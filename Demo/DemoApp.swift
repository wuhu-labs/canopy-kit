import SwiftUI
import WuhuUI

// MARK: - Build a boring long tree

func buildTree() -> RenderNode {
    var children: [RenderNode] = []

    for i in 0..<100 {
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
    @State private var viewportHeight: CGFloat = 0
    @State private var scrollOffset: CGFloat = 0
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        GeometryReader { outerGeo in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Invisible spacer sized to full content height.
                    GeometryReader { innerGeo in
                        Color.clear
                            .onChange(of: innerGeo.frame(in: .named("scroll")), initial: true) {
                                _, newFrame in
                                scrollOffset = -newFrame.origin.y
                            }
                    }
                    .frame(height: contentHeight(width: outerGeo.size.width))

                    // Visible nodes, each positioned absolutely.
                    ForEach(visibleNodes(width: outerGeo.size.width), id: \.id) { entry in
                        DrawingCanvas(node: entry.node)
                            .frame(width: entry.frame.width, height: entry.frame.height)
                            .offset(x: entry.frame.origin.x, y: entry.frame.origin.y)
                    }
                }
            }
            .coordinateSpace(name: "scroll")
            .onChange(of: outerGeo.size, initial: true) { _, newSize in
                viewportHeight = newSize.height
                viewportWidth = newSize.width
            }
        }
    }

    private func contentHeight(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        root.layoutPass(width: width)
        return root.cachedSize?.height ?? 0
    }

    private func visibleNodes(width: CGFloat) -> [VisibleEntry] {
        guard width > 0 else { return [] }
        root.layoutPass(width: width)
        root.assignFrames(origin: .zero)

        let visibleRect = CGRect(
            x: 0,
            y: scrollOffset,
            width: width,
            height: viewportHeight
        )
        let leaves = root.visibleLeaves(in: visibleRect)
        return leaves.map { node in
            VisibleEntry(id: ObjectIdentifier(node), node: node, frame: node.frame)
        }
    }
}

struct VisibleEntry: Identifiable {
    let id: ObjectIdentifier
    let node: RenderNode
    let frame: CGRect
}

// MARK: - Canvas that draws via AnyDrawing

struct DrawingCanvas: View {
    let node: RenderNode

    var body: some View {
        Canvas { context, size in
            guard case .leaf(var drawing) = node.content else { return }
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
