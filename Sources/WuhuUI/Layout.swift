import CoreGraphics

// MARK: - ProposedSize

/// A two-dimensional size proposal. `nil` on either axis means
/// "no constraint — report your ideal size on that axis."
public struct ProposedSize: Hashable, Sendable {
  public var width: CGFloat?
  public var height: CGFloat?

  public init(width: CGFloat? = nil, height: CGFloat? = nil) {
    self.width = width
    self.height = height
  }

  /// Both dimensions unspecified — asks for the ideal size.
  public static let unspecified = ProposedSize()

  /// Both dimensions zero — asks for the minimum size.
  public static let zero = ProposedSize(width: 0, height: 0)

  /// Replace `nil` dimensions with the given defaults (10 × 10 by default,
  /// matching SwiftUI's convention for flexible views).
  public func replacingUnspecifiedDimensions(
    by size: CGSize = CGSize(width: 10, height: 10)
  ) -> CGSize {
    CGSize(
      width: width ?? size.width,
      height: height ?? size.height
    )
  }
}

// MARK: - Layout

/// A proxy for a single child that the layout can measure with any proposal.
public struct LayoutSubview {
  private let _sizeThatFits: (ProposedSize) -> CGSize
  private let _layoutValues: LayoutValues

  public init(
    _ sizeThatFits: @escaping (ProposedSize) -> CGSize,
    layoutValues: LayoutValues = LayoutValues()
  ) {
    _sizeThatFits = sizeThatFits
    _layoutValues = layoutValues
  }

  /// Measure this child with the given proposal.
  public func sizeThatFits(proposal: ProposedSize) -> CGSize {
    _sizeThatFits(proposal)
  }

  /// Read a layout value from this child.
  public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
    _layoutValues[key]
  }
}

// MARK: - Layout Values

/// Per-child key-value metadata that layouts can read.
public protocol LayoutValueKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

/// Storage for layout values attached to a child.
public struct LayoutValues: @unchecked Sendable {
  private var storage: [ObjectIdentifier: Any] = [:]

  public init() {}

  public subscript<K: LayoutValueKey>(key: K.Type) -> K.Value {
    get { storage[ObjectIdentifier(key)] as? K.Value ?? K.defaultValue }
    set { storage[ObjectIdentifier(key)] = newValue }
  }
}

/// The result of layout: a placement origin for each child.
public struct LayoutPlacement {
  public var origin: CGPoint

  public init(origin: CGPoint = .zero) {
    self.origin = origin
  }
}

/// Pure geometry: given measurable child proxies and a size proposal,
/// measure children (with whatever proposals you want), compute the
/// container's size, and place children.
public protocol Layout {
  /// Measure children and return (container size, per-child placements).
  func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement])
}

// MARK: - AnyLayout

public struct AnyLayout: @unchecked Sendable {
  private let _layout:
    ([LayoutSubview], ProposedSize) -> (size: CGSize, placements: [LayoutPlacement])

  public init(_ layout: some Layout) {
    _layout = { subviews, proposal in
      layout.layout(subviews: subviews, proposal: proposal)
    }
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
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
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    let proposedWidth = proposal.width
    var placements: [LayoutPlacement] = []
    var y: CGFloat = 0
    var maxWidth: CGFloat = 0

    for (i, subview) in subviews.enumerated() {
      if i > 0 { y += spacing }
      let childSize = subview.sizeThatFits(
        proposal: ProposedSize(width: proposedWidth, height: nil)
      )
      placements.append(LayoutPlacement(origin: CGPoint(x: 0, y: y)))
      y += childSize.height
      maxWidth = max(maxWidth, childSize.width)
    }

    let width = proposedWidth ?? maxWidth
    return (size: CGSize(width: width, height: y), placements: placements)
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
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    let proposedWidth = proposal.width
    let proposedHeight = proposal.height
    var placements: [LayoutPlacement] = []
    var x: CGFloat = 0
    var maxHeight: CGFloat = 0

    for (i, subview) in subviews.enumerated() {
      if i > 0 { x += spacing }
      let remainingWidth = proposedWidth.map { max(0, $0 - x) }
      let childSize = subview.sizeThatFits(
        proposal: ProposedSize(width: remainingWidth, height: proposedHeight)
      )
      placements.append(LayoutPlacement(origin: CGPoint(x: x, y: 0)))
      x += childSize.width
      maxHeight = max(maxHeight, childSize.height)
    }

    let width: CGFloat
    if let proposedWidth {
      width = min(x, proposedWidth)
    } else {
      width = x
    }
    return (size: CGSize(width: width, height: maxHeight), placements: placements)
  }
}

