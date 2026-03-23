@testable import CanopyKit
import CoreGraphics
import IdentifiedCollections
import SwiftUI
import Testing

private struct StubComponent: Component {
  func body() -> Node {
    .primitive(.drawing(fixedDrawing(width: 0, height: 0)))
  }
}

private final class DrawingCacheRecorder {
  var makeCount = 0
  var updateCount = 0
}

private struct TrackingDrawing: CustomDrawing {
  let token: Int
  let recorder: DrawingCacheRecorder

  struct Cache {
    var token: Int
  }

  func makeCache() -> Cache {
    recorder.makeCount += 1
    return Cache(token: token)
  }

  func updateCache(_ cache: inout Cache) {
    recorder.updateCount += 1
    cache.token = token
  }

  func sizeThatFits(proposal _: ProposedSize, cache _: inout Cache) -> CGSize {
    CGSize(width: 100, height: 20)
  }

  func draw(in _: CGContext, bounds _: CGRect, cache _: Cache) {}
}

@MainActor
@Suite struct RenderRuntimeTests {
  @Test func visibleProjectionKeepsHierarchyAndFiltersInvisibleChildren() {
    let runtime = RenderRuntime()
    let body = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .layout(
        AnyLayout(VStackLayout(spacing: 0)),
        [
          ResolvedNode(
            id: NodeID(rawValue: 2),
            content: .primitive(.drawing(fixedDrawing(width: 100, height: 20)))
          ),
          ResolvedNode(
            id: NodeID(rawValue: 3),
            content: .primitive(.drawing(fixedDrawing(width: 100, height: 20)))
          ),
        ]
      )
    )
    let root = ResolvedNode(
      id: .root,
      content: .component(AnyComponent(StubComponent()), body)
    )

    let view = runtime.visibleView(
      root: root,
      proposal: ProposedSize(width: 100, height: nil),
      viewport: CGRect(x: 0, y: 0, width: 100, height: 19)
    )

