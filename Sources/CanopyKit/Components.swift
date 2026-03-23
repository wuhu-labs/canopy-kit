import Collections
import IdentifiedCollections
import Observation
import os.log
import SwiftUI

public struct NodeID: Hashable, Sendable, Comparable {
  public let rawValue: Int

  public init(rawValue: Int) {
    self.rawValue = rawValue
  }

  public static let root = NodeID(rawValue: 0)

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// A min-heap entry that orders pending dirty nodes by (depth, id), so
/// shallower ancestors are always processed before their descendants.
private struct PendingEntry: Comparable {
  let depth: Int
  let id: NodeID

  static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.depth == rhs.depth ? lhs.id < rhs.id : lhs.depth < rhs.depth
  }
}

@MainActor
public protocol Component {
  func body() -> Node
}

public struct Node: @unchecked Sendable {
  public var content: NodeContent
  public var values: NodeValues

  public init(content: NodeContent, values: NodeValues = NodeValues()) {
    self.content = content
    self.values = values
  }
}

public enum NodeContent: @unchecked Sendable {
  case component(AnyComponent)
  case layout(AnyLayout, IdentifiedArrayOf<IdentifiedNode>)
  case primitive(Primitive)
}

public struct IdentifiedNode: Identifiable, @unchecked Sendable {
  public var id: AnyHashable
  public var node: Node

  public init(id: AnyHashable, node: Node) {
    self.id = id
    self.node = node
  }

  public init(id: some Hashable, node: Node) {
    self.init(id: AnyHashable(id), node: node)
  }
}

public extension Node {
  static func component(_ component: AnyComponent, values: NodeValues = NodeValues()) -> Self {
    Self(content: .component(component), values: values)
  }

  static func layout(
    _ layout: AnyLayout,
    children: IdentifiedArrayOf<IdentifiedNode>,
    values: NodeValues = NodeValues()
  ) -> Self {
    Self(content: .layout(layout, children), values: values)
  }

  static func primitive(_ primitive: Primitive, values: NodeValues = NodeValues()) -> Self {
    Self(content: .primitive(primitive), values: values)
  }

  static func drawing(_ drawing: some CustomDrawing, values: NodeValues = NodeValues()) -> Self {
    Self.primitive(.init(drawing), values: values)
  }

  static func shape(_ shape: some Shape, values: NodeValues = NodeValues()) -> Self {
    Self.primitive(.init(shape), values: values)
  }

  static func view(
    _ representable: some CustomViewRepresentable,
    values: NodeValues = NodeValues()
  ) -> Self {
    primitive(.init(representable), values: values)
  }

  // MARK: Leaf Factories

  /// Convenience: creates a text drawing node.
  static func text(_ string: String, fontSize: CGFloat = 14) -> Self {
    drawing(TextDrawing(string, fontSize: fontSize))
  }

  /// Convenience: creates a text drawing node from an attributed string.
  static func text(attributedString: CFAttributedString) -> Self {
    drawing(TextDrawing(attributedString: attributedString))
  }

  // MARK: Layout Convenience (NodeBuilder)

  static func vstack(spacing: CGFloat = 0, @NodeBuilder _ children: () -> IdentifiedArrayOf<IdentifiedNode>) -> Self {
    layout(AnyLayout(VStackLayout(spacing: spacing)), children: children())
  }

  static func hstack(spacing: CGFloat = 0, @NodeBuilder _ children: () -> IdentifiedArrayOf<IdentifiedNode>) -> Self {
    layout(AnyLayout(HStackLayout(spacing: spacing)), children: children())
  }

  static func zstack(@NodeBuilder _ children: () -> IdentifiedArrayOf<IdentifiedNode>) -> Self {
    layout(AnyLayout(ZStackLayout()), children: children())
  }

  // MARK: Keying

  /// Wraps this node in an ``IdentifiedNode`` with the given key.
  func keyed(_ key: some Hashable) -> IdentifiedNode {
    IdentifiedNode(id: key, node: self)
  }
}

public extension IdentifiedNode {
  static func component(
    key: some Hashable,
    _ component: AnyComponent,
    values: NodeValues = NodeValues()
  ) -> Self {
    Self(id: key, node: .component(component, values: values))
  }

