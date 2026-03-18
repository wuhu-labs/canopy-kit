import CoreGraphics

// MARK: - Layout

/// Pure geometry: given child size proxies and a size proposal, place children
/// and return the container's size.
public protocol Layout {
  func sizeThatFits(
    children: [LayoutChild],
    proposal: CGFloat
  ) -> CGSize

  func placeChildren(
    children: inout [LayoutChild],
    proposal: CGFloat,
    size: CGSize
  )
}

/// A child as seen by a Layout during placement.
public struct LayoutChild {
  /// The measured size of this child.
  public var size: CGSize
  /// The origin assigned by the layout (in parent-local coordinates).
  public var origin: CGPoint

  public init(size: CGSize, origin: CGPoint = .zero) {
    self.size = size
    self.origin = origin
  }
}

// MARK: - AnyLayout

public struct AnyLayout: @unchecked Sendable {
  private let _sizeThatFits: ([LayoutChild], CGFloat) -> CGSize
  private let _placeChildren: (inout [LayoutChild], CGFloat, CGSize) -> Void

  public init(_ layout: some Layout) {
    _sizeThatFits = { children, proposal in
      layout.sizeThatFits(children: children, proposal: proposal)
    }
    _placeChildren = { children, proposal, size in
      layout.placeChildren(children: &children, proposal: proposal, size: size)
    }
  }

  public func sizeThatFits(children: [LayoutChild], proposal: CGFloat) -> CGSize {
    _sizeThatFits(children, proposal)
  }

  public func placeChildren(children: inout [LayoutChild], proposal: CGFloat, size: CGSize) {
    _placeChildren(&children, proposal, size)
  }
}

// MARK: - VStackLayout

public struct VStackLayout: Layout {
  public var spacing: CGFloat

  public init(spacing: CGFloat = 0) {
    self.spacing = spacing
  }

  public func sizeThatFits(children: [LayoutChild], proposal: CGFloat) -> CGSize {
    var height: CGFloat = 0
    var maxWidth: CGFloat = 0
    for (i, child) in children.enumerated() {
      if i > 0 { height += spacing }
      height += child.size.height
      maxWidth = max(maxWidth, child.size.width)
    }
    return CGSize(width: proposal, height: height)
  }

  public func placeChildren(
    children: inout [LayoutChild],
    proposal _: CGFloat,
    size _: CGSize
  ) {
    var y: CGFloat = 0
    for i in children.indices {
      if i > 0 { y += spacing }
      children[i].origin = CGPoint(x: 0, y: y)
      y += children[i].size.height
    }
  }
}
