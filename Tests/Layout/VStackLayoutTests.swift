@testable import CanopyKit
import CoreGraphics
import Testing

@Suite struct VStackLayoutTests {
  @Test func basicVerticalStacking() {
    let a = fixedLeaf(width: 100, height: 20)
    let b = fixedLeaf(width: 100, height: 30)
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 10)), [a, b])

    root.layoutPass(width: 200)

    #expect(root.frame == CGRect(x: 0, y: 0, width: 200, height: 60))
    #expect(a.frame == CGRect(x: 0, y: 0, width: 100, height: 20))
    #expect(b.frame == CGRect(x: 0, y: 30, width: 100, height: 30))
  }

  @Test func emptyVStack() {
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 10)), [])

    root.layoutPass(width: 200)

    #expect(root.frame == CGRect(x: 0, y: 0, width: 200, height: 0))
  }

  @Test func singleChild() {
    let a = fixedLeaf(width: 80, height: 40)
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 10)), [a])

    root.layoutPass(width: 200)

    #expect(root.frame == CGRect(x: 0, y: 0, width: 200, height: 40))
    #expect(a.frame == CGRect(x: 0, y: 0, width: 80, height: 40))
  }

  @Test func spacingAccumulatesCorrectly() {
    let children = (0 ..< 5).map { _ in fixedLeaf(width: 100, height: 10) }
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 8)), children)

    root.layoutPass(width: 200)

    // 5 * 10 + 4 * 8 = 82
    #expect(root.frame.size == CGSize(width: 200, height: 82))
  }

  @Test func zeroSpacing() {
    let a = fixedLeaf(width: 100, height: 20)
    let b = fixedLeaf(width: 100, height: 30)
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 0)), [a, b])

    root.layoutPass(width: 200)

    #expect(root.frame.size == CGSize(width: 200, height: 50))
    #expect(b.frame.origin.y == 20)
  }

  @Test func childrenReceiveParentWidth() {
    // A child wider than the proposal should be clamped.
    let wide = fixedLeaf(width: 500, height: 20)
    let root = RenderNode.container(AnyLayout(VStackLayout()), [wide])

    root.layoutPass(width: 200)

    // FixedSizeDrawing clamps to min(intrinsic, proposed).
    #expect(wide.frame.size.width == 200)
  }

  @Test func repeatedLayoutPassProducesSameFrames() {
    let a = fixedLeaf(width: 100, height: 20)
    let b = fixedLeaf(width: 100, height: 30)
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 10)), [a, b])

    root.layoutPass(width: 200)
    let firstA = a.frame
    let firstB = b.frame
    let firstRoot = root.frame

    root.layoutPass(width: 200)
    #expect(a.frame == firstA)
    #expect(b.frame == firstB)
    #expect(root.frame == firstRoot)
  }
}
