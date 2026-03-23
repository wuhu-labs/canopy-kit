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
