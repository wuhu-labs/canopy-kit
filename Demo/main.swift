import AppKit
import WuhuUI

// MARK: - Build a boring long tree

@MainActor
func buildTree() -> RenderNode {
    var children: [RenderNode] = []

    for i in 0..<100 {
        // Alternating: text paragraph, then a colored rect separator.

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

// MARK: - Document View (inside scroll view)

/// The document view is the scroll view's content. It overrides
/// `prepareContent(in:)` to synchronously update layers as the
/// user scrolls — no async notification, no white flash.
@MainActor
final class DocumentView: NSView {
    let root: RenderNode
    let renderer: Renderer
    private var needsInitialLayout = true

    init(root: RenderNode) {
        self.root = root
        let backing = CALayer()
        backing.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        backing.isGeometryFlipped = true
        self.renderer = Renderer(container: backing)
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer = backing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    /// Called synchronously by AppKit's responsive scrolling system
    /// when the visible region changes (scroll or overdraw).
    override func prepareContent(in rect: NSRect) {
        super.prepareContent(in: rect)
        updateRendering(visibleRect: rect)
    }

    override func layout() {
        super.layout()
        guard let scrollView = enclosingScrollView else { return }
        let width = scrollView.contentView.bounds.width
        guard width > 0 else { return }

        // Re-measure on width change.
        root.layoutPass(width: width)
        let contentSize = root.cachedSize ?? .zero
        frame = CGRect(origin: frame.origin, size: CGSize(width: width, height: contentSize.height))
        renderer.container.frame = CGRect(origin: .zero, size: frame.size)
        renderer.container.bounds = CGRect(origin: .zero, size: frame.size)

        updateRendering(visibleRect: scrollView.contentView.bounds)
    }

    private func updateRendering(visibleRect: CGRect) {
        renderer.render(root: root, visibleRect: visibleRect)
    }
}

// MARK: - App Setup

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = buildTree()

        let docView = DocumentView(root: root)

        let scrollView = NSScrollView()
        scrollView.documentView = docView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 600, height: 700),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.title = "WuhuUI — Render Tree Demo"
        window.makeKeyAndOrderFront(nil)

        print("✓ 100 paragraphs + separators in a scroll view. Resize the window.")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
