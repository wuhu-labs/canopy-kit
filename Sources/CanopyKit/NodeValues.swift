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

  func isEquivalent(to other: NodeValues) -> Bool {
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

// MARK: - Equivalence

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
