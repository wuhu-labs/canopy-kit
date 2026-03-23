import CoreGraphics
import SwiftUI

public enum StretchBehavior: Sendable {
  case intrinsic
  case fill
}

public struct StretchBehaviorKey: NodeValueKey {
  public static let defaultValue: StretchBehavior = .intrinsic
}

public struct FlexGrowKey: NodeValueKey {
  public static let defaultValue: CGFloat = 0
}

// MARK: - Node Modifier API

public extension Node {
  func value<K: NodeValueKey>(_ key: K.Type, _ value: K.Value) -> Self {
    var node = self
    node.values[key] = value
    return node
  }

  /// Attach an arbitrary SwiftUI `ViewModifier` to this node.
  ///
  /// The modifier is applied at SwiftUI materialization time and does **not**
  /// participate in CanopyKit's layout engine. The caller is responsible for
  /// only attaching layout-independent modifiers.
  ///
  /// Multiple calls concatenate: the modifiers are applied left-to-right in
  /// the order they were attached.
  func viewModifier<M: ViewModifier>(_ modifier: M) -> Self {
    var node = self
    let wrapped = AnyViewModifier(modifier)
    if let existing = node.values[ViewModifierKey.self] {
      node.values[ViewModifierKey.self] = existing.concat(wrapped)
    } else {
      node.values[ViewModifierKey.self] = wrapped
    }
    return node
  }

  func opacity(_ opacity: CGFloat) -> Self {
    viewModifier(_OpacityModifier(opacity: opacity))
  }

  func clip(_ path: Path?) -> Self {
    viewModifier(_ClipModifier(path: path))
  }
}

public extension IdentifiedNode {
  func value<K: NodeValueKey>(_ key: K.Type, _ value: K.Value) -> Self {
    var node = self
    node.node.values[key] = value
    return node
  }

  func viewModifier<M: ViewModifier>(_ modifier: M) -> Self {
    var node = self
    let wrapped = AnyViewModifier(modifier)
    if let existing = node.node.values[ViewModifierKey.self] {
      node.node.values[ViewModifierKey.self] = existing.concat(wrapped)
    } else {
      node.node.values[ViewModifierKey.self] = wrapped
    }
    return node
  }

  func opacity(_ opacity: CGFloat) -> Self {
    viewModifier(_OpacityModifier(opacity: opacity))
  }

  func clip(_ path: Path?) -> Self {
    viewModifier(_ClipModifier(path: path))
  }
}

// MARK: - Built-in View Modifiers

struct _OpacityModifier: ViewModifier {
  let opacity: CGFloat

  func body(content: Content) -> some View {
    content.opacity(opacity)
  }
}

struct _ClipModifier: ViewModifier {
  let path: Path?

  func body(content: Content) -> some View {
    if let path {
      AnyView(
        content.mask(
          Canvas { context, _ in
            context.fill(path, with: .color(.white))
          }
        )
      )
    } else {
      AnyView(content)
    }
  }
}
