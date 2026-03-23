@testable import CanopyKit
import CoreGraphics
import Testing

@Suite struct FrameLayoutTests {
  @Test func fixedWidthAndHeight() {
    let child = fixedLeaf(width: 200, height: 100)
    let root = RenderNode.container(AnyLayout(FrameLayout(width: 80, height: 60)), [child])

    root.layoutPass(width: 400)

    // Child proposed (80, 60), takes min(200,80)=80, min(100,60)=60.
    #expect(child.frame.size == CGSize(width: 80, height: 60))
    // Container reports (80, 60).
    #expect(root.frame.size == CGSize(width: 80, height: 60))
    // Child centered within container (same size, so origin 0,0).
    #expect(child.frame.origin == CGPoint(x: 0, y: 0))
  }

  @Test func fixedWidthOnly() {
    let child = fixedLeaf(width: 200, height: 50)
    let root = RenderNode.container(AnyLayout(FrameLayout(width: 100)), [child])

    root.layoutPass(width: 400)

    // Width overridden to 100, height passes through parent's nil.
    #expect(child.frame.size == CGSize(width: 100, height: 50))
    #expect(root.frame.size == CGSize(width: 100, height: 50))
  }

  @Test func fixedHeightOnly() {
    let child = fixedLeaf(width: 80, height: 200)
    let root = RenderNode.container(AnyLayout(FrameLayout(height: 60)), [child])

    root.layoutPass(width: 400)

    // Height overridden to 60, width passes through parent's 400.
    #expect(child.frame.size == CGSize(width: 80, height: 60))
    #expect(root.frame.size == CGSize(width: 80, height: 60))
  }

  @Test func centersChildWhenContainerIsLarger() {
    // Child is smaller than the fixed frame — should be centered.
    let child = fixedLeaf(width: 40, height: 20)
    let root = RenderNode.container(AnyLayout(FrameLayout(width: 100, height: 60)), [child])

    root.layoutPass(width: 400)

    #expect(root.frame.size == CGSize(width: 100, height: 60))
    #expect(child.frame.size == CGSize(width: 40, height: 20))
    #expect(child.frame.origin == CGPoint(x: 30, y: 20))
  }

  @Test func emptyFrame() {
    let root = RenderNode.container(AnyLayout(FrameLayout(width: 100, height: 50)), [])

    root.layoutPass(width: 400)

    #expect(root.frame.size == CGSize(width: 100, height: 50))
  }

  @Test func passesThrough() {
    // No explicit width or height — passes parent proposal through.
    let child = fixedLeaf(width: 80, height: 40)
    let root = RenderNode.container(AnyLayout(FrameLayout()), [child])

    root.layoutPass(width: 300)

    // Child proposed (300, nil), takes min(80,300)=80, 40.
    #expect(child.frame.size == CGSize(width: 80, height: 40))
    #expect(root.frame.size == CGSize(width: 80, height: 40))
  }

  @Test func flexibleChildFillsFrame() {
    let child = flexibleLeaf()
    let root = RenderNode.container(AnyLayout(FrameLayout(width: 200, height: 100)), [child])

    root.layoutPass(width: 400)

    // Flexible child accepts the proposed (200, 100).
    #expect(child.frame.size == CGSize(width: 200, height: 100))
    #expect(root.frame.size == CGSize(width: 200, height: 100))
  }

  @Test func frameInsideHStack() {
    // Two fixed-width columns in an HStack.
    let left = fixedLeaf(width: 200, height: 30)
    let right = fixedLeaf(width: 200, height: 40)
    let leftFrame = RenderNode.container(AnyLayout(FrameLayout(width: 100)), [left])
    let rightFrame = RenderNode.container(AnyLayout(FrameLayout(width: 100)), [right])
    let root = RenderNode.container(AnyLayout(HStackLayout(spacing: 10)), [leftFrame, rightFrame])

    root.layoutPass(width: 400)

    #expect(leftFrame.frame.size == CGSize(width: 100, height: 30))
    #expect(rightFrame.frame.size == CGSize(width: 100, height: 40))
    #expect(rightFrame.frame.origin.x == 110)
    #expect(root.frame.size == CGSize(width: 210, height: 40))
  }
}