  static func layout(
    key: some Hashable,
    _ layout: AnyLayout,
    children: IdentifiedArrayOf<IdentifiedNode>,
    values: NodeValues = NodeValues()
  ) -> Self {
    Self(id: key, node: .layout(layout, children: children, values: values))
  }

  static func primitive(
    key: some Hashable,
    _ primitive: Primitive,
    values: NodeValues = NodeValues()
  ) -> Self {
    Self(id: key, node: .primitive(primitive, values: values))
  }

  static func drawing(
    key: some Hashable,
    _ drawing: some CustomDrawing,
    values: NodeValues = NodeValues()
  ) -> Self {
    Self.primitive(key: key, .init(drawing), values: values)
  }

  static func shape(
    key: some Hashable,
    _ shape: some Shape,
    values: NodeValues = NodeValues()
  ) -> Self {
    Self.primitive(key: key, .init(shape), values: values)
  }

  static func view(
    key: some Hashable,
    _ representable: some CustomViewRepresentable,
    values: NodeValues = NodeValues()
  ) -> Self {
    Self.primitive(key: key, .init(representable), values: values)
  }
}

public struct AnyComponent: @unchecked Sendable {
  private let value: any Component

  public init(_ component: some Component) {
    value = component
  }

  @MainActor
  public func body() -> Node {
    value.body()
  }

  func isEquivalent(to other: AnyComponent) -> Bool {
    compareComponent(lhs: value, rhs: other.value)
  }
}

private func compareComponent<C: Component>(lhs: C, rhs: any Component) -> Bool {
  guard let rhs = rhs as? C else { return false }
  return defaultValueIsEquivalent(lhs, rhs)
}

public final class ResolvedNode: Identifiable, @unchecked Sendable {
  public enum Content: @unchecked Sendable {
    case component(AnyComponent, ResolvedNode)
    case layout(AnyLayout, IdentifiedArrayOf<ResolvedNode>)
    case primitive(Primitive)
  }

  public let id: NodeID
  public let content: Content
  public let values: NodeValues

  public init(id: NodeID, content: Content, values: NodeValues = NodeValues()) {
    self.id = id
    self.content = content
    self.values = values
  }

  public var children: IdentifiedArrayOf<ResolvedNode> {
    switch content {
    case let .component(_, child):
      [child]
    case let .layout(_, children):
      children
    case .primitive:
      []
    }
  }
}

@MainActor
private struct RuntimeEntry {
  let id: NodeID
  let parentID: NodeID?
  let depth: Int

  var component: AnyComponent
  var values: NodeValues
  var body: Node?
  var resolvedNode: ResolvedNode?
  var childComponents: [DeclarationPath: NodeID] = [:]
  var localNodes: [DeclarationPath: LocalNodeIdentity] = [:]
  var localResolvedNodes: [DeclarationPath: ResolvedNode] = [:]
}

private typealias DeclarationPath = [AnyHashable]

private struct CollectedComponentNode {
  let path: DeclarationPath
  let node: Node
}

private struct CollectedLocalNode {
  let path: DeclarationPath
  let kind: LocalNodeKind
}

private struct LocalNodeIdentity {
  let id: NodeID
  let kind: LocalNodeKind
}

private enum LocalNodeKind {
  case layout
  case primitive
}

@MainActor
@Observable
public final class ComponentRenderer {
  @ObservationIgnored private var nextID = NodeID.root.rawValue + 1
  @ObservationIgnored private var registry: [NodeID: RuntimeEntry]
  @ObservationIgnored private var dirtyIDs: Set<NodeID>
  @ObservationIgnored private var refreshScheduled = false

  public private(set) var resolvedRoot: ResolvedNode
  public private(set) var revision = 0

  public init(root: AnyComponent) {
    registry = [
      .root: RuntimeEntry(
        id: .root,
        parentID: nil,
        depth: 0,
        component: root,
        values: NodeValues()
      ),
    ]
    dirtyIDs = [.root]
    resolvedRoot = ResolvedNode(id: .root, content: .primitive(.init(PlaceholderDrawing())))
    refresh()
  }

