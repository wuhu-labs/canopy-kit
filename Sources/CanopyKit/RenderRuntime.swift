import CoreGraphics
import IdentifiedCollections
import os.log
import SwiftUI

public struct PrimitiveCommitment: @unchecked Sendable {
  let primitive: Primitive
  let value: Any
}

public final class ResolvedRenderNode: Identifiable, @unchecked Sendable {
  public enum Content: @unchecked Sendable {
    case component(AnyComponent, ResolvedRenderNode)
    case layout(AnyLayout, IdentifiedArrayOf<ResolvedRenderNode>)
    case primitive(Primitive, PrimitiveCommitment?)
  }

  public let id: NodeID
  public let frame: CGRect
  /// The smallest rect (in the parent's coordinate space) that encloses this
  /// node's frame and the bounding rects of all descendants. Used by the lazy
  /// visible-tree projection to cull entire subtrees that fall outside the
  /// viewport, even when children overflow their parent's frame.
  public let boundingRect: CGRect
  public let values: NodeValues
  public let content: Content

  public init(
    id: NodeID,
    frame: CGRect,
    boundingRect: CGRect,
    values: NodeValues,
    content: Content
  ) {
    self.id = id
    self.frame = frame
    self.boundingRect = boundingRect
    self.values = values
    self.content = content
  }

  public var children: IdentifiedArrayOf<ResolvedRenderNode> {
    switch content {
    case let .component(_, child):
      [child]
    case let .layout(_, children):
      children
    case .primitive:
      []
    }
  }

  public func leaves() -> [ResolvedRenderNode] {
    switch content {
    case let .component(_, child):
      child.leaves()
    case .primitive:
      [self]
    case let .layout(_, children):
      children.flatMap { $0.leaves() }
    }
  }
}

public struct ResolvedRenderNodeView {
  public let node: ResolvedRenderNode
  public let frame: CGRect
  public let viewport: CGRect

  /// Lazily projects visible children by intersecting each child's bounding
  /// rect with the viewport. Each child's init is O(1), so iterating direct
  /// children is cheap; entire off-screen subtrees are never visited.
  public var children: [ResolvedRenderNodeView] {
    node.children.compactMap { child in
      ResolvedRenderNodeView(
        node: child,
        absoluteOrigin: frame.origin,
        viewport: viewport
      )
    }
  }

  /// O(1) construction. Checks whether this node's bounding rect intersects
  /// the viewport; returns nil if it doesn't. No child traversal at init time.
  public init?(node: ResolvedRenderNode, absoluteOrigin: CGPoint = .zero, viewport: CGRect) {
    let frame = node.frame.offsetBy(dx: absoluteOrigin.x, dy: absoluteOrigin.y)
    let absoluteBounds = node.boundingRect.offsetBy(dx: absoluteOrigin.x, dy: absoluteOrigin.y)

    guard absoluteBounds.intersects(viewport) else { return nil }

    self.node = node
    self.frame = frame
    self.viewport = viewport
  }

  public func leaves() -> [ResolvedRenderNodeView] {
    if case .primitive = node.content {
      return [self]
    }
    return children.flatMap { $0.leaves() }
  }
}

@MainActor
public final class RenderRuntime {
  private struct SizeCacheEntry {
    let proposal: ProposedSize
    let size: CGSize
  }

  private struct CacheEntry {
    var sizeLRU: [SizeCacheEntry] = []
    var preparationCache: Any?
    var commitment: PrimitiveCommitment?
    var lastResolvedNode: ResolvedNode?
    var lastResolvedRenderNode: ResolvedRenderNode?
  }

  private var cache: [NodeID: CacheEntry] = [:]
  private var parentByID: [NodeID: NodeID?] = [:]
  private var rootID: NodeID?
  private var previousRootRef: ObjectIdentifier?

  public init() {}

  public func reconcile(with root: ResolvedNode) {
    if let previousRootRef, ObjectIdentifier(root) == previousRootRef {
      return
    }
    previousRootRef = ObjectIdentifier(root)

    let signpostID = OSSignpostID(log: canopyLog)
    os_signpost(.begin, log: canopyLog, name: "RenderRuntime.reconcile", signpostID: signpostID)

    rootID = root.id
    reconcile(node: root, parentID: nil)

    os_signpost(
      .end,
      log: canopyLog,
      name: "RenderRuntime.reconcile",
      signpostID: signpostID,
      "cacheSize=%{public}d",
      cache.count
    )
  }

