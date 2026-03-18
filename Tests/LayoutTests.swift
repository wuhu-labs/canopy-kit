import CoreGraphics
import Observation
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

func fixedDrawing(width: CGFloat, height: CGFloat) -> AnyDrawing {
  AnyDrawing(FixedSizeDrawing(width: width, height: height))
}

struct ChildComponent: Component, Equatable {
  var key: String
  var height: CGFloat

  func body() -> ComponentBody {
    .drawingNode(key: key, fixedDrawing(width: 100, height: height))
  }
}

struct ParentComponent: Component, Equatable {
  func body() -> ComponentBody {
    .layoutNode(
      key: "root",
      AnyLayout(VStackLayout(spacing: 4)),
      children: [
        .drawingNode(key: "header", fixedDrawing(width: 100, height: 20)),
        .componentNode(key: "child", AnyComponent(ChildComponent(key: "body", height: 40))),
      ]
    )
  }
}

@Observable
final class ParagraphModel {
  var count = 2
}

struct ReactiveParagraphsComponent: Component {
  var model: ParagraphModel

  func body() -> ComponentBody {
    .layoutNode(
      key: "root",
      AnyLayout(VStackLayout(spacing: 4)),
      children: (0 ..< model.count).map { index in
        .drawingNode(key: index, fixedDrawing(width: 100, height: 20))
      }
    )
  }
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

    child.content = .leaf(AnyDrawing(FixedSizeDrawing(width: 100, height: 60)))
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

    body.content = .leaf(AnyDrawing(FixedSizeDrawing(width: 300, height: 80)))
    body.invalidateLayout()

    root.layoutPass(width: 400)
    #expect(hstack.frame.height == 80)
    #expect(inset.frame.height == 80)
    #expect(root.frame.height == 80)
  }
}

// MARK: - Component Tests

@Suite struct ComponentResolverTests {
  @Test func nestedComponentResolvesToPathBackedTree() {
    let root = ComponentResolver.resolve(AnyComponent(ParentComponent()))

    #expect(root.id == ["root"])
    #expect(root.children.count == 2)
    #expect(root.children[0].id == ["root", "header"])
    #expect(root.children[1].id == ["root", "child", "body"])
  }
}

@MainActor
@Suite struct ComponentRendererTests {
  @Test func observableChangeRefreshesRenderTree() async {
    let model = ParagraphModel()
    let renderer = ComponentRenderer(
      root: AnyComponent(
        ReactiveParagraphsComponent(model: model),
        isEquivalent: { lhs, rhs in lhs.model === rhs.model }
      )
    )

    let initialRevision = renderer.revision
    #expect(renderer.renderRoot.leaves().count == 2)

    model.count = 4
    for _ in 0 ..< 10 {
      if renderer.revision > initialRevision { break }
      await Task.yield()
    }

    #expect(renderer.revision > initialRevision)
    #expect(renderer.renderRoot.leaves().count == 4)
  }
}