  public func updateRoot(_ root: AnyComponent) {
    guard var entry = registry[.root] else { return }
    guard !entry.component.isEquivalent(to: root) else { return }
    entry.component = root
    registry[.root] = entry
    markDirty(.root)
    scheduleRefresh()
  }

  public func refresh() {
    let signpostID = OSSignpostID(log: canopyLog)
    os_signpost(.begin, log: canopyLog, name: "ComponentRenderer.refresh", signpostID: signpostID)
    let (resolvedRoot, didChange) = refreshResolvedTree()
    os_signpost(.end, log: canopyLog, name: "ComponentRenderer.refresh", signpostID: signpostID)
    guard didChange, let resolvedRoot else { return }

    self.resolvedRoot = resolvedRoot
    revision &+= 1
  }

  private func refreshResolvedTree() -> (ResolvedNode?, Bool) {
    guard !dirtyIDs.isEmpty || registry[.root]?.resolvedNode == nil else {
      return (registry[.root]?.resolvedNode, false)
    }

    let signpostID = OSSignpostID(log: canopyLog)
    os_signpost(.begin, log: canopyLog, name: "refreshResolvedTree", signpostID: signpostID)

    var pending = Heap(dirtyIDs.compactMap { id in
      registry[id].map { PendingEntry(depth: $0.depth, id: id) }
    })
    dirtyIDs.removeAll()

    var pendingIDs = Set(pending.unordered.map(\.id))
    var rebuildIDs: Set<NodeID> = []

    while let pendingEntry = pending.popMin() {
      let id = pendingEntry.id
      pendingIDs.remove(id)

      guard var entry = registry[id] else { continue }

      let newBody = withObservationTracking {
        entry.component.body()
      } onChange: { [weak self] in
        Task { @MainActor in
          self?.markDirty(id)
          self?.scheduleRefresh()
        }
      }
      os_signpost(.event, log: canopyLog, name: "bodyEvaluated")

      let oldBody = entry.body
      entry.body = newBody
      registry[id] = entry

      let childResult = reconcileChildComponents(parentID: id, body: newBody)
      reconcileLocalNodes(parentID: id, body: newBody)
      let bodyChanged = oldBody.map { !nodesAreEquivalent($0, newBody) } ?? true

      if bodyChanged {
        rebuildIDs.insert(id)
      }
      rebuildIDs.formUnion(childResult.rebuildIDs)

      for dirtyChildID in childResult.dirtyIDs where pendingIDs.insert(dirtyChildID).inserted {
        guard let childEntry = registry[dirtyChildID] else { continue }
        pending.insert(PendingEntry(depth: childEntry.depth, id: dirtyChildID))
      }
    }

    for id in rebuildIDs {
      var current = registry[id]?.parentID
      while let ancestorID = current {
        let inserted = rebuildIDs.insert(ancestorID).inserted
        if !inserted { break }
        current = registry[ancestorID]?.parentID
      }
    }

    guard let resolvedRoot = rebuildResolvedSubtree(for: .root, rebuildIDs: rebuildIDs) else {
      os_signpost(.end, log: canopyLog, name: "refreshResolvedTree", signpostID: signpostID)
      return (nil, false)
    }
    os_signpost(.end, log: canopyLog, name: "refreshResolvedTree", signpostID: signpostID)
    return (resolvedRoot, true)
  }

  private func markDirty(_ id: NodeID) {
    dirtyIDs.insert(id)
  }

  private func scheduleRefresh() {
    guard !refreshScheduled else { return }
    refreshScheduled = true

    Task { @MainActor in
      await Task.yield()
      refreshScheduled = false
      refresh()
    }
  }

