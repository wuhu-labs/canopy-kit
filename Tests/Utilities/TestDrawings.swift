@testable import CanopyKit
import CoreGraphics

// MARK: - Fixed-Size Drawing

/// A trivial drawing with a fixed intrinsic size, no CoreText dependency.
/// Behaves like a rigid view: returns its intrinsic size regardless of proposal.
struct FixedSizeDrawing: CustomDrawing {
  var width: CGFloat
  var height: CGFloat

  struct Cache {}
  typealias Commitment = CGRect

  func makeCache() -> Cache {
    Cache()
  }

  func sizeThatFits(proposal: ProposedSize, cache _: inout Cache) -> CGSize {
    let w = proposal.width.map { min(width, $0) } ?? width
    let h = proposal.height.map { min(height, $0) } ?? height
    return CGSize(width: w, height: h)
  }

  func makeCommitment(in bounds: CGRect, cache _: Cache) -> CGRect {
    bounds
  }

  func draw(in _: CGContext, commitment _: CGRect) {}
}

// MARK: - Flexible Drawing

/// A fully flexible drawing that accepts whatever is proposed, falling back
/// to a small ideal size for unspecified dimensions (like SwiftUI shapes).
struct FlexibleDrawing: CustomDrawing {
  var idealWidth: CGFloat = 10
  var idealHeight: CGFloat = 10

  struct Cache {}
  typealias Commitment = CGRect

  func makeCache() -> Cache {
    Cache()
  }

  func sizeThatFits(proposal: ProposedSize, cache _: inout Cache) -> CGSize {
    CGSize(
      width: proposal.width ?? idealWidth,
      height: proposal.height ?? idealHeight
    )
  }

  func makeCommitment(in bounds: CGRect, cache _: Cache) -> CGRect {
    bounds
  }

  func draw(in _: CGContext, commitment _: CGRect) {}
}

// MARK: - Convenience Constructors

func fixedLeaf(width: CGFloat, height: CGFloat) -> RenderNode {
  .leaf(AnyDrawing(FixedSizeDrawing(width: width, height: height)))
}

func fixedDrawing(width: CGFloat, height: CGFloat) -> AnyDrawing {
  AnyDrawing(FixedSizeDrawing(width: width, height: height))
}

func flexibleLeaf(idealWidth: CGFloat = 10, idealHeight: CGFloat = 10) -> RenderNode {
  .leaf(AnyDrawing(FlexibleDrawing(idealWidth: idealWidth, idealHeight: idealHeight)))
}

func flexibleDrawing(idealWidth: CGFloat = 10, idealHeight: CGFloat = 10) -> AnyDrawing {
  AnyDrawing(FlexibleDrawing(idealWidth: idealWidth, idealHeight: idealHeight))
}
