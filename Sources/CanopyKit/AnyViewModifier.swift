import SwiftUI

/// A type-erased `ViewModifier` that supports concatenation.
///
/// `AnyViewModifier` boxes any concrete `ViewModifier` and can apply it to an
/// arbitrary `View`, returning `AnyView`. Multiple modifiers are concatenated
/// via ``concat(_:)`` which produces a new `AnyViewModifier` that applies both
/// in sequence (left-to-right).
///
/// ```swift
/// let m1 = AnyViewModifier(OpacityModifier(value: 0.5))
/// let m2 = AnyViewModifier(BackgroundModifier(color: .red))
/// let combined = m1.concat(m2) // applies opacity, then background
/// ```
///
/// The caller is responsible for only attaching layout-independent modifiers.
/// CanopyKit's layout engine does not see these — they are applied purely at
/// the SwiftUI materialization layer.
public struct AnyViewModifier: @unchecked Sendable {
  private let _apply: @MainActor (AnyView) -> AnyView

  /// Wraps a concrete `ViewModifier`.
  public init<M: ViewModifier>(_ modifier: M) {
    // Copy modifier into a nonisolated(unsafe) capture to cross the
    // isolation boundary. This is safe because AnyViewModifier is only
    // ever applied on the main actor (SwiftUI materialization).
    nonisolated(unsafe) let m = modifier
    _apply = { view in AnyView(view.modifier(m)) }
  }

  /// The identity modifier — applies no transformation.
  public static let identity = AnyViewModifier(apply: { $0 })

  /// Returns a new modifier that applies `self` first, then `other`.
  public func concat(_ other: AnyViewModifier) -> AnyViewModifier {
    let lhs = self._apply
    let rhs = other._apply
    return AnyViewModifier(apply: { view in rhs(lhs(view)) })
  }

  /// Applies this modifier to the given view.
  @MainActor
  public func apply<V: View>(to view: V) -> AnyView {
    _apply(AnyView(view))
  }

  // Internal initializer for identity / concat construction.
  private init(apply: @escaping @MainActor (AnyView) -> AnyView) {
    _apply = apply
  }
}

// MARK: - Node Value Key

public struct ViewModifierKey: NodeValueKey {
  public static let defaultValue: AnyViewModifier? = nil
}