  private func reconcileChildComponents(
    parentID: NodeID,
    body: Node
  ) -> (dirtyIDs: Set<NodeID>, rebuildIDs: Set<NodeID>) {
    guard var parentEntry = registry[parentID] else { return ([], []) }

    let oldChildren = parentEntry.childComponents
    let collectedChildren = collectComponentNodes(in: body)
    var dirtyChildren: Set<NodeID> = []
    var rebuildIDs: Set<NodeID> = []
    var newChildren: [DeclarationPath: NodeID] = [:]

    for collectedChild in collectedChildren {
      guard case let .component(component) = collectedChild.node.content else { continue }

      if let existingID = oldChildren[collectedChild.path], var existingEntry = registry[existingID] {
        let componentChanged = !existingEntry.component.isEquivalent(to: component)
        let valuesChanged = !existingEntry.values.isEquivalent(to: collectedChild.node.values)

        existingEntry.component = component
        existingEntry.values = collectedChild.node.values
        registry[existingID] = existingEntry
        newChildren[collectedChild.path] = existingID

        if componentChanged {
          dirtyChildren.insert(existingID)
        }
        if valuesChanged {
          rebuildIDs.insert(existingID)
        }
      } else {
        let id = allocateID()
        registry[id] = RuntimeEntry(
          id: id,
          parentID: parentID,
          depth: parentEntry.depth + 1,
          component: component,
          values: collectedChild.node.values
        )
        newChildren[collectedChild.path] = id
        dirtyChildren.insert(id)
        rebuildIDs.insert(id)
        os_signpost(.event, log: canopyLog, name: "componentCreated")
      }
    }

    let removedIDs = Set(oldChildren.values).subtracting(newChildren.values)
    for removedID in removedIDs {
      removeComponentSubtree(id: removedID)
      os_signpost(.event, log: canopyLog, name: "componentRemoved")
    }

    parentEntry.childComponents = newChildren
    registry[parentID] = parentEntry
    return (dirtyChildren, rebuildIDs)
  }

  private func reconcileLocalNodes(parentID: NodeID, body: Node) {
    guard var parentEntry = registry[parentID] else { return }

    let oldNodes = parentEntry.localNodes
    let collectedNodes = collectLocalNodes(in: body)
    var newNodes: [DeclarationPath: LocalNodeIdentity] = [:]

    for collectedNode in collectedNodes {
      if let existing = oldNodes[collectedNode.path], existing.kind == collectedNode.kind {
        newNodes[collectedNode.path] = existing
      } else {
        newNodes[collectedNode.path] = LocalNodeIdentity(
          id: allocateID(),
          kind: collectedNode.kind
        )
      }
    }

    parentEntry.localNodes = newNodes
    parentEntry.localResolvedNodes = parentEntry.localResolvedNodes.filter { newNodes[$0.key] != nil }
    registry[parentID] = parentEntry
  }

  private func rebuildResolvedSubtree(
    for id: NodeID,
    rebuildIDs: Set<NodeID>
  ) -> ResolvedNode? {
    guard var entry = registry[id], let body = entry.body else {
      return registry[id]?.resolvedNode
    }

    if !rebuildIDs.contains(id), let resolvedNode = entry.resolvedNode {
      return resolvedNode
    }

    var localResolvedNodes: [DeclarationPath: ResolvedNode] = [:]
    let resolvedChild = resolveBody(
      body,
      for: id,
      path: [],
      rebuildIDs: rebuildIDs,
      localResolvedNodes: &localResolvedNodes
    )
    let resolvedNode = reuseComponentNode(
      existing: entry.resolvedNode,
      component: entry.component,
      child: resolvedChild,
      id: entry.id,
      values: entry.values
    )
    entry.localResolvedNodes = localResolvedNodes
    entry.resolvedNode = resolvedNode
    registry[id] = entry
    return resolvedNode
  }

