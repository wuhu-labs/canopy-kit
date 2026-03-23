import CoreGraphics

// MARK: - ComposedUnaryLayout

/// Composes two unary (single-child) layouts into one, eliminating a level
/// of nesting in the node tree.
///
/// Given `outer` wrapping `inner`, the composed layout:
/// 1. Asks `outer` to lay out a single virtual child (whose size comes from `inner`)
/// 2. Asks `inner` to lay out the real children with the proposal `outer` assigned
/// 3. Offsets `inner`'s placements by `outer`'s origin
///
/// This means `node.padding(10).frame(width: 200)` produces a single layout
/// node instead of two nested ones.
struct ComposedUnaryLayout: Layout, Equatable {
  var outer: AnyLayout
  var inner: AnyLayout

  init(outer: AnyLayout, inner: AnyLayout) {
    self.outer = outer
    self.inner = inner
  }

  func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    // Ask outer to lay out a single virtual child whose measurement
    // delegates to inner.
    let outerResult = outer.layout(
      subviews: [LayoutSubview { outerProposal in
        inner.layout(subviews: subviews, proposal: outerProposal).size
      }],
      proposal: proposal
    )

    guard let outerPlacement = outerResult.placements.first else {
      return (size: outerResult.size, placements: subviews.map { _ in LayoutPlacement() })
    }

    // Run inner with the proposal outer assigned to its virtual child.
    let innerResult = inner.layout(subviews: subviews, proposal: outerPlacement.proposal)

    // Compose origins: shift inner placements by outer's origin.
    let placements = innerResult.placements.map { placement in
      LayoutPlacement(
        origin: CGPoint(
          x: outerPlacement.origin.x + placement.origin.x,
          y: outerPlacement.origin.y + placement.origin.y
        ),
        proposal: placement.proposal
      )
    }

    return (size: outerResult.size, placements: placements)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.outer.isEquivalent(to: rhs.outer) && lhs.inner.isEquivalent(to: rhs.inner)
  }
}
