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
  func makeView(cache: inout Cache) -> Body
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

  func makeView(cache: inout Any) -> AnyView {
    _makeView(representable: value, cache: &cache)
  }

  func isEquivalent(to other: AnyViewRepresentable) -> Bool {
    _compareViewRepresentable(lhs: value, rhs: other.value)
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

private func _makeView<V: CustomViewRepresentable>(
  representable: V,
  cache: inout Any
) -> AnyView {
  var typedCache = cache as! V.Cache
  let view = representable.makeView(cache: &typedCache)
  cache = typedCache
  return AnyView(view)
}