  private func resolveBody(
    _ node: Node,
    for ownerID: NodeID,
    path: DeclarationPath,
    rebuildIDs: Set<NodeID>,
    localResolvedNodes: inout [DeclarationPath: ResolvedNode]
  ) -> ResolvedNode {
    switch node.content {
    case .component:
      guard let childID = registry[ownerID]?.childComponents[path] else {
        preconditionFailure("Missing runtime entry for child component at path \(path)")
      }
      guard let child = rebuildResolvedSubtree(for: childID, rebuildIDs: rebuildIDs) else {
        preconditionFailure("Missing resolved subtree for component \(childID)")
      }
      return child

    case let .layout(layout, children):
      let resolvedChildren = IdentifiedArray(
        uniqueElements: children.map { child in
          resolveIdentifiedNode(
            child,
            ownerID: ownerID,
            path: path + [child.id],
            rebuildIDs: rebuildIDs,
            localResolvedNodes: &localResolvedNodes
          )
        }
      )
      let resolvedNode = reuseLayoutNode(
        existing: registry[ownerID]?.localResolvedNodes[path],
        layout: layout,
        children: resolvedChildren,
        id: localNodeID(for: ownerID, path: path, kind: .layout),
        values: node.values
      )
      localResolvedNodes[path] = resolvedNode
      return resolvedNode

    case let .primitive(primitive):
      let resolvedNode = reusePrimitiveNode(
        existing: registry[ownerID]?.localResolvedNodes[path],
        primitive: primitive,
        id: localNodeID(for: ownerID, path: path, kind: .primitive),
        values: node.values
      )
      localResolvedNodes[path] = resolvedNode
      return resolvedNode
    }
  }

  private func resolveIdentifiedNode(
    _ identifiedNode: IdentifiedNode,
    ownerID: NodeID,
    path: DeclarationPath,
    rebuildIDs: Set<NodeID>,
    localResolvedNodes: inout [DeclarationPath: ResolvedNode]
  ) -> ResolvedNode {
    resolveBody(
      identifiedNode.node,
      for: ownerID,
      path: path,
      rebuildIDs: rebuildIDs,
      localResolvedNodes: &localResolvedNodes
    )
  }

  private func collectComponentNodes(in root: Node) -> [CollectedComponentNode] {
    var collected: [CollectedComponentNode] = []
    collectComponentNodes(in: root, trail: [], into: &collected)
    return collected
  }

  private func collectComponentNodes(
    in node: Node,
    trail: DeclarationPath,
    into collected: inout [CollectedComponentNode]
  ) {
    switch node.content {
    case .component:
      collected.append(CollectedComponentNode(path: trail, node: node))

    case let .layout(_, children):
      for child in children {
        collectComponentNodes(
          in: child.node,
          trail: trail + [child.id],
          into: &collected
        )
      }

    case .primitive:
      break
    }
  }

  private func collectLocalNodes(in root: Node) -> [CollectedLocalNode] {
    var collected: [CollectedLocalNode] = []
    collectLocalNodes(in: root, trail: [], into: &collected)
    return collected
  }

  private func collectLocalNodes(
    in node: Node,
    trail: DeclarationPath,
    into collected: inout [CollectedLocalNode]
  ) {
    switch node.content {
    case .component:
      break

    case let .layout(_, children):
      collected.append(CollectedLocalNode(path: trail, kind: .layout))
      for child in children {
        collectLocalNodes(
          in: child.node,
          trail: trail + [child.id],
          into: &collected
        )
      }

    case .primitive:
      collected.append(CollectedLocalNode(path: trail, kind: .primitive))
    }
  }

  private func removeComponentSubtree(id: NodeID) {
    guard let entry = registry[id] else { return }

    for childID in entry.childComponents.values {
      removeComponentSubtree(id: childID)
    }

    dirtyIDs.remove(id)
    registry[id] = nil
  }

  private func localNodeID(
    for ownerID: NodeID,
    path: DeclarationPath,
    kind: LocalNodeKind
  ) -> NodeID {
    guard let entry = registry[ownerID] else {
      preconditionFailure("Missing runtime entry for owner \(ownerID)")
    }
    guard let identity = entry.localNodes[path], identity.kind == kind else {
      preconditionFailure("Missing local \(kind) node identity at path \(path) for owner \(ownerID)")
    }
    return identity.id
  }

  private func allocateID() -> NodeID {
    defer { nextID += 1 }
    return NodeID(rawValue: nextID)
  }
}

public struct ComponentTreeView: View {
  @State private var renderer: ComponentRenderer
  private let root: AnyComponent

  public init(root: AnyComponent) {
    self.root = root
    _renderer = State(initialValue: ComponentRenderer(root: root))
  }

  public var body: some View {
    renderer.updateRoot(root)
    return RenderTreeView(root: renderer.resolvedRoot, revision: renderer.revision)
  }
}

