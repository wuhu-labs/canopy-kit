import CoreGraphics

// MARK: - Rect Drawing

/// A leaf that draws a filled rectangle. Fully flexible — accepts whatever
/// size is proposed, falling back to 10 × 10 for unspecified dimensions
/// (matching SwiftUI shape convention).
public struct RectDrawing: CustomDrawing {
  public var color: CGColor
  public var idealHeight: CGFloat

  public init(color: CGColor, height: CGFloat) {
    self.color = color
    idealHeight = height
  }

  public struct Cache {}

  public func makeCache() -> Cache {
    Cache()
  }

  public func sizeThatFits(proposal: ProposedSize, cache _: inout Cache) -> CGSize {
    CGSize(
      width: proposal.width ?? 10,
      height: proposal.height ?? idealHeight
    )
  }

  public func draw(in context: CGContext, bounds: CGRect, cache _: inout Cache) {
    context.setFillColor(color)
    context.fill(bounds)
  }
}
