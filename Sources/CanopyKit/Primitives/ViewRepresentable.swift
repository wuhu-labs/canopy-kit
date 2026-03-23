import CoreGraphics
import SwiftUI

// MARK: - Custom View Representable

/// A leaf primitive that participates in CanopyKit's layout system and
/// materialises as a SwiftUI `View` instead of drawing into a `CGContext`.
///
/// The protocol mirrors ``CustomDrawing`` — `makeCache`, `updateCache`,
/// `sizeThatFits` — but replaces the `draw` method with ``makeView``.
public protocol CustomViewRepresentable {
  associatedtype Cache = Void
  associatedtype Commitment
  associatedtype Body: View

  func makeCache() -> Cache
  func updateCache(_ cache: inout Cache)
  func sizeThatFits(proposal: ProposedSize, cache: inout Cache) -> CGSize
  func makeCommitment(in bounds: CGRect, cache: Cache) -> Commitment
  @MainActor
  func makeView(commitment: Commitment) -> Body
}

public extension CustomViewRepresentable {
  func updateCache(_ cache: inout Cache) {
    cache = makeCache()
  }
}

public extension CustomViewRepresentable where Cache == Void {
  func makeCache() -> Void {}
}

// MARK: - AnyViewRepresentable

struct AnyViewRepresentable: @unchecked Sendable {
  private let value: any CustomViewRepresentable

  init(_ representable: some CustomViewRepresentable) {
    value = representable
  }

  init(_ shape: some Shape) {
    self.init(ShapeViewRepresentable(shape: shape))
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

  func makeCommitment(in bounds: CGRect, cache: Any) -> Any {
    _makeCommitment(representable: value, in: bounds, cache: cache)
  }

  @MainActor
  func makeView(commitment: Any) -> AnyView {
    _makeView(representable: value, commitment: commitment)
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

@MainActor
private func _makeView<V: CustomViewRepresentable>(
  representable: V,
  commitment: Any
) -> AnyView {
  let typedCommitment = commitment as! V.Commitment
  let view = representable.makeView(commitment: typedCommitment)
  return AnyView(view)
}

private func _makeCommitment<V: CustomViewRepresentable>(
  representable: V,
  in bounds: CGRect,
  cache: Any
) -> Any {
  let typedCache = cache as! V.Cache
  return representable.makeCommitment(in: bounds, cache: typedCache)
}
