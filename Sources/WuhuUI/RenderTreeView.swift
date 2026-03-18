import SwiftUI

public struct RenderTreeView: View {
  let root: RenderNode
  let revision: Int

  public init(root: RenderNode, revision: Int = 0) {
    self.root = root
    self.revision = revision
  }

  public var body: some View {
    let _ = revision

    GeometryReader { outerGeo in
      ScrollView {
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
        .frame(height: contentHeight(width: outerGeo.size.width))
      }
      .coordinateSpace(name: "scroll")
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
