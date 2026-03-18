import CoreGraphics

// MARK: - Render Node

/// A persistent node in the render tree. Either a leaf (custom drawing)
/// or a container (layout + children).
public final class RenderNode {
  public enum Content {
    case leaf(AnyDrawing)
    case container(AnyLayout, [RenderNode])
  }

  public var content: Content

  // Layout cache — the last proposal this node was measured with,
  // and the resulting size.
  public internal(set) var cachedSize: CGSize?
  public internal(set) var cachedProposal: CGFloat?

  /// Frame in document coordinates, assigned during layout.
  public internal(set) var frame: CGRect = .zero

  public init(_ content: Content) {
    self.content = content
  }

  // MARK: - Convenience constructors

  public static func leaf(_ drawing: AnyDrawing) -> RenderNode {
    RenderNode(.leaf(drawing))
  }

  public static func container(_ layout: AnyLayout, _ children: [RenderNode]) -> RenderNode {
    RenderNode(.container(layout, children))
  }

  // MARK: - Children

  public var children: [RenderNode] {
    switch content {
    case .leaf: []
    case let .container(_, children): children
    }
  }

  // MARK: - Cache invalidation

  /// Invalidate this node's cached size.
  public func invalidateLayout() {
    cachedSize = nil
    cachedProposal = nil
  }

  /// Invalidate this node and all ancestors.
  /// `ancestors` should be the path from root to this node (not including self).
  public static func invalidateUpward(_ ancestors: [RenderNode]) {
    for node in ancestors {
      node.invalidateLayout()
    }
  }
}

// MARK: - Layout Engine

public extension RenderNode {
  /// Full layout pass: measure with the given width, then assign frames.
  func layoutPass(width: CGFloat) {
    _ = measure(proposal: width)
    assignFrames(origin: .zero)
  }

  /// Measure this node given a width proposal. Returns the computed size.
  /// Uses cache when possible.
  func measure(proposal: CGFloat) -> CGSize {
    if let cached = cachedSize, cachedProposal == proposal {
      return cached
    }

    let size: CGSize

    switch content {
    case var .leaf(drawing):
      size = drawing.sizeThatFits(width: proposal)
      // Write back the drawing (it may have mutated its cache).
      content = .leaf(drawing)

    case let .container(layout, children):
      // Create measurable proxies — the layout decides what width each child gets.
      let subviews = children.map { child in
        LayoutSubview { proposal in
          child.measure(proposal: proposal)
        }
      }

      let result = layout.layout(subviews: subviews, proposal: proposal)
      size = result.size

      // Store placements on child nodes.
      for (i, child) in children.enumerated() {
        child.frame = CGRect(origin: result.placements[i].origin, size: result.placements[i].size)
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
        x: origin.x + child.frame.origin.x,
        y: origin.y + child.frame.origin.y
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
