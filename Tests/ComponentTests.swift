import CoreGraphics
import IdentifiedCollections
import Observation
import Testing
@testable import WuhuUI

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

  @Test func markdownComponentPreservesQuoteAndNestedListStructure() {
    let source = """
    # Title

    > quoted intro
    >
    > - nested one
    > - nested two
    """

    let root = ComponentResolver.resolve(AnyComponent(MarkdownDocumentComponent(source: source)))

    guard case let .component(_, documentNode) = root.content else {
      Issue.record("Expected markdown root wrapper")
      return
    }
    guard case let .layout(_, blocks) = documentNode.content else {
      Issue.record("Expected markdown document body to be a layout")
      return
    }

    #expect(blocks.count == 2)

    // Each block is now a component; unwrap it
    guard case let .component(_, blockQuoteInner) = blocks[1].content else {
      Issue.record("Expected block quote to resolve as a component")
      return
    }
    guard case let .layout(_, quoteChildren) = blockQuoteInner.content else {
      Issue.record("Expected block quote body to be a layout")
      return
    }
    #expect(quoteChildren.count == 2)

    guard case let .layout(_, barChildren) = quoteChildren[0].content else {
      Issue.record("Expected block quote bar wrapper")
      return
    }
    #expect(barChildren.count == 1)

    guard case let .layout(_, insetChildren) = quoteChildren[1].content else {
      Issue.record("Expected block quote content inset")
      return
    }
    #expect(insetChildren.count == 1)

    guard case let .layout(_, quoteContentChildren) = insetChildren[0].content else {
      Issue.record("Expected block quote content stack")
      return
    }
    #expect(quoteContentChildren.count == 2)

    // Nested list items are now components too; unwrap the list component first
    guard case let .component(_, listInner) = quoteContentChildren[1].content else {
      Issue.record("Expected nested quote list to be a component")
      return
    }
    guard case let .layout(_, quoteListChildren) = listInner.content else {
      Issue.record("Expected nested quote list body to be a layout")
      return
    }
    #expect(quoteListChildren.count == 2)
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
        proposal: ProposedSize(width: 200, height: nil),
        viewport: CGRect(x: 0, y: 0, width: 200, height: 400)
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
        proposal: ProposedSize(width: 200, height: nil),
        viewport: CGRect(x: 0, y: 0, width: 200, height: 400)
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
