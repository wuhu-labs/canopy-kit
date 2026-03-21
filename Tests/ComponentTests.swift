import CoreGraphics
import IdentifiedCollections
import Observation
import Testing
@testable import CanopyKit

struct ChildComponent: Component, Equatable {
  var key: String
  var height: CGFloat

  func body() -> Node {
    .drawing(fixedDrawing(width: 100, height: height))
  }
}

struct ParentComponent: Component, Equatable {
  func body() -> Node {
    .layout(
      AnyLayout(VStackLayout(spacing: 4)),
      children: [
        .drawing(key: "header", fixedDrawing(width: 100, height: 20)),
        .component(key: "child", AnyComponent(ChildComponent(key: "body", height: 40))),
      ]
    )
  }
}

@Observable
final class ParagraphModel {
  var count = 2
}

@Observable
final class PairModel {
  var left = 1
  var right = 1
}

final class RenderCounter {
  var root = 0
  var left = 0
  var right = 0
}

struct ReactiveParagraphsComponent: Component {
  var model: ParagraphModel

  func body() -> Node {
    .layout(
      AnyLayout(VStackLayout(spacing: 4)),
      children: IdentifiedArray(
        uniqueElements: (0 ..< model.count).map { index in
          IdentifiedNode.drawing(
            key: index,
            fixedDrawing(width: 100, height: 20)
          )
        }
      )
    )
  }
}

struct CountingRootComponent: Component {
  let model: PairModel
  let counter: RenderCounter

  func body() -> Node {
    counter.root += 1

    return .layout(
      AnyLayout(VStackLayout(spacing: 4)),
      children: [
        .component(
          key: "left",
          AnyComponent(
            CountingLeafComponent(side: .left, model: model, counter: counter),
            isEquivalent: { lhs, rhs in
              lhs.side == rhs.side && lhs.model === rhs.model && lhs.counter === rhs.counter
            }
          )
        ),
        .component(
          key: "right",
          AnyComponent(
            CountingLeafComponent(side: .right, model: model, counter: counter),
            isEquivalent: { lhs, rhs in
              lhs.side == rhs.side && lhs.model === rhs.model && lhs.counter === rhs.counter
            }
          )
        ),
      ]
    )
  }
}

struct CountingLeafComponent: Component {
  enum Side {
    case left
    case right
  }

  let side: Side
  let model: PairModel
  let counter: RenderCounter

  func body() -> Node {
    let value: Int

    switch side {
    case .left:
      counter.left += 1
      value = model.left

    case .right:
      counter.right += 1
      value = model.right
    }

    return .drawing(
      fixedDrawing(width: CGFloat(80 + value), height: 20)
    )
  }
}

@Suite struct ComponentResolverTests {
  @Test func nestedComponentPreservesComponentBoundary() {
    let root = ComponentResolver.resolve(AnyComponent(ParentComponent()))

    #expect(root.id == .root)

    guard case let .component(_, rootBody) = root.content else {
      Issue.record("Expected root component wrapper")
      return
    }
    guard case let .layout(_, children) = rootBody.content else {
      Issue.record("Expected root body to resolve as a layout")
      return
    }

    #expect(children.count == 2)
    #expect(children[0].id != children[1].id)

    guard case .primitive = children[0].content else {
      Issue.record("Expected header child to remain a primitive leaf")
      return
    }

    guard case let .component(_, childLeaf) = children[1].content else {
      Issue.record("Expected nested child component wrapper to survive resolution")
      return
    }
    guard case .primitive = childLeaf.content else {
      Issue.record("Expected nested child component body to remain a primitive leaf")
      return
    }
  }

}

@MainActor
@Suite struct ComponentRendererTests {
  @Test func observableChangeRefreshesRenderTree() async {
    let model = ParagraphModel()
    let runtime = RenderRuntime()
    let renderer = ComponentRenderer(
      root: AnyComponent(
        ReactiveParagraphsComponent(model: model),
        isEquivalent: { lhs, rhs in lhs.model === rhs.model }
      )
    )

    let initialRevision = renderer.revision
    #expect(
      runtime.layout(
        root: renderer.resolvedRoot,
        proposal: ProposedSize(width: 200, height: nil)
      ).leaves().count == 2
    )

    model.count = 4
    for _ in 0 ..< 10 {
      if renderer.revision > initialRevision { break }
      await Task.yield()
    }

    #expect(renderer.revision > initialRevision)
    #expect(
      runtime.layout(
        root: renderer.resolvedRoot,
        proposal: ProposedSize(width: 200, height: nil)
      ).leaves().count == 4
    )
  }

  @Test func observableChangeRefreshesOnlyDirtyComponentPath() async {
    let model = PairModel()
    let counter = RenderCounter()
    let renderer = ComponentRenderer(
      root: AnyComponent(
        CountingRootComponent(model: model, counter: counter),
        isEquivalent: { lhs, rhs in
          lhs.model === rhs.model && lhs.counter === rhs.counter
        }
      )
    )

    let rootCount = counter.root
    let leftCount = counter.left
    let rightCount = counter.right
    let initialRevision = renderer.revision

    model.left = 5

    for _ in 0 ..< 10 {
      if renderer.revision > initialRevision { break }
      await Task.yield()
    }

    #expect(renderer.revision > initialRevision)
    #expect(counter.root == rootCount)
    #expect(counter.left == leftCount + 1)
    #expect(counter.right == rightCount)
  }
}