    #expect(view != nil)
    #expect(view?.children.count == 1)
    #expect(view?.children.first?.children.count == 1)
  }

  @Test func shapePrimitiveProducesViewCommitment() throws {
    let runtime = RenderRuntime()

    var values = NodeValues()
    values[PrimitiveFillColorKey.self] = CGColor(gray: 0.2, alpha: 1)
    values[PrimitiveStrokeStyleKey.self] = PrimitiveStrokeStyle(
      color: CGColor(gray: 0.8, alpha: 1),
      lineWidth: 2
    )
    let root = ResolvedNode(
      id: .root,
      content: .primitive(.shape(AnyShape(Rectangle()))),
      values: values
    )

    let renderRoot = runtime.layout(
      root: root,
      proposal: ProposedSize(width: 80, height: nil)
    )

    let leaf = try #require(renderRoot.leaves().first)
    guard case let .primitive(_, commitment) = leaf.content else {
      Issue.record("Expected primitive render node")
      return
    }
    guard let commitment else {
      Issue.record("Expected shape view commitment")
      return
    }

    #expect(commitment.primitive.isEquivalent(to: .shape(AnyShape(Rectangle()))))
    #expect(leaf.frame.width == 80)
    #expect(leaf.values[PrimitiveStrokeStyleKey.self]?.lineWidth == 2)
  }

  @Test func customDrawingPrimitiveProducesViewCommitment() throws {
    let runtime = RenderRuntime()
    let root = ResolvedNode(
      id: .root,
      content: .primitive(.drawing(fixedDrawing(width: 80, height: 20)))
    )

    let renderRoot = runtime.layout(
      root: root,
      proposal: ProposedSize(width: 100, height: nil)
    )

    let leaf = try #require(renderRoot.leaves().first)
    guard case let .primitive(_, commitment) = leaf.content else {
      Issue.record("Expected primitive render node")
      return
    }
    guard let commitment else {
      Issue.record("Expected custom drawing view commitment")
      return
    }

    #expect(commitment.primitive.isEquivalent(to: .drawing(fixedDrawing(width: 80, height: 20))))
    #expect(leaf.frame.size == CGSize(width: 80, height: 20))
  }

  @Test func viewModifierKeyIsSetByViewModifier() {
    struct TestModifier: ViewModifier {
      func body(content: Content) -> some View {
        content
      }
    }
    let node = Node.primitive(.drawing(fixedDrawing(width: 60, height: 20)))
      .viewModifier(TestModifier())

    #expect(node.values[ViewModifierKey.self] != nil)
  }

  @Test func unchangedResolvedSubtreesArePointerSharedAcrossRefreshes() async throws {
    let model = PairModel()
    let counter = RenderCounter()
    let renderer = ComponentRenderer(
      root: AnyComponent(
        CountingRootComponent(model: model, counter: counter)
      )
    )

    let initialRoot = renderer.resolvedRoot
    let initialBody = try #require(initialRoot.children.first)
    let initialRight = try #require(initialBody.children.last)

    model.left = 5
    let initialRevision = renderer.revision
    for _ in 0 ..< 10 {
      if renderer.revision > initialRevision { break }
      await Task.yield()
    }

    let updatedBody = try #require(renderer.resolvedRoot.children.first)
    let updatedRight = try #require(updatedBody.children.last)
    #expect(initialRight === updatedRight)
  }

  @Test func customDrawingCacheUpdatesAcrossResolvedNodeRebuilds() {
    let runtime = RenderRuntime()
    let recorder = DrawingCacheRecorder()

    let initialRoot = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .primitive(.drawing(AnyDrawing(TrackingDrawing(token: 1, recorder: recorder))))
    )
    _ = runtime.sizeThatFits(root: initialRoot, proposal: ProposedSize(width: 100, height: nil))

    let updatedRoot = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .primitive(.drawing(AnyDrawing(TrackingDrawing(token: 2, recorder: recorder))))
    )
    _ = runtime.sizeThatFits(root: updatedRoot, proposal: ProposedSize(width: 100, height: nil))

    #expect(recorder.makeCount == 1)
    #expect(recorder.updateCount == 1)
  }

  @Test func insertingHeadOnlyRebuildsShiftedAncestorChain() throws {
    let runtime = RenderRuntime()
    let nestedLeafD = ResolvedNode(
      id: NodeID(rawValue: 5),
      content: .primitive(.drawing(fixedDrawing(width: 100, height: 20)))
    )
    let nestedLeafE = ResolvedNode(
      id: NodeID(rawValue: 6),
      content: .primitive(.drawing(fixedDrawing(width: 100, height: 20)))
    )
    let nestedStack = ResolvedNode(
      id: NodeID(rawValue: 4),
      content: .layout(
        AnyLayout(VStackLayout(spacing: 0)),
        [nestedLeafD, nestedLeafE]
      )
    )
    let leafB = ResolvedNode(
      id: NodeID(rawValue: 3),
      content: .primitive(.drawing(fixedDrawing(width: 100, height: 20)))
    )
    let initialRoot = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .layout(
        AnyLayout(VStackLayout(spacing: 0)),
        [leafB, nestedStack]
      )
    )

    let initialRenderRoot = runtime.layout(
      root: initialRoot,
      proposal: ProposedSize(width: 100, height: nil)
    )
    let initialNestedStack = try #require(findRenderNode(in: initialRenderRoot, id: NodeID(rawValue: 4)))
    let initialNestedLeafD = try #require(findRenderNode(in: initialRenderRoot, id: NodeID(rawValue: 5)))
    let initialNestedLeafE = try #require(findRenderNode(in: initialRenderRoot, id: NodeID(rawValue: 6)))

    let insertedHead = ResolvedNode(
      id: NodeID(rawValue: 2),
      content: .primitive(.drawing(fixedDrawing(width: 100, height: 20)))
    )
    let updatedRoot = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .layout(
        AnyLayout(VStackLayout(spacing: 0)),
        [insertedHead, leafB, nestedStack]
      )
    )

    let updatedRenderRoot = runtime.layout(
      root: updatedRoot,
      proposal: ProposedSize(width: 100, height: nil)
    )
    let updatedNestedStack = try #require(findRenderNode(in: updatedRenderRoot, id: NodeID(rawValue: 4)))
    let updatedNestedLeafD = try #require(findRenderNode(in: updatedRenderRoot, id: NodeID(rawValue: 5)))
    let updatedNestedLeafE = try #require(findRenderNode(in: updatedRenderRoot, id: NodeID(rawValue: 6)))

    #expect(initialNestedStack !== updatedNestedStack)
    #expect(initialNestedLeafD === updatedNestedLeafD)
    #expect(initialNestedLeafE === updatedNestedLeafE)
    #expect(initialNestedLeafD.frame == updatedNestedLeafD.frame)
    #expect(initialNestedLeafE.frame == updatedNestedLeafE.frame)
  }
}

private func findRenderNode(in root: ResolvedRenderNode, id: NodeID) -> ResolvedRenderNode? {
  if root.id == id {
    return root
  }
  for child in root.children {
    if let match = findRenderNode(in: child, id: id) {
      return match
    }
  }
  return nil
}
