import CoreGraphics
import SwiftUI

// MARK: - Primitive

public struct Primitive: @unchecked Sendable {
  let representable: AnyViewRepresentable

  public init(_ representable: AnyViewRepresentable) {
    self.representable = representable
  }

  public init(_ representable: some CustomViewRepresentable) {
    self.init(AnyViewRepresentable(representable))
  }

  public static func view(_ representable: AnyViewRepresentable) -> Self {
    Self(representable)
  }

  public static func view(_ representable: some CustomViewRepresentable) -> Self {
    Self(representable)
  }

  public static func drawing(_ drawing: some CustomDrawing) -> Self {
    Self(drawing)
  }

  public static func shape(_ shape: AnyShape) -> Self {
    Self(AnyViewRepresentable(shape: shape))
  }

  public static func shape(_ shape: some ShapePrimitive) -> Self {
    Self.shape(AnyShape(shape))
  }

  public static func shape(_ shape: some Shape) -> Self {
    Self.shape(AnyShape(shape))
  }

  @available(*, deprecated, renamed: "view")
  public static func customView(_ representable: AnyViewRepresentable) -> Self {
    Self.view(representable)
  }

  func isEquivalent(to other: Self) -> Bool {
    representable.isEquivalent(to: other.representable)
  }

  var viewRepresentable: AnyViewRepresentable {
    representable
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
