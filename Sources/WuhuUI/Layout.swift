import CoreGraphics

// MARK: - Layout

/// A proxy for a single child that the layout can measure with any proposal.
public struct LayoutSubview {
  private let _sizeThatFits: (CGFloat) -> CGSize

  public init(_ sizeThatFits: @escaping (CGFloat) -> CGSize) {
    _sizeThatFits = sizeThatFits
  }

  /// Measure this child with the given width proposal.
  public func sizeThatFits(proposal: CGFloat) -> CGSize {
    _sizeThatFits(proposal)
  }
}

/// The result of layout: a size for each child and its placement origin.
public struct LayoutPlacement {
  public var size: CGSize
  public var origin: CGPoint

  public init(size: CGSize, origin: CGPoint = .zero) {
    self.size = size
    self.origin = origin
  }
}

/// Pure geometry: given measurable child proxies and a width proposal,
/// measure children (with whatever proposals you want), compute the
/// container's size, and place children.
public protocol Layout {
  /// Measure children and return (container size, per-child placements).
  func layout(
    subviews: [LayoutSubview],
    proposal: CGFloat
  ) -> (size: CGSize, placements: [LayoutPlacement])
}

// MARK: - AnyLayout

public struct AnyLayout: @unchecked Sendable {
  private let _layout: ([LayoutSubview], CGFloat) -> (size: CGSize, placements: [LayoutPlacement])

  public init(_ layout: some Layout) {
    _layout = { subviews, proposal in
      layout.layout(subviews: subviews, proposal: proposal)
    }
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: CGFloat
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    _layout(subviews, proposal)
  }
}

// MARK: - VStackLayout

public struct VStackLayout: Layout {
  public var spacing: CGFloat

  public init(spacing: CGFloat = 0) {
    self.spacing = spacing
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: CGFloat
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    var placements: [LayoutPlacement] = []
    var y: CGFloat = 0

    for (i, subview) in subviews.enumerated() {
      if i > 0 { y += spacing }
      let childSize = subview.sizeThatFits(proposal: proposal)
      placements.append(LayoutPlacement(size: childSize, origin: CGPoint(x: 0, y: y)))
      y += childSize.height
    }

    return (size: CGSize(width: proposal, height: y), placements: placements)
  }
}

// MARK: - HStackLayout

public struct HStackLayout: Layout {
  public var spacing: CGFloat

  public init(spacing: CGFloat = 0) {
    self.spacing = spacing
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: CGFloat
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    var placements: [LayoutPlacement] = []
    var x: CGFloat = 0
    var maxHeight: CGFloat = 0

    for (i, subview) in subviews.enumerated() {
      if i > 0 { x += spacing }
      let remaining = max(0, proposal - x)
      let childSize = subview.sizeThatFits(proposal: remaining)
      placements.append(LayoutPlacement(size: childSize, origin: CGPoint(x: x, y: 0)))
      x += childSize.width
      maxHeight = max(maxHeight, childSize.height)
    }

    return (size: CGSize(width: min(x, proposal), height: maxHeight), placements: placements)
  }
}

// MARK: - InsetLayout

/// Wraps a single child with edge insets. Proposes reduced width to the child.
public struct InsetLayout: Layout {
  public var left: CGFloat
  public var top: CGFloat
  public var right: CGFloat
  public var bottom: CGFloat

  public init(left: CGFloat = 0, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0) {
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: CGFloat
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    guard let subview = subviews.first else {
      return (size: CGSize(width: proposal, height: top + bottom), placements: [])
    }

    let innerWidth = max(0, proposal - left - right)
    let childSize = subview.sizeThatFits(proposal: innerWidth)
    let placement = LayoutPlacement(size: childSize, origin: CGPoint(x: left, y: top))
    let containerSize = CGSize(
      width: childSize.width + left + right,
      height: childSize.height + top + bottom
    )
    return (size: containerSize, placements: [placement])
  }
}
