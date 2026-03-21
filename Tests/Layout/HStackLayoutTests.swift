import CoreGraphics
import Testing
@testable import CanopyKit

@Suite struct HStackLayoutTests {
  @Test func basicHorizontalStacking() {
    let a = fixedLeaf(width: 50, height: 20)
    let b = fixedLeaf(width: 60, height: 30)
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 10)), [a, b])

    root.layoutPass(width: 200)

    #expect(root.frame == CGRect(x: 0, y: 0, width: 120, height: 30))
    #expect(a.frame == CGRect(x: 0, y: 0, width: 50, height: 20))
    #expect(b.frame == CGRect(x: 60, y: 0, width: 60, height: 30))
  }

  @Test func secondChildGetsReducedProposal() {
    // First child takes 80px, spacing 10, so second child gets proposed 200-80-10=110.
    // Second child wants 200 width but should be clamped to 110.
    let a = fixedLeaf(width: 80, height: 20)
    let b = fixedLeaf(width: 200, height: 20)
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 10)), [a, b])

    root.layoutPass(width: 200)

    #expect(b.frame.size.width == 110)
  }

  @Test func emptyHStack() {
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 10)), [])

    root.layoutPass(width: 200)

    #expect(root.frame.size == CGSize(width: 0, height: 0))
  }

  @Test func singleChild() {
    let a = fixedLeaf(width: 50, height: 20)
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 10)), [a])

    root.layoutPass(width: 200)

    #expect(root.frame == CGRect(x: 0, y: 0, width: 50, height: 20))
    #expect(a.frame == CGRect(x: 0, y: 0, width: 50, height: 20))
  }

  @Test func heightIsTallestChild() {
    let short = fixedLeaf(width: 40, height: 10)
    let tall = fixedLeaf(width: 40, height: 50)
    let medium = fixedLeaf(width: 40, height: 30)
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 0)), [short, tall, medium])

    root.layoutPass(width: 200)

    #expect(root.frame.size.height == 50)
  }

  @Test func zeroSpacing() {
    let a = fixedLeaf(width: 30, height: 20)
    let b = fixedLeaf(width: 40, height: 20)
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 0)), [a, b])

    root.layoutPass(width: 200)

    #expect(root.frame.size.width == 70)
    #expect(b.frame.origin.x == 30)
  }

  @Test func totalWidthClampedToProposal() {
    // Two children that together exceed the proposal.
    let a = fixedLeaf(width: 120, height: 20)
    let b = fixedLeaf(width: 120, height: 20)
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 10)), [a, b])

    root.layoutPass(width: 200)

    // a takes 120, spacing 10, b proposed max(0, 200-120-10)=70, takes min(120,70)=70
    // total content = 120+10+70 = 200, clamped to 200
    #expect(root.frame.size.width == 200)
  }
}
