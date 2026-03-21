import SwiftUI

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

public extension AnyShape {
  /// Creates an `AnyShape` from any SwiftUI `Shape`.
  init(_ shape: some Shape) {
    self.init(SwiftUIShapeAdapter(source: shape))
  }
}
