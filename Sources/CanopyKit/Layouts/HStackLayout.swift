import CoreGraphics

// MARK: - HStackLayout

public struct HStackLayout: Layout, Equatable {
  public var spacing: CGFloat

  public init(spacing: CGFloat = 0) {
    self.spacing = spacing
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    let proposedWidth = proposal.width
    let proposedHeight = proposal.height
    var placements: [LayoutPlacement] = []
    var x: CGFloat = 0
    var maxHeight: CGFloat = 0

    for (index, subview) in subviews.enumerated() {
      if index > 0 { x += spacing }
      let remainingWidth = proposedWidth.map { max(0, $0 - x) }
      let childProposal = ProposedSize(width: remainingWidth, height: proposedHeight)
      let childSize = subview.sizeThatFits(
        proposal: childProposal
      )
      placements.append(LayoutPlacement(origin: CGPoint(x: x, y: 0), proposal: childProposal))
      x += childSize.width
      maxHeight = max(maxHeight, childSize.height)
    }

    let width = proposedWidth.map { min(x, $0) } ?? x
    return (size: CGSize(width: width, height: maxHeight), placements: placements)
  }
}
