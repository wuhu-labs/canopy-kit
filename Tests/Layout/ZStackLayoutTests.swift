import CoreGraphics
import Testing
@testable import CanopyKit

@Suite struct ZStackLayoutTests {
  @Test func singleChild() {
    let child = fixedLeaf(width: 80, height: 40)
    let root = RenderNode.container(AnyLayout(ZStackLayout()), [child])

    root.layoutPass(width: 200)

    #expect(child.frame == CGRect(x: 0, y: 0, width: 80, height: 40))
    #expect(root.frame.size == CGSize(width: 80, height: 40))
  }

  @Test func unionOfChildSizes() {
    let small = fixedLeaf(width: 40, height: 20)
    let large = fixedLeaf(width: 100, height: 60)
    let root = RenderNode.container(AnyLayout(ZStackLayout()), [small, large])

    root.layoutPass(width: 200)

    // Union is (100, 60). Both placed at origin.
    #expect(root.frame.size == CGSize(width: 100, height: 60))
    #expect(small.frame.origin == .zero)
    #expect(large.frame.origin == .zero)
  }

  @Test func flexibleChildStretchesToUnionSize() {
    // A flexible drawing (like a background rect) should stretch to match
    // the union size from the second pass.
    let background = flexibleLeaf()
    let content = fixedLeaf(width: 120, height: 80)
    let root = RenderNode.container(AnyLayout(ZStackLayout()), [background, content])

    root.layoutPass(width: 200)

    // Pass 1: background gets proposed (200, nil) → (200, 10)
    //         content gets proposed (200, nil) → (120, 80)
    //         union = (200, 80)
    // Pass 2: background re-proposed (200, 80) → (200, 80) ✓
    //         content re-proposed (200, 80) → (120, 80)
    //         final union = (200, 80)
    #expect(background.frame.size == CGSize(width: 200, height: 80))
    #expect(content.frame.size == CGSize(width: 120, height: 80))
    #expect(root.frame.size == CGSize(width: 200, height: 80))
  }

  @Test func emptyZStack() {
    let root = RenderNode.container(AnyLayout(ZStackLayout()), [])

    root.layoutPass(width: 200)

    #expect(root.frame.size == CGSize(width: 0, height: 0))
  }

  @Test func allChildrenAtSameOrigin() {
    let a = fixedLeaf(width: 50, height: 30)
    let b = fixedLeaf(width: 80, height: 20)
    let c = fixedLeaf(width: 30, height: 50)
    let root = RenderNode.container(AnyLayout(ZStackLayout()), [a, b, c])

    root.layoutPass(width: 200)

    #expect(a.frame.origin == .zero)
    #expect(b.frame.origin == .zero)
    #expect(c.frame.origin == .zero)
  }

  @Test func backgroundRectBehindText() {
    // Realistic scenario: a colored rect behind a fixed-size text block.
    let bgRect = flexibleLeaf()
    let text = fixedLeaf(width: 150, height: 40)
    let zstack = RenderNode.container(AnyLayout(ZStackLayout()), [bgRect, text])
    let root = RenderNode.container(AnyLayout(VStackLayout()), [zstack])

    root.layoutPass(width: 300)

    // The ZStack should size to the union, and the background should fill it.
    #expect(zstack.frame.size == CGSize(width: 300, height: 40))
    #expect(bgRect.frame.size == CGSize(width: 300, height: 40))
    #expect(text.frame.size == CGSize(width: 150, height: 40))
  }
}
