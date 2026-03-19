import CoreGraphics
import Observation
import Testing
@testable import WuhuUI

// MARK: - Test Components

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

struct CountingRootComponent: Component {
  let model: PairModel
  let counter: RenderCounter

  func body() -> ComponentBody {
    counter.root += 1

    return .layoutNode(
      key: "root",
      AnyLayout(VStackLayout(spacing: 4)),
      children: [
        .componentNode(
          key: "left",
          AnyComponent(
            CountingLeafComponent(side: .left, model: model, counter: counter),
            isEquivalent: { lhs, rhs in
              lhs.side == rhs.side && lhs.model === rhs.model && lhs.counter === rhs.counter
            }
          )
        ),
        .componentNode(
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

  func body() -> ComponentBody {
    let value: Int

    switch side {
    case .left:
      counter.left += 1
      value = model.left

    case .right:
      counter.right += 1
      value = model.right
    }

    return .drawingNode(
      key: "leaf",
      fixedDrawing(width: CGFloat(80 + value), height: 20)
    )
  }
}

// MARK: - Component Resolver Tests

@Suite struct ComponentResolverTests {
  @Test func nestedComponentResolvesToPathBackedTree() {
    let root = ComponentResolver.resolve(AnyComponent(ParentComponent()))

    #expect(root.id == ["root"])
    #expect(root.children.count == 2)
    #expect(root.children[0].id == ["root", "header"])
    #expect(root.children[1].id == ["root", "child", "body"])
  }

  @Test func markdownComponentPreservesQuoteAndNestedListStructure() {
    let source = """
    # Title

    > quoted intro
    >
    > - nested one
    > - nested two
    """

    let root = ComponentResolver.resolve(AnyComponent(MarkdownDocumentComponent(source: source)))

    #expect(root.id == ["document"])

    let blockQuote = root.children.first { $0.id == ["document", "block-1"] }
    #expect(blockQuote != nil)

    let nestedList = blockQuote?.children.first {
      $0.id == ["document", "block-1", "block-1-marker"]
    }
    #expect(nestedList != nil)

    let quoteContent = blockQuote?.children.first {
      $0.id == ["document", "block-1", "block-1-content"]
    }
    #expect(quoteContent != nil)
    #expect(quoteContent?.children.count == 2)

    let quoteList = quoteContent?.children.last
    #expect(quoteList?.children.count == 2)
  }
}

// MARK: - Component Renderer Tests

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
