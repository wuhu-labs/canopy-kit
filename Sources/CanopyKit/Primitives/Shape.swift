import CoreGraphics
import SwiftUI

struct ShapeViewRepresentable<S: Shape>: CustomViewRepresentable {
  let shape: S

  func sizeThatFits(proposal: ProposedSize, cache _: inout Void) -> CGSize {
    shape.sizeThatFits(ProposedViewSize(width: proposal.width, height: proposal.height))
  }

  func makeCommitment(in bounds: CGRect, cache _: Void) -> Path {
    shape.path(in: bounds)
  }

  @MainActor
  func makeView(commitment: Path) -> some View {
    commitment
  }
}

extension ShapeViewRepresentable: Equatable where S: Equatable {}
