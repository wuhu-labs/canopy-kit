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

// MARK: - Node Values

public protocol NodeValueKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

private protocol AnyNodeValueBox {
  var value: Any { get }
  func isEquivalent(to other: any AnyNodeValueBox) -> Bool
}

private struct NodeValueBox<Value>: AnyNodeValueBox, @unchecked Sendable {
  let typedValue: Value

  var value: Any { typedValue }

  func isEquivalent(to other: any AnyNodeValueBox) -> Bool {
    guard let otherValue = other.value as? Value else { return false }
    return defaultValueIsEquivalent(typedValue, otherValue)
  }
}

public struct NodeValues: @unchecked Sendable {
  private var storage: [ObjectIdentifier: any AnyNodeValueBox] = [:]

  public init() {}

  public subscript<K: NodeValueKey>(key: K.Type) -> K.Value {
    get {
      guard let storedValue = storage[ObjectIdentifier(key)] else {
        return K.defaultValue
      }
      return storedValue.value as! K.Value
    }
    set {
      let identifier = ObjectIdentifier(key)

      if defaultValueIsEquivalent(newValue, K.defaultValue) {
        storage[identifier] = nil
      } else {
        storage[identifier] = NodeValueBox(typedValue: newValue)
      }
    }
  }

  public func isEquivalent(to other: NodeValues) -> Bool {
    guard storage.count == other.storage.count else { return false }

    for (key, value) in storage {
      guard let otherValue = other.storage[key] else { return false }
      guard value.isEquivalent(to: otherValue) else { return false }
    }

    return true
  }
}

public typealias LayoutValueKey = NodeValueKey
public typealias LayoutValues = NodeValues

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

// MARK: - VStackLayout

public struct VStackLayout: Layout, Equatable {
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

    for (index, subview) in subviews.enumerated() {
      if index > 0 { y += spacing }
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

public struct HStackLayout: Layout, Equatable {
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

    for (index, subview) in subviews.enumerated() {
      if index > 0 { x += spacing }
      let remainingWidth = proposedWidth.map { max(0, $0 - x) }
      let childSize = subview.sizeThatFits(
        proposal: ProposedSize(width: remainingWidth, height: proposedHeight)
      )
      placements.append(LayoutPlacement(origin: CGPoint(x: x, y: 0)))
      x += childSize.width
      maxHeight = max(maxHeight, childSize.height)
    }

    let width = proposedWidth.map { min(x, $0) } ?? x
    return (size: CGSize(width: width, height: maxHeight), placements: placements)
  }
}

// MARK: - InsetLayout

public struct InsetLayout: Layout, Equatable {
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
    return (
      size: CGSize(
        width: childSize.width + left + right,
        height: childSize.height + top + bottom
      ),
      placements: [LayoutPlacement(origin: CGPoint(x: left, y: top))]
    )
  }
}

// MARK: - ZStackLayout

public struct ZStackLayout: Layout, Equatable {
  public init() {}

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    guard !subviews.isEmpty else {
      return (size: .zero, placements: [])
    }

    var sizes = subviews.map { $0.sizeThatFits(proposal: proposal) }
    let unionSize = CGSize(
      width: sizes.map(\.width).max() ?? 0,
      height: sizes.map(\.height).max() ?? 0
    )

    let unionProposal = ProposedSize(width: unionSize.width, height: unionSize.height)
    sizes = subviews.map { $0.sizeThatFits(proposal: unionProposal) }

    let finalSize = CGSize(
      width: sizes.map(\.width).max() ?? 0,
      height: sizes.map(\.height).max() ?? 0
    )
    return (
      size: finalSize,
      placements: subviews.map { _ in LayoutPlacement(origin: .zero) }
    )
  }
}

// MARK: - FrameLayout

public struct FrameLayout: Layout, Equatable {
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
    guard let subview = subviews.first else {
      return (
        size: CGSize(width: width ?? 0, height: height ?? 0),
        placements: []
      )
    }

    let childProposal = ProposedSize(
      width: width ?? proposal.width,
      height: height ?? proposal.height
    )
    let childSize = subview.sizeThatFits(proposal: childProposal)
    let containerSize = CGSize(
      width: width ?? childSize.width,
      height: height ?? childSize.height
    )
    return (
      size: containerSize,
      placements: [
        LayoutPlacement(
          origin: CGPoint(
            x: max(0, (containerSize.width - childSize.width) / 2),
            y: max(0, (containerSize.height - childSize.height) / 2)
          )
        )
      ]
    )
  }
}

func defaultValueIsEquivalent<Value>(_ lhs: Value, _ rhs: Value) -> Bool {
  if Value.self is AnyObject.Type {
    return ObjectIdentifier(lhs as AnyObject) == ObjectIdentifier(rhs as AnyObject)
  }
  if let lhs = lhs as? any Equatable {
    return defaultEquatableValueIsEquivalent(lhs, rhs)
  }
  return defaultBytewiseValueIsEquivalent(lhs, rhs)
}

private func defaultEquatableValueIsEquivalent<Value: Equatable>(_ lhs: Value, _ rhs: Any) -> Bool {
  guard let rhs = rhs as? Value else { return false }
  return lhs == rhs
}

private func defaultBytewiseValueIsEquivalent<Value>(_ lhs: Value, _ rhs: Value) -> Bool {
  withUnsafeBytes(of: lhs) { lhsBytes in
    withUnsafeBytes(of: rhs) { rhsBytes in
      lhsBytes.elementsEqual(rhsBytes)
    }
  }
}
