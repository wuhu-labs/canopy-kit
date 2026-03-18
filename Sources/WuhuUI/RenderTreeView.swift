import SwiftUI

public struct RenderTreeView: View {
  @Environment(\.autoScrollWhenHeightChanges) private var autoScrollWhenHeightChanges
  @State private var lastObservedContentHeight: CGFloat = 0

  let root: RenderNode
  let revision: Int

  public init(root: RenderNode, revision: Int = 0) {
    self.root = root
    self.revision = revision
  }

  public var body: some View {
    let _ = revision

    GeometryReader { outerGeo in
      let height = contentHeight(width: outerGeo.size.width)

      ScrollViewReader { proxy in
        ScrollView {
          VStack(spacing: 0) {
            GeometryReader { innerGeo in
              let innerFrame = innerGeo.frame(in: .named("scroll"))
              let visibleRect = CGRect(
                x: 0,
                y: -innerFrame.origin.y,
                width: outerGeo.size.width,
                height: outerGeo.size.height
              )

              ForEach(visibleNodes(visibleRect: visibleRect), id: \.id) { entry in
                DrawingCanvas(node: entry.node)
                  .frame(width: entry.frame.width, height: entry.frame.height)
                  .offset(x: entry.frame.origin.x, y: entry.frame.origin.y)
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
    root.layoutPass(width: width)
    return root.cachedSize?.height ?? 0
  }

  private func visibleNodes(visibleRect: CGRect) -> [VisibleEntry] {
    let width = visibleRect.width
    guard width > 0 else { return [] }
    root.layoutPass(width: width)
    root.assignFrames(origin: .zero)

    let leaves = root.visibleLeaves(in: visibleRect)
    return leaves.map { node in
      VisibleEntry(node: node, frame: node.frame)
    }
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

private struct AutoScrollWhenHeightChangesKey: EnvironmentKey {
  static let defaultValue = false
}

public extension EnvironmentValues {
  var autoScrollWhenHeightChanges: Bool {
    get { self[AutoScrollWhenHeightChangesKey.self] }
    set { self[AutoScrollWhenHeightChangesKey.self] = newValue }
  }
}

public extension View {
  func autoScrollWhenHeightChanges(_ enabled: Bool = true) -> some View {
    environment(\.autoScrollWhenHeightChanges, enabled)
  }
}

private struct VisibleEntry: Identifiable {
  var id: ObjectIdentifier {
    ObjectIdentifier(node)
  }

  let node: RenderNode
  let frame: CGRect
}

private struct DrawingCanvas: View {
  let node: RenderNode

  var body: some View {
    Canvas { context, size in
      guard case var .leaf(drawing) = node.content else { return }
      context.withCGContext { cgContext in
        drawing.draw(in: cgContext, bounds: CGRect(origin: .zero, size: size))
      }
      node.content = .leaf(drawing)
    }
  }
}
