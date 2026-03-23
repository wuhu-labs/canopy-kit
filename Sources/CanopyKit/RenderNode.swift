import CoreGraphics
import IdentifiedCollections

/// A persistent node in the render tree.
public final class RenderNode {
  public enum Content {
    case component(AnyComponent, RenderNode)
    case primitive(Primitive)
    case container(AnyLayout, [RenderNode])

    public static func leaf(_ drawing: AnyDrawing) -> Self {
      .primitive(.customDrawing(drawing))
    }
  }

  public let nodeID: NodeID

  public var values: NodeValues

  public var content: Content {
    didSet {
      updateChildParents(from: oldValue, to: content)
    }
  }

  public internal(set) var resolvedNode: ResolvedNode

  weak var parent: RenderNode?

  public internal(set) var cachedSize: CGSize?
  public internal(set) var cachedProposal: ProposedSize?
  public internal(set) var localOrigin: CGPoint = .zero
  public internal(set) var frame: CGRect = .zero
  public internal(set) var primitiveCache: Any?

  public init(
    _ content: Content,
    nodeID: NodeID,
    values: NodeValues = NodeValues(),
    resolvedNode: ResolvedNode
  ) {
    self.nodeID = nodeID
    self.values = values
    self.content = content
    self.resolvedNode = resolvedNode
    updateChildParents(from: nil, to: content)
  }

  public static func leaf(
    _ drawing: AnyDrawing,
    nodeID: NodeID? = nil,
    values: NodeValues = NodeValues()
  ) -> RenderNode {
    let nodeID = nodeID ?? temporaryNodeID()
    let resolved = ResolvedNode(
      id: nodeID,
      content: .primitive(.customDrawing(drawing)),
      values: values
    )
    return RenderNode(
      .primitive(.customDrawing(drawing)),
      nodeID: nodeID,
      values: values,
      resolvedNode: resolved
    )
  }

  public static func container(
    _ layout: AnyLayout,
    _ children: [RenderNode],
    nodeID: NodeID? = nil,
    values: NodeValues = NodeValues()
  ) -> RenderNode {
    let nodeID = nodeID ?? temporaryNodeID()
    let resolved = ResolvedNode(
      id: nodeID,
      content: .layout(layout, IdentifiedArray(uniqueElements: children.map(\.resolvedNode))),
      values: values
    )
    return RenderNode(
      .container(layout, children),
      nodeID: nodeID,
      values: values,
      resolvedNode: resolved
    )
  }

  public var children: [RenderNode] {
    switch content {
    case let .component(_, child):
      [child]
    case .primitive:
      []
    case let .container(_, children):
      children
    }
  }

  public func invalidateLayout() {
    var node: RenderNode? = self
    while let current = node {
      current.cachedSize = nil
      current.cachedProposal = nil
      node = current.parent
    }
  }

  public static func invalidateUpward(_ ancestors: [RenderNode]) {
    ancestors.last?.invalidateLayout()
  }

  private func updateChildParents(from oldContent: Content?, to newContent: Content) {
    switch oldContent {
    case let .component(_, child):
      if child.parent === self {
        child.parent = nil
      }
    case let .container(_, children):
      for child in children where child.parent === self {
        child.parent = nil
      }
    case .primitive, nil:
      break
    }

    switch newContent {
    case let .component(_, child):
      child.parent = self
    case let .container(_, children):
      for child in children {
        child.parent = self
      }
    case .primitive:
      break
    }
  }
}

private func temporaryNodeID() -> NodeID {
  NodeID(rawValue: Int.random(in: 1 ... Int.max))
}

public extension RenderNode {
  func layoutPass(width: CGFloat) {
    _ = measure(proposal: ProposedSize(width: width, height: nil))
    assignFrames(origin: .zero)
  }

  func measure(proposal: ProposedSize) -> CGSize {
    if let cachedSize, cachedProposal == proposal {
      return cachedSize
    }

    let size: CGSize

    switch content {
    case let .component(_, child):
      child.localOrigin = .zero
      size = child.measure(proposal: proposal)

    case let .primitive(primitive):
      size = measurePrimitive(primitive, proposal: proposal)

    case let .container(layout, children):
      let subviews = children.map { child in
        LayoutSubview(
          { proposal in
            child.measure(proposal: proposal)
          },
          nodeValues: child.values
        )
      }
      let result = layout.layout(subviews: subviews, proposal: proposal)
      precondition(
        result.placements.count == children.count,
        "Layout returned \(result.placements.count) placements for \(children.count) children."
      )
      size = result.size
      for (index, child) in children.enumerated() {
        child.localOrigin = result.placements[index].origin
      }
    }

    cachedSize = size
    cachedProposal = proposal
    return size
  }

  func assignFrames(origin: CGPoint) {
    let size = cachedSize ?? .zero
    frame = CGRect(origin: origin, size: size)

    switch content {
    case let .component(_, child):
      child.assignFrames(origin: origin)

    case .primitive:
      break

    case .container:
      for child in children {
        let childOrigin = CGPoint(
          x: origin.x + child.localOrigin.x,
          y: origin.y + child.localOrigin.y
        )
        child.assignFrames(origin: childOrigin)
      }
    }
  }

  private func measurePrimitive(_ primitive: Primitive, proposal: ProposedSize) -> CGSize {
    switch primitive {
    case let .shape(shape):
      return shape.sizeThatFits(proposal: proposal)

    case let .customDrawing(drawing):
      if primitiveCache == nil {
        primitiveCache = drawing.makeCache()
      }
      return drawing.sizeThatFits(proposal: proposal, cache: &primitiveCache!)

    case let .customView(representable):
      if primitiveCache == nil {
        primitiveCache = representable.makeCache()
      }
      return representable.sizeThatFits(proposal: proposal, cache: &primitiveCache!)
    }
  }
}

public extension RenderNode {
  func leaves() -> [RenderNode] {
    switch content {
    case let .component(_, child):
      child.leaves()
    case .primitive:
      [self]
    case let .container(_, children):
      children.flatMap { $0.leaves() }
    }
  }

  func visibleLeaves(in rect: CGRect) -> [RenderNode] {
    guard frame.intersects(rect) else { return [] }
    switch content {
    case let .component(_, child):
      return child.visibleLeaves(in: rect)
    case .primitive:
      return [self]
    case let .container(_, children):
      return children.flatMap { $0.visibleLeaves(in: rect) }
    }
  }
}
