import CoreGraphics
import SwiftUI

// MARK: - Custom Drawing

public protocol CustomDrawing {
  associatedtype Cache

  func makeCache() -> Cache
  func updateCache(_ cache: inout Cache)
  func sizeThatFits(proposal: ProposedSize, cache: inout Cache) -> CGSize
  func draw(in context: CGContext, bounds: CGRect, cache: inout Cache)
}

public extension CustomDrawing {
  func updateCache(_ cache: inout Cache) {
    cache = makeCache()
  }
}

// MARK: - Shapes

public protocol ShapePrimitive {
  func path(in rect: CGRect) -> Path
}

public extension ShapePrimitive {
  func sizeThatFits(proposal: ProposedSize) -> CGSize {
    let size = proposal.replacingUnspecifiedDimensions()
    let rect = CGRect(origin: .zero, size: size)
    let boundingRect = path(in: rect).boundingRect

    return CGSize(
      width: max(boundingRect.width, proposal.width ?? size.width),
      height: max(boundingRect.height, proposal.height ?? size.height)
    )
  }
}

public struct AnyShape: @unchecked Sendable {
  private let box: any AnyShapeBox

  public init<S: ShapePrimitive>(_ shape: S) {
    self.init(shape, isEquivalent: defaultValueIsEquivalent)
  }

  public init<S: ShapePrimitive>(
    _ shape: S,
    isEquivalent: @escaping @Sendable (S, S) -> Bool
  ) {
    box = ShapeBox(shape: shape, isEquivalentClosure: isEquivalent)
  }

  public func path(in rect: CGRect) -> Path {
    box.path(in: rect)
  }

  public func sizeThatFits(proposal: ProposedSize) -> CGSize {
    box.sizeThatFits(proposal: proposal)
  }

  public func isEquivalent(to other: AnyShape) -> Bool {
    box.isEquivalent(to: other.box)
  }
}

private protocol AnyShapeBox {
  func path(in rect: CGRect) -> Path
  func sizeThatFits(proposal: ProposedSize) -> CGSize
  func isEquivalent(to other: any AnyShapeBox) -> Bool
}

private struct ShapeBox<S: ShapePrimitive>: AnyShapeBox, @unchecked Sendable {
  let shape: S
  let isEquivalentClosure: @Sendable (S, S) -> Bool

  func path(in rect: CGRect) -> Path {
    shape.path(in: rect)
  }

  func sizeThatFits(proposal: ProposedSize) -> CGSize {
    shape.sizeThatFits(proposal: proposal)
  }

  func isEquivalent(to other: any AnyShapeBox) -> Bool {
    guard let other = other as? Self else { return false }
    return isEquivalentClosure(shape, other.shape)
  }
}

// MARK: - AnyDrawing

public struct AnyDrawing: @unchecked Sendable {
  private let box: any AnyDrawingBox

  public init<D: CustomDrawing>(_ drawing: D) {
    self.init(drawing, isEquivalent: defaultValueIsEquivalent)
  }

  public init<D: CustomDrawing>(
    _ drawing: D,
    isEquivalent: @escaping @Sendable (D, D) -> Bool
  ) {
    box = DrawingBox(drawing: drawing, isEquivalentClosure: isEquivalent)
  }

  func makeCache() -> Any {
    box.makeCache()
  }

  func updateCache(cache: inout Any) {
    box.updateCache(cache: &cache)
  }

  func sizeThatFits(proposal: ProposedSize, cache: inout Any) -> CGSize {
    box.sizeThatFits(proposal: proposal, cache: &cache)
  }

  func draw(in context: CGContext, bounds: CGRect, cache: inout Any) {
    box.draw(in: context, bounds: bounds, cache: &cache)
  }

  public func isEquivalent(to other: AnyDrawing) -> Bool {
    box.isEquivalent(to: other.box)
  }
}

private protocol AnyDrawingBox {
  func makeCache() -> Any
  func updateCache(cache: inout Any)
  func sizeThatFits(proposal: ProposedSize, cache: inout Any) -> CGSize
  func draw(in context: CGContext, bounds: CGRect, cache: inout Any)
  func isEquivalent(to other: any AnyDrawingBox) -> Bool
}

private struct DrawingBox<D: CustomDrawing>: AnyDrawingBox, @unchecked Sendable {
  let drawing: D
  let isEquivalentClosure: @Sendable (D, D) -> Bool

  func makeCache() -> Any {
    drawing.makeCache()
  }

  func updateCache(cache: inout Any) {
    guard var typedCache = cache as? D.Cache else {
      cache = drawing.makeCache()
      return
    }
    drawing.updateCache(&typedCache)
    cache = typedCache
  }

  func sizeThatFits(proposal: ProposedSize, cache: inout Any) -> CGSize {
    var typedCache = cache as! D.Cache
    let size = drawing.sizeThatFits(proposal: proposal, cache: &typedCache)
    cache = typedCache
    return size
  }

  func draw(in context: CGContext, bounds: CGRect, cache: inout Any) {
    var typedCache = cache as! D.Cache
    drawing.draw(in: context, bounds: bounds, cache: &typedCache)
    cache = typedCache
  }

  func isEquivalent(to other: any AnyDrawingBox) -> Bool {
    guard let other = other as? Self else { return false }
    return isEquivalentClosure(drawing, other.drawing)
  }
}

// MARK: - Primitive

public enum Primitive: @unchecked Sendable {
  case shape(AnyShape)
  case customDrawing(AnyDrawing)

  public func isEquivalent(to other: Primitive) -> Bool {
    switch (self, other) {
    case let (.shape(lhs), .shape(rhs)):
      lhs.isEquivalent(to: rhs)
    case let (.customDrawing(lhs), .customDrawing(rhs)):
      lhs.isEquivalent(to: rhs)
    default:
      false
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

public struct OpacityKey: NodeValueKey {
  public static let defaultValue: CGFloat = 1
}

public struct ClipPathKey: NodeValueKey {
  public static let defaultValue: Path? = nil
}
