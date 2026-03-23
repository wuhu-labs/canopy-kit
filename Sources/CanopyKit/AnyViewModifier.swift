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
  private var modifier: any ViewModifier

  /// Wraps a concrete `ViewModifier`.
  public init<M: ViewModifier>(_ modifier: M) {
    self.modifier = modifier
  }

  private init(erased: any ViewModifier) {
    modifier = erased
  }

  /// Returns a new modifier that applies `self` first, then `other`.
  public func concat(_ other: AnyViewModifier) -> AnyViewModifier {
    AnyViewModifier(concatModifier(m1: modifier, m2: other.modifier))
  }

  public func apply(to view: some View) -> AnyView {
    applyModifier(body: view, modifier: modifier)
  }
}

private func concatModifier(m1: some ViewModifier, m2: some ViewModifier) -> some ViewModifier {
  return m1.concat(m2)
}

private func applyModifier(body: some View, modifier: some ViewModifier) -> AnyView {
  AnyView(body.modifier(modifier))
}

// MARK: - Node Value Key

public struct ViewModifierKey: NodeValueKey {
  public static let defaultValue: AnyViewModifier? = nil
}
