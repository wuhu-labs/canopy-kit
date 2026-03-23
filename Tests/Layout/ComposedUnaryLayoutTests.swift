import CoreGraphics
import IdentifiedCollections
import Testing
@testable import CanopyKit

@Suite struct ComposedUnaryLayoutTests {
  // MARK: - ComposedUnaryLayout directly

  @Test func paddingThenFrame() {
    // Compose InsetLayout(left:10, top:5) with FrameLayout(width:80, height:60)
    // Outer = Frame, Inner = Inset
    let composed = ComposedUnaryLayout(
      outer: AnyLayout(FrameLayout(width: 100, height: 70)),
      inner: AnyLayout(InsetLayout(left: 10, top: 5, right: 10, bottom: 5))
    )

    let child = LayoutSubview({ _ in CGSize(width: 50, height: 30) })
    let result = composed.layout(subviews: [child], proposal: ProposedSize(width: 200, height: nil))

    // Frame forces 100x70. Inset subtracts 20x10 → child gets proposed 80x60.
    // Child returns 50x30. Inset adds back → 70x40. Frame centers: (15, 15).
    // Inset places child at (10, 5) within its own frame.
    // Composed origin = frame-center-offset + inset-offset.
    #expect(result.size == CGSize(width: 100, height: 70))
    #expect(result.placements.count == 1)
  }

  @Test func composedLayoutEquivalence() {
    let a = ComposedUnaryLayout(
      outer: AnyLayout(FrameLayout(width: 100)),
      inner: AnyLayout(InsetLayout(left: 10))
    )
    let b = ComposedUnaryLayout(
      outer: AnyLayout(FrameLayout(width: 100)),
      inner: AnyLayout(InsetLayout(left: 10))
    )
    let c = ComposedUnaryLayout(
      outer: AnyLayout(FrameLayout(width: 200)),
      inner: AnyLayout(InsetLayout(left: 10))
    )

    #expect(a == b)
    #expect(a != c)
  }

  // MARK: - Node.padding() composition

  @Test func paddingOnDrawingWraps() {
    let node = Node.drawing(fixedDrawing(width: 100, height: 20))
      .padding(left: 10, top: 5, right: 10, bottom: 5)

    // A drawing is a primitive, not a layout — should wrap in a new layout node.
    guard case let .layout(_, children) = node.content else {
      Issue.record("Expected layout node")
      return
    }
    #expect(children.count == 1)
  }

  @Test func paddingOnSingleChildLayoutComposes() {
    // Start with a frame layout wrapping a drawing.
    let inner = Node.layout(
      AnyLayout(FrameLayout(width: 100)),
      children: [.drawing(key: "d", fixedDrawing(width: 50, height: 20))]
    )

    let composed = inner.padding(left: 10)

    // Should compose, not nest — still one layout with one child.
    guard case let .layout(layout, children) = composed.content else {
      Issue.record("Expected layout node")
      return
    }
    #expect(children.count == 1)

    // The layout should be a ComposedUnaryLayout, not a plain InsetLayout wrapping FrameLayout.
    let result = layout.layout(
      subviews: [LayoutSubview({ _ in CGSize(width: 50, height: 20) })],
      proposal: ProposedSize(width: 200, height: nil)
    )
    // Frame(width:100) + Inset(left:10) → total width = 100 + 10 = 110
    #expect(result.size.width == 110)
  }

  @Test func frameOnSingleChildLayoutComposes() {
    let inner = Node.layout(
      AnyLayout(InsetLayout(left: 16, right: 16)),
      children: [.drawing(key: "d", fixedDrawing(width: 50, height: 20))]
    )

    let composed = inner.frame(width: 200)

    guard case let .layout(layout, children) = composed.content else {
      Issue.record("Expected layout node")
      return
    }
    #expect(children.count == 1)

    let result = layout.layout(
      subviews: [LayoutSubview({ _ in CGSize(width: 50, height: 20) })],
      proposal: ProposedSize(width: 400, height: nil)
    )
    // Frame forces width 200. Inset subtracts 32 → child proposed 168.
    // Child is 50 wide. Inset adds back → 82. Frame forces 200.
    #expect(result.size.width == 200)
  }

  @Test func chainingMultipleUnaryModifiersComposes() {
    let node = Node.drawing(fixedDrawing(width: 50, height: 20))
      .padding(left: 10, right: 10)
      .frame(width: 200)

    // First .padding() wraps the drawing.
    // Second .frame() composes with the padding layout.
    guard case let .layout(_, children) = node.content else {
      Issue.record("Expected layout node")
      return
    }
    // Should be a single child all the way down, not nested layouts.
    #expect(children.count == 1)
  }

  @Test func paddingOnMultiChildLayoutWraps() {
    // A VStack with 2 children — should NOT compose, should wrap.
    let vstack = Node.layout(
      AnyLayout(VStackLayout()),
      children: [
        .drawing(key: "a", fixedDrawing(width: 50, height: 20)),
        .drawing(key: "b", fixedDrawing(width: 50, height: 20)),
      ]
    )

    let padded = vstack.padding(10)

    guard case let .layout(_, children) = padded.content else {
      Issue.record("Expected layout node")
      return
    }
    // Wrapped: the VStack is now the single child of the padding layout.
    #expect(children.count == 1)
  }

  // MARK: - End-to-end layout pass

  @Test func composedLayoutProducesSameFramesAsNested() {
    // Nested: Inset > Frame > leaf
    let leaf1 = fixedLeaf(width: 50, height: 20)
    let frame1 = RenderNode.container(AnyLayout(FrameLayout(width: 80)), [leaf1])
    let inset1 = RenderNode.container(AnyLayout(InsetLayout(left: 10, top: 5)), [frame1])
    inset1.layoutPass(width: 200)

    // Composed
    let composed = ComposedUnaryLayout(
      outer: AnyLayout(InsetLayout(left: 10, top: 5)),
      inner: AnyLayout(FrameLayout(width: 80))
    )
    let leaf2 = fixedLeaf(width: 50, height: 20)
    let composedNode = RenderNode.container(AnyLayout(composed), [leaf2])
    composedNode.layoutPass(width: 200)

    #expect(inset1.frame == composedNode.frame)
    #expect(leaf1.frame == leaf2.frame)
  }
}