  @discardableResult
  public func sizeThatFits(root: ResolvedNode, proposal: ProposedSize) -> CGSize {
    reconcile(with: root)
    let signpostID = OSSignpostID(log: canopyLog)
    os_signpost(.begin, log: canopyLog, name: "RenderRuntime.sizeThatFits", signpostID: signpostID)
    let size = measure(node: root, proposal: proposal)
    os_signpost(.end, log: canopyLog, name: "RenderRuntime.sizeThatFits", signpostID: signpostID)
    return size
  }

  public func layout(
    root: ResolvedNode,
    proposal: ProposedSize
  ) -> ResolvedRenderNode {
    reconcile(with: root)
    let signpostID = OSSignpostID(log: canopyLog)
    os_signpost(.begin, log: canopyLog, name: "RenderRuntime.layout", signpostID: signpostID)
    let result = layout(node: root, proposal: proposal, origin: .zero)
    os_signpost(.end, log: canopyLog, name: "RenderRuntime.layout", signpostID: signpostID)
    return result
  }

  public func visibleView(
    root: ResolvedNode,
    proposal: ProposedSize,
    viewport: CGRect
  ) -> ResolvedRenderNodeView? {
    let renderRoot = layout(root: root, proposal: proposal)
    return ResolvedRenderNodeView(node: renderRoot, viewport: viewport)
  }

  private func reconcile(
    node: ResolvedNode,
    parentID: NodeID?
  ) {
    parentByID[node.id] = parentID

    var entry = cache[node.id] ?? CacheEntry()
    let previousResolvedNode = entry.lastResolvedNode

    // Pointer-equal → entire subtree is unchanged, done
    if entry.lastResolvedNode === node {
      return
    }

    // Collect old child IDs before updating
    let oldChildIDs: Set<NodeID> = if let old = previousResolvedNode {
      Set(old.children.map(\.id))
    } else {
      []
    }

    entry.lastResolvedNode = node
    entry.lastResolvedRenderNode = nil
    if !canReusePreparationCache(from: previousResolvedNode, to: node) {
      entry.preparationCache = nil
    }
    entry.commitment = nil
    entry.sizeLRU.removeAll()
    invalidateAncestors(of: node.id)
    cache[node.id] = entry

    // Recurse into new children
    let newChildIDs = Set(node.children.map(\.id))
    for child in node.children {
      reconcile(node: child, parentID: node.id)
    }

    // Remove cache entries for children that no longer exist
    let removedIDs = oldChildIDs.subtracting(newChildIDs)
    for id in removedIDs {
      removeSubtreeCache(id: id)
    }
  }

  private func removeSubtreeCache(id: NodeID) {
    guard let entry = cache[id] else { return }
    if let node = entry.lastResolvedNode {
      for child in node.children {
        removeSubtreeCache(id: child.id)
      }
    }
    cache[id] = nil
    parentByID[id] = nil
  }

  private func invalidateAncestors(of id: NodeID) {
    var current = parentByID[id] ?? nil
    while let ancestor = current {
      guard var entry = cache[ancestor] else { break }
      entry.sizeLRU.removeAll()
      cache[ancestor] = entry
      current = parentByID[ancestor] ?? nil
    }
  }

  private func measure(node: ResolvedNode, proposal: ProposedSize) -> CGSize {
    if let size = cachedSize(for: node.id, proposal: proposal) {
      os_signpost(.event, log: canopyLog, name: "sizeCacheHit")
      return size
    }
    os_signpost(.event, log: canopyLog, name: "sizeCacheMiss")

    var entry = cache[node.id] ?? CacheEntry()
    let size: CGSize

    switch node.content {
    case let .component(_, child):
      size = measure(node: child, proposal: proposal)

    case let .layout(layout, children):
      let subviews = children.map { child in
        LayoutSubview(
          { childProposal in
            self.measure(node: child, proposal: childProposal)
          },
          nodeValues: child.values
        )
      }
      size = layout.layout(subviews: subviews, proposal: proposal).size

    case let .primitive(primitive):
      size = measurePrimitive(
        primitive,
        proposal: proposal,
        entry: &entry
      )
    }

    remember(size: size, proposal: proposal, for: node.id, entry: entry)
    return size
  }

