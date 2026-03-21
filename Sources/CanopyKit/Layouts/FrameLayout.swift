import CoreGraphics

// MARK: - FrameLayout

public struct FrameLayout: Layout, Equatable {
  public var width: CGFloat?
  public var height: CGFloat?

  public init(width: CGFloat? = nil, height: CGFloat? = nil) {
    self.width = width
    self.height = height
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    guard let subview = subviews.first else {
      return (
        size: CGSize(width: width ?? 0, height: height ?? 0),
        placements: []
      )
    }

    let childProposal = ProposedSize(
      width: width ?? proposal.width,
      height: height ?? proposal.height
    )
    let childSize = subview.sizeThatFits(proposal: childProposal)
    let containerSize = CGSize(
      width: width ?? childSize.width,
      height: height ?? childSize.height
    )
    return (
      size: containerSize,
      placements: [
        LayoutPlacement(
          origin: CGPoint(
            x: max(0, (containerSize.width - childSize.width) / 2),
            y: max(0, (containerSize.height - childSize.height) / 2)
          ),
          proposal: childProposal
        ),
      ]
    )
  }
}
