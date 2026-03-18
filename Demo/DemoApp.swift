import SwiftUI
import WuhuUI

// MARK: - Build a boring long tree

func buildTree() -> RenderNode {
  var children: [RenderNode] = []

  for i in 0 ..< 100 {
    let text = "[\(i)] Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
      + "Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
      + "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris."

    let textNode = RenderNode.leaf(AnyDrawing(TextDrawing(text, fontSize: 14)))

    let hue = CGFloat(i) / 100.0
    let color = CGColor(
      red: hue,
      green: 0.4,
      blue: 1.0 - hue,
      alpha: 1
    )
    let separator = RenderNode.leaf(AnyDrawing(RectDrawing(color: color, height: 4)))

    children.append(textNode)
    children.append(separator)
  }

  return RenderNode.container(AnyLayout(VStackLayout(spacing: 8)), children)
}

// MARK: - Render Tree View

struct RenderTreeView: View {
  let root: RenderNode

  var body: some View {
    GeometryReader { outerGeo in
      ScrollView {
        GeometryReader { innerGeo in
          let innerFrame = innerGeo.frame(in: .named("scroll"))
          let visibleRect = CGRect(x: 0, y: -innerFrame.origin.y, width: outerGeo.size.width, height: outerGeo.size.height)

          // Visible nodes, each positioned absolutely.
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

struct VisibleEntry: Identifiable {
  var id: ObjectIdentifier {
    ObjectIdentifier(node)
  }

  let node: RenderNode
  let frame: CGRect
}

// MARK: - Canvas that draws via AnyDrawing

struct DrawingCanvas: View {
  let node: RenderNode

  var body: some View {
    Canvas { context, size in
      guard case var .leaf(drawing) = node.content else { return }
      context.withCGContext { cgContext in
        drawing.draw(in: cgContext, bounds: CGRect(origin: .zero, size: size))
      }
      node.content = .leaf(drawing) // write back cache
    }
  }
}

// MARK: - App

@main
struct WuhuUIDemoApp: App {
  let root = buildTree()

  var body: some Scene {
    WindowGroup {
      RenderTreeView(root: root)
        .frame(minWidth: 400, minHeight: 400)
    }
  }
}
