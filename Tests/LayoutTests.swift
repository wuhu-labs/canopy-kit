import CoreGraphics
import Testing
@testable import WuhuUI

// MARK: - Test Drawing

/// A trivial drawing with a fixed size, no CoreText dependency.
struct FixedSizeDrawing: CustomDrawing {
  var width: CGFloat
  var height: CGFloat

  struct Cache {}
  func makeCache() -> Cache {
    Cache()
  }

  func sizeThatFits(width proposal: CGFloat, cache _: inout Cache) -> CGSize {
    CGSize(width: min(width, proposal), height: height)
  }

  func draw(in _: CGContext, bounds _: CGRect, cache _: inout Cache) {}
}

func fixedLeaf(width: CGFloat, height: CGFloat) -> RenderNode {
  .leaf(AnyDrawing(FixedSizeDrawing(width: width, height: height)))
}

// MARK: - VStack Tests

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
}

// MARK: - HStack Tests

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
}

// MARK: - InsetLayout Tests

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
}

// MARK: - Nested Layout Tests

@Suite struct NestedLayoutTests {
  @Test func insetWrappingHStack() {
    // InsetLayout(left: 16) wrapping HStack(spacing: 6) with two children.
    let bullet = fixedLeaf(width: 10, height: 14)
    let body = fixedLeaf(width: 300, height: 28)
    let hstack = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, body])
    let inset = RenderNode.container(AnyLayout(InsetLayout(left: 16)), [hstack])
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), [inset])

    root.layoutPass(width: 400)

    // Inset proposes 400-16=384 to hstack.
    // HStack: bullet gets proposed 384, takes 10. Body gets 384-10-6=368, takes min(300,368)=300.
    #expect(bullet.frame == CGRect(x: 16, y: 0, width: 10, height: 14))
    #expect(body.frame == CGRect(x: 32, y: 0, width: 300, height: 28))
  }

  @Test func repeatedLayoutPassProducesSameFrames() {
    // This is the suspected bug: calling layoutPass twice should give identical frames.
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

  @Test func repeatedLayoutPassNestedProducesSameFrames() {
    let bullet = fixedLeaf(width: 10, height: 14)
    let body = fixedLeaf(width: 300, height: 28)
    let hstack = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, body])
    let inset = RenderNode.container(AnyLayout(InsetLayout(left: 16)), [hstack])
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), [inset])

    root.layoutPass(width: 400)
    let firstBullet = bullet.frame
    let firstBody = body.frame

    root.layoutPass(width: 400)
    #expect(bullet.frame == firstBullet)
    #expect(body.frame == firstBody)
  }
}
