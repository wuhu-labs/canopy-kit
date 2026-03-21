import CoreGraphics

// MARK: - InsetLayout

public struct InsetLayout: Layout, Equatable {
  public var left: CGFloat
  public var top: CGFloat
  public var right: CGFloat
  public var bottom: CGFloat

  public init(left: CGFloat = 0, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0) {
    self.left = left
    self.top = top
    self.right = right
    self.bottom = bottom
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    guard let subview = subviews.first else {
      let width = proposal.width ?? (left + right)
      return (size: CGSize(width: width, height: top + bottom), placements: [])
    }

    let innerWidth = proposal.width.map { max(0, $0 - left - right) }
    let innerHeight = proposal.height.map { max(0, $0 - top - bottom) }
    let childProposal = ProposedSize(width: innerWidth, height: innerHeight)
    let childSize = subview.sizeThatFits(
      proposal: childProposal
    )
    return (
      size: CGSize(
        width: childSize.width + left + right,
        height: childSize.height + top + bottom
      ),
      placements: [LayoutPlacement(origin: CGPoint(x: left, y: top), proposal: childProposal)]
    )
  }
}
