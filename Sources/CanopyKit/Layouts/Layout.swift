import CoreGraphics

// MARK: - Layout

/// A proxy for a single child that the layout can measure with any proposal.
public struct LayoutSubview {
  private let _sizeThatFits: (ProposedSize) -> CGSize
  private let _nodeValues: NodeValues

  public init(
    _ sizeThatFits: @escaping (ProposedSize) -> CGSize,
    nodeValues: NodeValues = NodeValues()
  ) {
    _sizeThatFits = sizeThatFits
    _nodeValues = nodeValues
  }

  /// Measure this child with the given proposal.
  public func sizeThatFits(proposal: ProposedSize) -> CGSize {
    _sizeThatFits(proposal)
  }

  /// Read a node value from this child.
  public subscript<K: NodeValueKey>(key: K.Type) -> K.Value {
    _nodeValues[key]
  }
}

/// The result of layout: a placement origin and proposed size for each child.
public struct LayoutPlacement {
  public var origin: CGPoint
  public var proposal: ProposedSize

  public init(origin: CGPoint = .zero, proposal: ProposedSize = ProposedSize(width: nil, height: nil)) {
    self.origin = origin
    self.proposal = proposal
  }
}

/// Pure geometry: given measurable child proxies and a size proposal,
/// measure children (with whatever proposals you want), compute the
/// container's size, and place children.
public protocol Layout: Sendable {
  /// Measure children and return (container size, per-child placements).
  func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement])
}

// MARK: - AnyLayout

public struct AnyLayout: @unchecked Sendable {
  private let box: any AnyLayoutBox

  public init<L: Layout>(_ layout: L) {
    self.init(layout, isEquivalent: defaultValueIsEquivalent)
  }

  public init<L: Layout>(_ layout: L, isEquivalent: @escaping @Sendable (L, L) -> Bool) {
    box = LayoutBox(layoutValue: layout, isEquivalentClosure: isEquivalent)
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    box.layout(subviews: subviews, proposal: proposal)
  }

  public func isEquivalent(to other: AnyLayout) -> Bool {
    box.isEquivalent(to: other.box)
  }
}

private protocol AnyLayoutBox {
  func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement])
  func isEquivalent(to other: any AnyLayoutBox) -> Bool
}

private struct LayoutBox<L: Layout>: AnyLayoutBox, @unchecked Sendable {
  let layoutValue: L
  let isEquivalentClosure: @Sendable (L, L) -> Bool

  func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    layoutValue.layout(subviews: subviews, proposal: proposal)
  }

  func isEquivalent(to other: any AnyLayoutBox) -> Bool {
    guard let other = other as? Self else { return false }
    return isEquivalentClosure(layoutValue, other.layoutValue)
  }
}
