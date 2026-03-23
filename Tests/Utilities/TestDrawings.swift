@testable import CanopyKit
import CoreGraphics

// MARK: - Fixed-Size Drawing

/// A trivial drawing with a fixed intrinsic size, no CoreText dependency.
/// Behaves like a rigid view: returns its intrinsic size regardless of proposal.
struct FixedSizeDrawing: CustomDrawing {
  var width: CGFloat
  var height: CGFloat

  typealias Commitment = CGRect

  func sizeThatFits(proposal: ProposedSize, cache _: inout Void) -> CGSize {
    let w = proposal.width.map { min(width, $0) } ?? width
    let h = proposal.height.map { min(height, $0) } ?? height
    return CGSize(width: w, height: h)
  }

  func makeCommitment(in bounds: CGRect, cache _: Void) -> CGRect {
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

  typealias Commitment = CGRect

  func sizeThatFits(proposal: ProposedSize, cache _: inout Void) -> CGSize {
    CGSize(
      width: proposal.width ?? idealWidth,
      height: proposal.height ?? idealHeight
    )
  }

  func makeCommitment(in bounds: CGRect, cache _: Void) -> CGRect {
    bounds
  }

  func draw(in _: CGContext, commitment _: CGRect) {}
}

// MARK: - Convenience Constructors

func fixedLeaf(width: CGFloat, height: CGFloat) -> RenderNode {
  let drawing = FixedSizeDrawing(width: width, height: height)
  let nodeID = NodeID(rawValue: Int.random(in: 1 ... Int.max))
  let resolvedNode = ResolvedNode(
    id: nodeID,
    content: .primitive(.init(drawing))
  )
  return RenderNode(
    .primitive(.init(drawing)),
    nodeID: nodeID,
    resolvedNode: resolvedNode
  )
}

func fixedDrawing(width: CGFloat, height: CGFloat) -> FixedSizeDrawing {
  FixedSizeDrawing(width: width, height: height)
}

func flexibleLeaf(idealWidth: CGFloat = 10, idealHeight: CGFloat = 10) -> RenderNode {
  let drawing = FlexibleDrawing(idealWidth: idealWidth, idealHeight: idealHeight)
  let nodeID = NodeID(rawValue: Int.random(in: 1 ... Int.max))
  let resolvedNode = ResolvedNode(
    id: nodeID,
    content: .primitive(.init(drawing))
  )
  return RenderNode(
    .primitive(.init(drawing)),
    nodeID: nodeID,
    resolvedNode: resolvedNode
  )
}

func flexibleDrawing(idealWidth: CGFloat = 10, idealHeight: CGFloat = 10) -> FlexibleDrawing {
  FlexibleDrawing(idealWidth: idealWidth, idealHeight: idealHeight)
}
