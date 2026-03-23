@testable import CanopyKit
import CoreGraphics
import Testing

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

  @Test func visibleLeavesFindsNestedLeaves() {
    let bullet = fixedLeaf(width: 10, height: 14)
    let body = fixedLeaf(width: 300, height: 28)
    let hstack = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, body])
    let inset = RenderNode.container(AnyLayout(InsetLayout(left: 16)), [hstack])
    let above = fixedLeaf(width: 100, height: 50)
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), [above, inset])

    root.layoutPass(width: 400)

    let allLeaves = root.visibleLeaves(in: CGRect(x: 0, y: 0, width: 400, height: 200))
    #expect(allLeaves.count == 3) // above + bullet + body
  }

  @Test func visibleLeavesConsistentAcrossRepeatedLayoutPass() {
    let bullet = fixedLeaf(width: 10, height: 14)
    let body = fixedLeaf(width: 300, height: 28)
    let hstack = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, body])
    let inset = RenderNode.container(AnyLayout(InsetLayout(left: 16)), [hstack])
    let above = fixedLeaf(width: 100, height: 50)
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), [above, inset])

    root.layoutPass(width: 400)
    let first = root.visibleLeaves(in: CGRect(x: 0, y: 0, width: 400, height: 200)).count

    root.layoutPass(width: 400)
    let second = root.visibleLeaves(in: CGRect(x: 0, y: 0, width: 400, height: 200)).count

    #expect(first == second)
    #expect(first == 3)
  }

  @Test func manyBlocksContentHeight() {
    // Simulate the demo scenario: many VStack children, check total height is reasonable.
    var children: [RenderNode] = []
    for _ in 0 ..< 100 {
      children.append(fixedLeaf(width: 400, height: 20))
    }
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), children)

    root.layoutPass(width: 400)

    // 100 * 20 + 99 * 4 = 2396
    #expect(root.cachedSize == CGSize(width: 400, height: 2396))
    #expect(root.frame == CGRect(x: 0, y: 0, width: 400, height: 2396))

    // Check that visible leaves near the bottom are found.
    let bottomLeaves = root.visibleLeaves(in: CGRect(x: 0, y: 2300, width: 400, height: 100))
    #expect(bottomLeaves.count > 0)
  }

  @Test func mixedNestedBlocksContentHeight() {
    // Simulate demo: mix of plain leaves and nested inset+hstack bullet items.
    var children: [RenderNode] = []
    for i in 0 ..< 50 {
      if i % 5 == 0 {
        // Bullet item: Inset > HStack > [bullet, body]
        let bullet = fixedLeaf(width: 10, height: 14)
        let body = fixedLeaf(width: 300, height: 28)
        let hstack = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, body])
        let inset = RenderNode.container(AnyLayout(InsetLayout(left: 16)), [hstack])
        children.append(inset)
      } else {
        children.append(fixedLeaf(width: 400, height: 20))
      }
    }
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), children)

    root.layoutPass(width: 400)

    // 10 bullets at height 28, 40 plain at height 20 = 10*28 + 40*20 + 49*4 = 280+800+196 = 1276
    #expect(root.cachedSize?.height == 1276)

    // All leaves should be visible in a tall enough rect.
    let allLeaves = root.visibleLeaves(in: CGRect(x: 0, y: 0, width: 400, height: 1276))
    // 10 bullets * 2 leaves + 40 plain = 60
    #expect(allLeaves.count == 60)

    // Leaves near the bottom should be found.
    let bottomLeaves = root.visibleLeaves(in: CGRect(x: 0, y: 1200, width: 400, height: 100))
    #expect(bottomLeaves.count > 0)
  }

  @Test func invalidatingLeafUpdatesRootLayout() {
    let child = fixedLeaf(width: 100, height: 20)
    let root = RenderNode.container(AnyLayout(VStackLayout()), [child])

    root.layoutPass(width: 200)
    #expect(root.frame.height == 20)

    child.content = .primitive(.drawing(FixedSizeDrawing(width: 100, height: 60)))
    child.invalidateLayout()

    root.layoutPass(width: 200)
    #expect(root.frame.height == 60)
    #expect(child.frame.height == 60)
  }

  @Test func invalidatingNestedLeafUpdatesAncestorLayouts() {
    let bullet = fixedLeaf(width: 10, height: 14)
    let body = fixedLeaf(width: 300, height: 28)
    let hstack = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, body])
    let inset = RenderNode.container(AnyLayout(InsetLayout(left: 16)), [hstack])
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), [inset])

    root.layoutPass(width: 400)
    #expect(root.frame.height == 28)

    body.content = .primitive(.drawing(FixedSizeDrawing(width: 300, height: 80)))
    body.invalidateLayout()

    root.layoutPass(width: 400)
    #expect(hstack.frame.height == 80)
    #expect(inset.frame.height == 80)
    #expect(root.frame.height == 80)
  }

  @Test func zstackInsideVStack() {
    // Card pattern: ZStack(background, content) inside a VStack.
    let bg = flexibleLeaf()
    let text = fixedLeaf(width: 150, height: 40)
    let card = RenderNode.container(AnyLayout(ZStackLayout()), [bg, text])

    let header = fixedLeaf(width: 200, height: 30)
    let root = RenderNode.container(AnyLayout(VStackLayout(spacing: 8)), [header, card])

    root.layoutPass(width: 300)

    #expect(header.frame == CGRect(x: 0, y: 0, width: 200, height: 30))
    #expect(card.frame.origin == CGPoint(x: 0, y: 38))
    #expect(card.frame.size == CGSize(width: 300, height: 40))
    #expect(bg.frame.size == CGSize(width: 300, height: 40))
  }

  @Test func frameInsideInset() {
    let child = fixedLeaf(width: 200, height: 100)
    let frame = RenderNode.container(AnyLayout(FrameLayout(width: 80, height: 60)), [child])
    let root = RenderNode.container(AnyLayout(InsetLayout(left: 10, top: 5)), [frame])

    root.layoutPass(width: 400)

    #expect(frame.frame.size == CGSize(width: 80, height: 60))
    #expect(frame.frame.origin == CGPoint(x: 10, y: 5))
    #expect(root.frame.size == CGSize(width: 90, height: 65))
  }
}
