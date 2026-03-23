@testable import CanopyKit
import CoreGraphics
import Testing

@Suite struct InsetLayoutTests {
  @Test func childGetsReducedProposal() {
    // Inset left=20 right=10, proposal=200 → child proposed 170.
    // Child wants 300 wide, so it should get min(300, 170) = 170.
    let child = fixedLeaf(width: 300, height: 40)
    let root = RenderNode.container(AnyLayout(InsetLayout(left: 20, right: 10)), [child])

    root.layoutPass(width: 200)

    #expect(child.frame == CGRect(x: 20, y: 0, width: 170, height: 40))
    #expect(root.frame == CGRect(x: 0, y: 0, width: 200, height: 40))
  }

  @Test func allEdges() {
    let child = fixedLeaf(width: 300, height: 300)
    let root = RenderNode.container(
      AnyLayout(InsetLayout(left: 10, top: 20, right: 30, bottom: 40)),
      [child]
    )

    root.layoutPass(width: 200)

    // Child proposed width: 200 - 10 - 30 = 160, takes min(300,160)=160
    // Child proposed height: nil, takes 300
    #expect(child.frame.origin == CGPoint(x: 10, y: 20))
    #expect(child.frame.size.width == 160)
    #expect(child.frame.size.height == 300)
    #expect(root.frame.size == CGSize(width: 200, height: 360))
  }

  @Test func emptyInset() {
    let root = RenderNode.container(
      AnyLayout(InsetLayout(left: 10, top: 20, right: 30, bottom: 40)),
      []
    )

    root.layoutPass(width: 200)

    #expect(root.frame.size == CGSize(width: 200, height: 60))
  }

  @Test func zeroInsets() {
    let child = fixedLeaf(width: 80, height: 50)
    let root = RenderNode.container(AnyLayout(InsetLayout()), [child])

    root.layoutPass(width: 200)

    #expect(child.frame == CGRect(x: 0, y: 0, width: 80, height: 50))
    #expect(root.frame.size == CGSize(width: 80, height: 50))
  }
}
