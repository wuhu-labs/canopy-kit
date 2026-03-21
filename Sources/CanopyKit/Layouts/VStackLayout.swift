import CoreGraphics

// MARK: - VStackLayout

public struct VStackLayout: Layout, Equatable {
  public var spacing: CGFloat

  public init(spacing: CGFloat = 0) {
    self.spacing = spacing
  }

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    let proposedWidth = proposal.width
    var placements: [LayoutPlacement] = []
    var y: CGFloat = 0
    var maxWidth: CGFloat = 0

    for (index, subview) in subviews.enumerated() {
      if index > 0 { y += spacing }
      let childProposal = ProposedSize(width: proposedWidth, height: nil)
      let childSize = subview.sizeThatFits(
        proposal: childProposal
      )
      placements.append(LayoutPlacement(origin: CGPoint(x: 0, y: y), proposal: childProposal))
      y += childSize.height
      maxWidth = max(maxWidth, childSize.width)
    }

    let width = proposedWidth ?? maxWidth
    return (size: CGSize(width: width, height: y), placements: placements)
  }
}
