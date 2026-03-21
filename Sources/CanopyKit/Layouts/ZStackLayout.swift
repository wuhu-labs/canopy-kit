import CoreGraphics

// MARK: - ZStackLayout

public struct ZStackLayout: Layout, Equatable {
  public init() {}

  public func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    guard !subviews.isEmpty else {
      return (size: .zero, placements: [])
    }

    var sizes = subviews.map { $0.sizeThatFits(proposal: proposal) }
    let unionSize = CGSize(
      width: sizes.map(\.width).max() ?? 0,
      height: sizes.map(\.height).max() ?? 0
    )

    let unionProposal = ProposedSize(width: unionSize.width, height: unionSize.height)
    sizes = subviews.map { $0.sizeThatFits(proposal: unionProposal) }

    let finalSize = CGSize(
      width: sizes.map(\.width).max() ?? 0,
      height: sizes.map(\.height).max() ?? 0
    )
    return (
      size: finalSize,
      placements: subviews.map { _ in LayoutPlacement(origin: .zero, proposal: unionProposal) }
    )
  }
}
