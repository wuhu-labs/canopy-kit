@testable import CanopyKit
import CoreGraphics
import IdentifiedCollections
import Observation
import Testing

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
            CountingLeafComponent(side: .left, model: model, counter: counter)
          )
        ),
        .component(
          key: "right",
          AnyComponent(
            CountingLeafComponent(side: .right, model: model, counter: counter)
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

@MainActor
@Suite struct ComponentRendererTests {
  @Test func observableChangeRefreshesRenderTree() async {
    let model = ParagraphModel()
    let runtime = RenderRuntime()
    let renderer = ComponentRenderer(
      root: AnyComponent(
        ReactiveParagraphsComponent(model: model)
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
        CountingRootComponent(model: model, counter: counter)
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