// MARK: - InsetLayout

/// Wraps a single child with edge insets. Proposes reduced size to the child.
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
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    guard let subview = subviews.first else {
      let width = proposal.width ?? (left + right)
      return (size: CGSize(width: width, height: top + bottom), placements: [])
    }

    let innerWidth = proposal.width.map { max(0, $0 - left - right) }
    let innerHeight = proposal.height.map { max(0, $0 - top - bottom) }
    let childSize = subview.sizeThatFits(
      proposal: ProposedSize(width: innerWidth, height: innerHeight)
    )
    let placement = LayoutPlacement(origin: CGPoint(x: left, y: top))
    let containerSize = CGSize(
      width: childSize.width + left + right,
      height: childSize.height + top + bottom
    )
    return (size: containerSize, placements: [placement])
  }
}

// MARK: - ZStackLayout

/// Overlays all children at the same origin. Two-pass: measures children first,
/// then re-proposes the union size so flexible children can stretch to fill.
public struct ZStackLayout: Layout {
  public init() {}

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    guard !subviews.isEmpty else {
      return (size: .zero, placements: [])
    }

    // Pass 1: measure each child with the incoming proposal.
    var sizes = subviews.map { $0.sizeThatFits(proposal: proposal) }
    let unionWidth = sizes.map(\.width).max() ?? 0
    let unionHeight = sizes.map(\.height).max() ?? 0
    let unionSize = CGSize(width: unionWidth, height: unionHeight)

    // Pass 2: re-propose the union size so flexible children can stretch.
    let unionProposal = ProposedSize(width: unionSize.width, height: unionSize.height)
    sizes = subviews.map { $0.sizeThatFits(proposal: unionProposal) }

    let finalWidth = sizes.map(\.width).max() ?? 0
    let finalHeight = sizes.map(\.height).max() ?? 0

    let placements = subviews.map { _ in LayoutPlacement(origin: .zero) }
    return (size: CGSize(width: finalWidth, height: finalHeight), placements: placements)
  }
}

// MARK: - FrameLayout

/// Overrides the proposal to its single child with explicit width/height values.
/// `nil` means pass through the parent's proposal on that axis.
public struct FrameLayout: Layout {
  public var width: CGFloat?
  public var height: CGFloat?

  public init(width: CGFloat? = nil, height: CGFloat? = nil) {
    self.width = width
    self.height = height
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    let childProposal = ProposedSize(
      width: width ?? proposal.width,
      height: height ?? proposal.height
    )

    guard let subview = subviews.first else {
      let size = childProposal.replacingUnspecifiedDimensions(by: .zero)
      return (size: size, placements: [])
    }

    let childSize = subview.sizeThatFits(proposal: childProposal)

    // The container reports the explicitly set dimensions, or the child's size.
    let containerSize = CGSize(
      width: width ?? childSize.width,
      height: height ?? childSize.height
    )

    // Center the child within the container if the container is larger.
    let originX = (containerSize.width - childSize.width) / 2
    let originY = (containerSize.height - childSize.height) / 2
    let placement = LayoutPlacement(origin: CGPoint(x: originX, y: originY))

    return (size: containerSize, placements: [placement])
  }
}
