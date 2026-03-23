import CoreGraphics
import SwiftUI

// MARK: - Primitive

public struct Primitive: @unchecked Sendable {
  let representable: AnyViewRepresentable

  init(_ representable: AnyViewRepresentable) {
    self.representable = representable
  }

  public init(_ representable: some CustomViewRepresentable) {
    self.init(AnyViewRepresentable(representable))
  }

  public init(_ shape: some Shape) {
    self.init(AnyViewRepresentable(shape))
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
