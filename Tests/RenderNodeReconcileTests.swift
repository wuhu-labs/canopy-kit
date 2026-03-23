@testable import CanopyKit
import Testing

private struct EmptyComponent: Component, Equatable {
  func body() -> Node {
    .layout(AnyLayout(VStackLayout()), children: [])
  }
}

@Suite struct RenderNodeReconcileTests {
  @Test func reconcilingEquivalentTreePreservesCachedLayout() {
    let initialResolved = makeResolvedTree()
    let renderNode = RenderNode.make(from: initialResolved)

    renderNode.layoutPass(width: 200)
    #expect(renderNode.cachedSize != nil)
    #expect(renderNode.children.first?.cachedSize != nil)
    #expect(renderNode.children.first?.children.first?.cachedSize != nil)

    let updatedResolved = makeResolvedTree()
    let reconciled = RenderNode.reconcile(existing: renderNode, with: updatedResolved)

    #expect(reconciled === renderNode)
    #expect(reconciled.cachedSize != nil)
    #expect(reconciled.children.first?.cachedSize != nil)
    #expect(reconciled.children.first?.children.first?.cachedSize != nil)
  }
}

private func makeResolvedTree() -> ResolvedNode {
  let leaf = ResolvedNode(
    id: NodeID(rawValue: 3),
    content: .primitive(.customDrawing(fixedDrawing(width: 100, height: 20)))
  )
  let layout = ResolvedNode(
    id: NodeID(rawValue: 2),
    content: .layout(AnyLayout(VStackLayout()), [leaf])
  )
  return ResolvedNode(
    id: NodeID(rawValue: 1),
    content: .component(AnyComponent(EmptyComponent()), layout)
  )
}
