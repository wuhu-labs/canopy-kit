import CoreGraphics
import SwiftUI

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
  func viewModifier(_ modifier: some ViewModifier) -> Self {
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

  // MARK: Unary Layout Modifiers

  /// Wraps this node in a padding (inset) layout. If this node is already a
  /// single-child layout, the layouts are composed into one to avoid nesting.
  func padding(
    left: CGFloat = 0,
    top: CGFloat = 0,
    right: CGFloat = 0,
    bottom: CGFloat = 0
  ) -> Self {
    wrapUnary(AnyLayout(InsetLayout(left: left, top: top, right: right, bottom: bottom)))
  }

  /// Wraps this node in a padding (inset) layout with uniform insets.
  func padding(_ inset: CGFloat) -> Self {
    padding(left: inset, top: inset, right: inset, bottom: inset)
  }

  /// Wraps this node in a frame layout. If this node is already a
  /// single-child layout, the layouts are composed into one to avoid nesting.
  func frame(width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
    wrapUnary(AnyLayout(FrameLayout(width: width, height: height)))
  }

  private func wrapUnary(_ outer: AnyLayout) -> Self {
    if case let .layout(inner, children) = content, children.count == 1 {
      return .layout(
        AnyLayout(ComposedUnaryLayout(outer: outer, inner: inner)),
        children: children,
        values: values
      )
    }
    return .layout(outer, children: [IdentifiedNode(id: AnyHashable("__u"), node: self)])
  }
}

public extension IdentifiedNode {
  func value<K: NodeValueKey>(_ key: K.Type, _ value: K.Value) -> Self {
    var node = self
    node.node.values[key] = value
    return node
  }

  func viewModifier(_ modifier: some ViewModifier) -> Self {
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

  // MARK: Unary Layout Modifiers

  func padding(
    left: CGFloat = 0,
    top: CGFloat = 0,
    right: CGFloat = 0,
    bottom: CGFloat = 0
  ) -> Self {
    var result = self
    result.node = result.node.padding(left: left, top: top, right: right, bottom: bottom)
    return result
  }

  func padding(_ inset: CGFloat) -> Self {
    padding(left: inset, top: inset, right: inset, bottom: inset)
  }

  func frame(width: CGFloat? = nil, height: CGFloat? = nil) -> Self {
    var result = self
    result.node = result.node.frame(width: width, height: height)
    return result
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
