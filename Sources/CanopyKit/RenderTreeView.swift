import SwiftUI

public struct RenderTreeView: View {
  @Environment(\.autoScrollWhenHeightChanges) private var autoScrollWhenHeightChanges
  @State private var lastObservedContentHeight: CGFloat = 0
  @State private var runtime = RenderRuntime()

  let root: ResolvedNode
  let revision: Int

  public init(root: ResolvedNode, revision: Int = 0) {
    self.root = root
    self.revision = revision
  }

  public var body: some View {
    let _ = revision

    GeometryReader { outerGeo in
      let width = outerGeo.size.width
      let height = contentHeight(width: width)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            GeometryReader { innerGeo in
              let innerFrame = innerGeo.frame(in: .named("scroll"))
              let viewport = CGRect(
                x: 0,
                y: -innerFrame.origin.y,
                width: outerGeo.size.width,
                height: outerGeo.size.height
              )

              if let visibleTree = visibleTree(width: width, viewport: viewport) {
                VisibleRenderNodeView(nodeView: visibleTree, positionsAbsolutely: true)
              }
            }
            .frame(height: height)

            Color.clear
              .frame(height: 1)
              .id(BottomSentinel.id)
          }
        }
        .task(id: height) {
          handleContentHeightChange(height, proxy: proxy)
        }
        .coordinateSpace(name: "scroll")
      }
    }
  }

  private func contentHeight(width: CGFloat) -> CGFloat {
    guard width > 0 else { return 0 }
    return runtime.sizeThatFits(
      root: root,
      proposal: ProposedSize(width: width, height: nil)
    ).height
  }

  private func visibleTree(width: CGFloat, viewport: CGRect) -> ResolvedRenderNodeView? {
    guard width > 0 else { return nil }
    return runtime.visibleView(
      root: root,
      proposal: ProposedSize(width: width, height: nil),
      viewport: viewport
    )
  }

  @MainActor
  private func handleContentHeightChange(_ height: CGFloat, proxy: ScrollViewProxy) {
    guard autoScrollWhenHeightChanges else {
      lastObservedContentHeight = height
      return
    }

    guard lastObservedContentHeight != 0 else {
      lastObservedContentHeight = height
      return
    }

    if height > lastObservedContentHeight {
      proxy.scrollTo(BottomSentinel.id, anchor: .bottom)
    }

    lastObservedContentHeight = height
  }
}

private enum BottomSentinel {
  static let id = "wuhu.renderTree.bottomSentinel"
}

public extension EnvironmentValues {
  @Entry var autoScrollWhenHeightChanges: Bool = false
}

public extension View {
  func autoScrollWhenHeightChanges(_ enabled: Bool = true) -> some View {
    environment(\.autoScrollWhenHeightChanges, enabled)
  }
}

private struct VisibleRenderNodeView: View {
  let nodeView: ResolvedRenderNodeView
  var positionsAbsolutely = false

  var body: some View {
    let node = nodeView.node
    let width = nodeView.frame.width
    let height = nodeView.frame.height

    let base = nodeContent(node)
      .frame(width: width, height: height, alignment: .topLeading)

    let decorated: AnyView = if let viewModifier = node.values[ViewModifierKey.self] {
      viewModifier.apply(to: base)
    } else {
      AnyView(base)
    }

    decorated
      .offset(
        x: positionsAbsolutely ? nodeView.frame.minX : 0,
        y: positionsAbsolutely ? nodeView.frame.minY : 0
      )
  }

  @ViewBuilder
  private func nodeContent(_ node: ResolvedRenderNode) -> some View {
    switch node.content {
    case let .primitive(_, commitment):
      switch commitment {
      case let .customView(representable, storedCache):
        ViewRepresentableCanvas(representable: representable, storedCache: storedCache)
      case nil:
        Color.clear
      }

    case .component, .layout:
      GeometryReader { _ in
        ForEach(nodeView.children, id: \.node.id) { childView in
          VisibleRenderNodeView(nodeView: childView)
            .offset(
              x: childView.frame.minX - nodeView.frame.minX,
              y: childView.frame.minY - nodeView.frame.minY
            )
        }
      }
    }
  }
}

private struct ViewRepresentableCanvas: View {
  let representable: AnyViewRepresentable
  let storedCache: Any?

  var body: some View {
    var cache = storedCache ?? representable.makeCache()
    representable.makeView(cache: &cache)
  }
}
