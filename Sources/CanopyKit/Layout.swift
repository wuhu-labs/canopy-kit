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
