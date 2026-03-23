import CoreGraphics
import SwiftUI

// MARK: - Primitive

public enum Primitive: @unchecked Sendable {
  case shape(AnyShape)
  case customDrawing(AnyDrawing)
  case customView(AnyViewRepresentable)

  func isEquivalent(to other: Primitive) -> Bool {
    switch (self, other) {
    case let (.shape(lhs), .shape(rhs)):
      lhs.isEquivalent(to: rhs)
    case let (.customDrawing(lhs), .customDrawing(rhs)):
      lhs.isEquivalent(to: rhs)
    case let (.customView(lhs), .customView(rhs)):
      lhs.isEquivalent(to: rhs)
    default:
      false
    }
  }

  var viewRepresentable: AnyViewRepresentable {
    switch self {
    case let .shape(shape):
      AnyViewRepresentable(shape: shape)
    case let .customDrawing(drawing):
      AnyViewRepresentable(drawing: drawing)
    case let .customView(representable):
      representable
    }
  }
}

// MARK: - Primitive Styling

public struct PrimitiveFillColorKey: NodeValueKey {
  public static var defaultValue: CGColor? {
    CGColor(gray: 0, alpha: 1)
  }
}

public struct PrimitiveStrokeStyle: @unchecked Sendable {
  public var color: CGColor
  public var lineWidth: CGFloat

  public init(color: CGColor, lineWidth: CGFloat = 1) {
    self.color = color
    self.lineWidth = lineWidth
  }
}

public struct PrimitiveStrokeStyleKey: NodeValueKey {
  public static let defaultValue: PrimitiveStrokeStyle? = nil
}