  private func layout(
    node: ResolvedNode,
    proposal: ProposedSize,
    origin: CGPoint
  ) -> ResolvedRenderNode {
    let size = measure(node: node, proposal: proposal)
    var entry = cache[node.id] ?? CacheEntry()
    let frame = CGRect(origin: origin, size: size)

    if let existing = entry.lastResolvedRenderNode,
       entry.lastResolvedNode === node,
       existing.frame == frame
    {
      os_signpost(.event, log: canopyLog, name: "renderNodeReused")
      return existing
    }
    os_signpost(.event, log: canopyLog, name: "renderNodeCreated")

    let renderNode: ResolvedRenderNode

    switch node.content {
    case let .component(component, child):
      let renderChild = layout(
        node: child,
        proposal: proposal,
        origin: .zero
      )
      let boundingRect = frame.union(
        renderChild.boundingRect.offsetBy(dx: frame.origin.x, dy: frame.origin.y)
      )
      renderNode = ResolvedRenderNode(
        id: node.id,
        frame: frame,
        boundingRect: boundingRect,
        values: node.values,
        content: .component(component, renderChild)
      )

    case let .layout(layoutValue, children):
      let subviews = children.map { child in
        LayoutSubview(
          { childProposal in
            self.measure(node: child, proposal: childProposal)
          },
          nodeValues: child.values
        )
      }
      let result = layoutValue.layout(subviews: subviews, proposal: proposal)

      let renderChildren = IdentifiedArray(
        uniqueElements: zip(children, result.placements).map { child, placement in
          layout(
            node: child,
            proposal: placement.proposal,
            origin: placement.origin
          )
        }
      )
      var boundingRect = frame
      for child in renderChildren {
        boundingRect = boundingRect.union(
          child.boundingRect.offsetBy(dx: frame.origin.x, dy: frame.origin.y)
        )
      }
      renderNode = ResolvedRenderNode(
        id: node.id,
        frame: frame,
        boundingRect: boundingRect,
        values: node.values,
        content: .layout(layoutValue, renderChildren)
      )

    case let .primitive(primitive):
      let commitment = makeCommitment(
        primitive,
        size: size,
        entry: &entry
      )
      renderNode = ResolvedRenderNode(
        id: node.id,
        frame: frame,
        boundingRect: frame,
        values: node.values,
        content: .primitive(primitive, commitment)
      )
    }

    entry.lastResolvedNode = node
    entry.lastResolvedRenderNode = renderNode
    cache[node.id] = entry
    return renderNode
  }

  private func measurePrimitive(
    _ primitive: Primitive,
    proposal: ProposedSize,
    entry: inout CacheEntry
  ) -> CGSize {
    let representable = primitive.viewRepresentable
    if entry.preparationCache == nil {
      entry.preparationCache = representable.makeCache()
    } else {
      representable.updateCache(cache: &entry.preparationCache!)
    }
    return representable.sizeThatFits(
      proposal: proposal,
      cache: &entry.preparationCache!
    )
  }

  private func makeCommitment(
    _ primitive: Primitive,
    size: CGSize,
    entry: inout CacheEntry
  ) -> PrimitiveCommitment {
    let commitment = PrimitiveCommitment(
      primitive: primitive,
      value: primitive.viewRepresentable.makeCommitment(
        in: CGRect(origin: .zero, size: size),
        cache: entry.preparationCache!
      )
    )
    entry.commitment = commitment
    return commitment
  }

  private func cachedSize(for id: NodeID, proposal: ProposedSize) -> CGSize? {
    guard let entry = cache[id] else { return nil }
    return entry.sizeLRU.first(where: { $0.proposal == proposal })?.size
  }

  private func remember(
    size: CGSize,
    proposal: ProposedSize,
    for id: NodeID,
    entry: CacheEntry
  ) {
    var entry = entry
    entry.sizeLRU.removeAll(where: { $0.proposal == proposal })
    entry.sizeLRU.insert(SizeCacheEntry(proposal: proposal, size: size), at: 0)
    if entry.sizeLRU.count > 4 {
      entry.sizeLRU.removeLast(entry.sizeLRU.count - 4)
    }
    cache[id] = entry
  }
}

private func canReusePreparationCache(from oldNode: ResolvedNode?, to newNode: ResolvedNode) -> Bool {
  guard let oldNode else { return false }

  switch (oldNode.content, newNode.content) {
  case (.primitive, .primitive):
    return true
  default:
    return false
  }
}
