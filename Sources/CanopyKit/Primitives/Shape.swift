import CoreGraphics
import SwiftUI

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

// MARK: - AnyShape

public struct AnyShape: @unchecked Sendable {
  private let value: any ShapePrimitive

  public init<S: ShapePrimitive>(_ shape: S) {
    value = shape
  }

  /// Creates an `AnyShape` from any SwiftUI `Shape`.
  public init(_ shape: some Shape) {
    self.init(SwiftUIShapeAdapter(source: shape))
  }

  public func path(in rect: CGRect) -> Path {
    value.path(in: rect)
  }

  public func sizeThatFits(proposal: ProposedSize) -> CGSize {
    value.sizeThatFits(proposal: proposal)
  }

  func isEquivalent(to other: AnyShape) -> Bool {
    compareShape(lhs: value, rhs: other.value)
  }
}

private func compareShape<S: ShapePrimitive>(lhs: S, rhs: any ShapePrimitive) -> Bool {
  guard let rhs = rhs as? S else { return false }
  return defaultValueIsEquivalent(lhs, rhs)
}

// MARK: - SwiftUI Shape Adapter

/// Bridges any SwiftUI `Shape` into CanopyKit's `ShapePrimitive` protocol.
private struct SwiftUIShapeAdapter<S: Shape>: ShapePrimitive {
  let source: S

  func path(in rect: CGRect) -> Path {
    source.path(in: rect)
  }

  func sizeThatFits(proposal: ProposedSize) -> CGSize {
    source.sizeThatFits(ProposedViewSize(
      width: proposal.width,
      height: proposal.height
    ))
  }
}
