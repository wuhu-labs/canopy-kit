import CoreGraphics

// MARK: - Render Node

/// A persistent node in the render tree. Either a leaf (custom drawing)
/// or a container (layout + children).
public final class RenderNode {
  public enum Content {
    case leaf(AnyDrawing)
    case container(AnyLayout, [RenderNode])
  }

  public let nodeID: NodeID?

  public var content: Content {
    didSet {
      updateChildParents(from: oldValue, to: content)
    }
  }

  weak var parent: RenderNode?

  // Layout cache — the last proposal this node was measured with,
  // and the resulting size.
  public internal(set) var cachedSize: CGSize?
  public internal(set) var cachedProposal: ProposedSize?

  /// Origin in parent-local coordinates, set by the parent's layout during measure.
  public internal(set) var localOrigin: CGPoint = .zero

  /// Frame in document coordinates, assigned during assignFrames.
  public internal(set) var frame: CGRect = .zero

  public init(_ content: Content, nodeID: NodeID? = nil) {
    self.nodeID = nodeID
    self.content = content
    updateChildParents(from: nil, to: content)
  }

  // MARK: - Convenience constructors

  public static func leaf(_ drawing: AnyDrawing, nodeID: NodeID? = nil) -> RenderNode {
    RenderNode(.leaf(drawing), nodeID: nodeID)
  }

  public static func container(
    _ layout: AnyLayout,
    _ children: [RenderNode],
    nodeID: NodeID? = nil
  ) -> RenderNode {
    RenderNode(.container(layout, children), nodeID: nodeID)
  }

  // MARK: - Children

  public var children: [RenderNode] {
    switch content {
    case .leaf: []
    case let .container(_, children): children
    }
  }

  // MARK: - Cache invalidation

  /// Invalidate this node's cached size and all ancestor caches to the root.
  public func invalidateLayout() {
    var node: RenderNode? = self

    while let current = node {
      current.cachedSize = nil
      current.cachedProposal = nil
      node = current.parent
    }
  }

  /// Invalidate this node and all ancestors.
  /// `ancestors` should be the path from root to this node (not including self).
  public static func invalidateUpward(_ ancestors: [RenderNode]) {
    ancestors.last?.invalidateLayout()
  }

  private func updateChildParents(from oldContent: Content?, to newContent: Content) {
    if case let .container(_, oldChildren) = oldContent {
      for child in oldChildren {
        if child.parent === self {
          child.parent = nil
        }
      }
    }

    if case let .container(_, newChildren) = newContent {
      for child in newChildren {
        child.parent = self
      }
    }
  }
}

// MARK: - Layout Engine

public extension RenderNode {
  /// Full layout pass: measure with the given width, then assign frames.
  func layoutPass(width: CGFloat) {
    _ = measure(proposal: ProposedSize(width: width, height: nil))
    assignFrames(origin: .zero)
  }

  /// Measure this node given a size proposal. Returns the computed size.
  /// Uses cache when possible.
  func measure(proposal: ProposedSize) -> CGSize {
    if let cached = cachedSize, cachedProposal == proposal {
      return cached
    }

    let size: CGSize

    switch content {
    case var .leaf(drawing):
      size = drawing.sizeThatFits(proposal: proposal)
      // Write back the drawing (it may have mutated its cache).
      content = .leaf(drawing)

    case let .container(layout, children):
      // Create measurable proxies — the layout decides what proposal each child gets.
      let subviews = children.map { child in
        LayoutSubview { proposal in
          child.measure(proposal: proposal)
        }
      }

      let result = layout.layout(subviews: subviews, proposal: proposal)
      precondition(
        result.placements.count == children.count,
        "Layout returned \(result.placements.count) placements for \(children.count) children."
      )
      size = result.size

      // Store placements on child nodes.
      for (i, child) in children.enumerated() {
        child.localOrigin = result.placements[i].origin
      }
    }

    cachedSize = size
    cachedProposal = proposal
    return size
  }

  /// Assign absolute frames in document coordinates.
  func assignFrames(origin: CGPoint) {
    let size = cachedSize ?? .zero
    frame = CGRect(origin: origin, size: size)

    for child in children {
      let childOrigin = CGPoint(
        x: origin.x + child.localOrigin.x,
        y: origin.y + child.localOrigin.y
      )
      child.assignFrames(origin: childOrigin)
    }
  }
}

// MARK: - Queries

public extension RenderNode {
  /// All leaf nodes in tree order.
  func leaves() -> [RenderNode] {
    switch content {
    case .leaf: [self]
    case let .container(_, children):
      children.flatMap { $0.leaves() }
    }
  }

  /// Leaf nodes whose frame intersects the given rect.
  func visibleLeaves(in rect: CGRect) -> [RenderNode] {
    guard frame.intersects(rect) else { return [] }
    switch content {
    case .leaf: return [self]
    case let .container(_, children):
      return children.flatMap { $0.visibleLeaves(in: rect) }
    }
  }
}
