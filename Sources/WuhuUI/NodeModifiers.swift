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

public final class NodeGesture: @unchecked Sendable {
  public var onTap: (() -> Void)?
  public var onDoubleTap: (() -> Void)?
  public var onLongPress: (() -> Void)?
  public var onHover: ((Bool) -> Void)?
  public var onDragChanged: ((DragGesture.Value) -> Void)?
  public var onDragEnded: ((DragGesture.Value) -> Void)?

  public init(
    onTap: (() -> Void)? = nil,
    onDoubleTap: (() -> Void)? = nil,
    onLongPress: (() -> Void)? = nil,
    onHover: ((Bool) -> Void)? = nil,
    onDragChanged: ((DragGesture.Value) -> Void)? = nil,
    onDragEnded: ((DragGesture.Value) -> Void)? = nil
  ) {
    self.onTap = onTap
    self.onDoubleTap = onDoubleTap
    self.onLongPress = onLongPress
    self.onHover = onHover
    self.onDragChanged = onDragChanged
    self.onDragEnded = onDragEnded
  }
}

public struct GestureKey: NodeValueKey {
  public static let defaultValue: NodeGesture? = nil
}

public extension Node {
  func value<K: NodeValueKey>(_ key: K.Type, _ value: K.Value) -> Self {
    var node = self
    node.values[key] = value
    return node
  }

  func opacity(_ opacity: CGFloat) -> Self {
    value(OpacityKey.self, opacity)
  }

  func clip(_ path: Path?) -> Self {
    value(ClipPathKey.self, path)
  }

  func gesture(_ gesture: NodeGesture?) -> Self {
    value(GestureKey.self, gesture)
  }

  func onTapGesture(_ action: @escaping () -> Void) -> Self {
    gesture(NodeGesture(onTap: action))
  }
}

public extension IdentifiedNode {
  func value<K: NodeValueKey>(_ key: K.Type, _ value: K.Value) -> Self {
    var node = self
    node.node.values[key] = value
    return node
  }

  func opacity(_ opacity: CGFloat) -> Self {
    value(OpacityKey.self, opacity)
  }

  func clip(_ path: Path?) -> Self {
    value(ClipPathKey.self, path)
  }

  func gesture(_ gesture: NodeGesture?) -> Self {
    value(GestureKey.self, gesture)
  }

  func onTapGesture(_ action: @escaping () -> Void) -> Self {
    gesture(NodeGesture(onTap: action))
  }
}