private func nodesAreEquivalent(_ lhs: Node, _ rhs: Node) -> Bool {
  guard lhs.values.isEquivalent(to: rhs.values) else { return false }

  switch (lhs.content, rhs.content) {
  case let (.component(lhsComponent), .component(rhsComponent)):
    return lhsComponent.isEquivalent(to: rhsComponent)

  case let (.layout(lhsLayout, lhsChildren), .layout(rhsLayout, rhsChildren)):
    guard lhsLayout.isEquivalent(to: rhsLayout) else { return false }
    guard lhsChildren.count == rhsChildren.count else { return false }

    for (lhsChild, rhsChild) in zip(lhsChildren, rhsChildren) {
      guard lhsChild.id == rhsChild.id else { return false }
      guard nodesAreEquivalent(lhsChild.node, rhsChild.node) else { return false }
    }

    return true

  case let (.primitive(lhsPrimitive), .primitive(rhsPrimitive)):
    return lhsPrimitive.isEquivalent(to: rhsPrimitive)

  default:
    return false
  }
}

private func reuseComponentNode(
  existing: ResolvedNode?,
  component: AnyComponent,
  child: ResolvedNode,
  id: NodeID,
  values: NodeValues
) -> ResolvedNode {
  guard let existing else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .component(component, child), values: values)
  }
  guard existing.id == id else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .component(component, child), values: values)
  }
  guard existing.values.isEquivalent(to: values) else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .component(component, child), values: values)
  }
  guard case let .component(existingComponent, existingChild) = existing.content else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .component(component, child), values: values)
  }
  guard existingComponent.isEquivalent(to: component), existingChild === child else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .component(component, child), values: values)
  }
  os_signpost(.event, log: canopyLog, name: "resolvedNodeReused")
  return existing
}

private func reuseLayoutNode(
  existing: ResolvedNode?,
  layout: AnyLayout,
  children: IdentifiedArrayOf<ResolvedNode>,
  id: NodeID,
  values: NodeValues
) -> ResolvedNode {
  guard let existing else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .layout(layout, children), values: values)
  }
  guard existing.id == id else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .layout(layout, children), values: values)
  }
  guard existing.values.isEquivalent(to: values) else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .layout(layout, children), values: values)
  }
  guard case let .layout(existingLayout, existingChildren) = existing.content else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .layout(layout, children), values: values)
  }
  guard existingLayout.isEquivalent(to: layout) else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .layout(layout, children), values: values)
  }
  guard existingChildren.count == children.count else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .layout(layout, children), values: values)
  }
  for (existingChild, child) in zip(existingChildren, children) where existingChild !== child {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .layout(layout, children), values: values)
  }
  os_signpost(.event, log: canopyLog, name: "resolvedNodeReused")
  return existing
}

private func reusePrimitiveNode(
  existing: ResolvedNode?,
  primitive: Primitive,
  id: NodeID,
  values: NodeValues
) -> ResolvedNode {
  guard let existing else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .primitive(primitive), values: values)
  }
  guard existing.id == id else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .primitive(primitive), values: values)
  }
  guard existing.values.isEquivalent(to: values) else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .primitive(primitive), values: values)
  }
  guard case let .primitive(existingPrimitive) = existing.content else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .primitive(primitive), values: values)
  }
  guard existingPrimitive.isEquivalent(to: primitive) else {
    os_signpost(.event, log: canopyLog, name: "resolvedNodeCreated")
    return ResolvedNode(id: id, content: .primitive(primitive), values: values)
  }
  os_signpost(.event, log: canopyLog, name: "resolvedNodeReused")
  return existing
}

// MARK: - Placeholder Drawing

/// Zero-size drawing used as a throwaway seed for `ComponentRenderer`
/// before the first `refresh()` replaces it.
private struct PlaceholderDrawing: CustomDrawing {
  typealias Commitment = CGRect

  func sizeThatFits(proposal _: ProposedSize, cache _: inout Void) -> CGSize {
    .zero
  }

  func makeCommitment(in bounds: CGRect, cache _: Void) -> CGRect {
    bounds
  }

  func draw(in _: CGContext, commitment _: CGRect) {}
}
