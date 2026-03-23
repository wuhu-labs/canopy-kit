import CoreGraphics
import SwiftUI

// MARK: - Custom View Representable

/// A leaf primitive that participates in CanopyKit's layout system and
/// materialises as a SwiftUI `View` instead of drawing into a `CGContext`.
///
/// The protocol mirrors ``CustomDrawing`` — `makeCache`, `updateCache`,
/// `sizeThatFits` — but replaces the `draw` method with ``makeView``.
public protocol CustomViewRepresentable {
  associatedtype Cache
  associatedtype Body: View

  func makeCache() -> Cache
  func updateCache(_ cache: inout Cache)
  func sizeThatFits(proposal: ProposedSize, cache: inout Cache) -> CGSize
  @MainActor
  func makeView(cache: Cache) -> Body
}

public extension CustomViewRepresentable {
  func updateCache(_ cache: inout Cache) {
    cache = makeCache()
  }
}

// MARK: - AnyViewRepresentable

public struct AnyViewRepresentable: @unchecked Sendable {
  private let value: any CustomViewRepresentable

  public init(_ representable: some CustomViewRepresentable) {
    value = representable
  }

  func makeCache() -> Any {
    value.makeCache()
  }

  func updateCache(cache: inout Any) {
    _updateCache(representable: value, cache: &cache)
  }

  func sizeThatFits(proposal: ProposedSize, cache: inout Any) -> CGSize {
    _sizeThatFits(representable: value, proposal: proposal, cache: &cache)
  }

  @MainActor
  func makeView(cache: Any) -> AnyView {
    _makeView(representable: value, cache: cache)
  }

  func isEquivalent(to other: AnyViewRepresentable) -> Bool {
    _compareViewRepresentable(lhs: value, rhs: other.value)
  }
}

extension AnyViewRepresentable {
  init(shape: AnyShape) {
    self.init(ShapeViewRepresentable(shape: shape))
  }

  init(drawing: AnyDrawing) {
    self.init(DrawingViewRepresentable(drawing: drawing))
  }
}

private func _compareViewRepresentable<V: CustomViewRepresentable>(
  lhs: V,
  rhs: any CustomViewRepresentable
) -> Bool {
  guard let rhs = rhs as? V else { return false }
  return defaultValueIsEquivalent(lhs, rhs)
}

private func _updateCache<V: CustomViewRepresentable>(
  representable: V,
  cache: inout Any
) {
  guard var typedCache = cache as? V.Cache else {
    cache = representable.makeCache()
    return
  }
  representable.updateCache(&typedCache)
  cache = typedCache
}

private func _sizeThatFits<V: CustomViewRepresentable>(
  representable: V,
  proposal: ProposedSize,
  cache: inout Any
) -> CGSize {
  var typedCache = cache as! V.Cache
  let size = representable.sizeThatFits(proposal: proposal, cache: &typedCache)
  cache = typedCache
  return size
}

@MainActor
private func _makeView<V: CustomViewRepresentable>(
  representable: V,
  cache: Any
) -> AnyView {
  let typedCache = cache as! V.Cache
  let view = representable.makeView(cache: typedCache)
  return AnyView(view)
}

private struct ShapeViewRepresentable: CustomViewRepresentable, Equatable {
  let shape: AnyShape

  struct Cache {}

  func makeCache() -> Cache {
    Cache()
  }

  func sizeThatFits(proposal: ProposedSize, cache _: inout Cache) -> CGSize {
    shape.sizeThatFits(proposal: proposal)
  }

  func makeView(cache _: Cache) -> some View {
    ShapePrimitiveView(shape: shape)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.shape.isEquivalent(to: rhs.shape)
  }
}

private struct ShapePrimitiveView: View {
  let shape: AnyShape

  var body: some View {
    GeometryReader { proxy in
      shape.path(in: CGRect(origin: .zero, size: proxy.size))
    }
  }
}

private struct DrawingViewRepresentable: CustomViewRepresentable, Equatable {
  let drawing: AnyDrawing

  struct Cache {
    var drawingCache: Any
  }

  func makeCache() -> Cache {
    Cache(drawingCache: drawing.makeCache())
  }

  func updateCache(_ cache: inout Cache) {
    drawing.updateCache(cache: &cache.drawingCache)
  }

  func sizeThatFits(proposal: ProposedSize, cache: inout Cache) -> CGSize {
    drawing.sizeThatFits(proposal: proposal, cache: &cache.drawingCache)
  }

  func makeView(cache: Cache) -> some View {
    DrawingPrimitiveView(drawing: drawing, storedCache: cache.drawingCache)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.drawing.isEquivalent(to: rhs.drawing)
  }
}

private struct DrawingPrimitiveView: View {
  let drawing: AnyDrawing
  let storedCache: Any

  var body: some View {
    Canvas { context, size in
      context.withCGContext { cgContext in
        drawing.draw(
          in: cgContext,
          bounds: CGRect(origin: .zero, size: size),
          cache: storedCache
        )
      }
    }
  }
}
