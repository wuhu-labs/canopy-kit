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

@MainActor
final class DocumentView: NSView {
    let root: RenderNode
    let renderer: Renderer

    init(root: RenderNode) {
        self.root = root
        let backing = CALayer()
        backing.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        self.renderer = Renderer(container: backing)
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer = backing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func relayout(width: CGFloat, visibleRect: CGRect) {
        root.layoutPass(width: width)
        let contentSize = root.cachedSize ?? .zero

        // Resize ourselves to the full content height so the scroll view
        // knows the document size.
        frame = CGRect(origin: frame.origin, size: CGSize(width: width, height: contentSize.height))

        renderer.container.bounds = CGRect(origin: .zero, size: frame.size)
        renderer.container.frame = CGRect(origin: .zero, size: frame.size)
        renderer.render(root: root, visibleRect: visibleRect)
    }
}

// MARK: - Scroll view wrapper

@MainActor
final class ScrollDocumentView: NSView {
    let scrollView: NSScrollView
    let docView: DocumentView

    init(root: RenderNode) {
        self.docView = DocumentView(root: root)
        self.scrollView = NSScrollView()
        super.init(frame: .zero)

        scrollView.documentView = docView
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.drawsBackground = false

        addSubview(scrollView)

        // Observe scroll and resize.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollOrResize),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(scrollOrResize),
            name: NSView.frameDidChangeNotification,
            object: scrollView
        )
        scrollView.postsFrameChangedNotifications = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        updateLayout()
    }

    @objc private func scrollOrResize() {
        updateLayout()
    }

    private func updateLayout() {
        let width = scrollView.contentView.bounds.width
        guard width > 0 else { return }
        let visibleRect = scrollView.contentView.bounds
        docView.relayout(width: width, visibleRect: visibleRect)
    }
}

// MARK: - App Setup

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let root = buildTree()
        let scrollDoc = ScrollDocumentView(root: root)

        scrollDoc.translatesAutoresizingMaskIntoConstraints = false

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 700))
        contentView.addSubview(scrollDoc)
        NSLayoutConstraint.activate([
            scrollDoc.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollDoc.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollDoc.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollDoc.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
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
