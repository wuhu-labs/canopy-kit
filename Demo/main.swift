import Foundation
import AppKit

// MARK: - Reactive Primitive

/// Minimal signal. Stores a value, notifies one observer on change.
final class Signal<T: Equatable>: @unchecked Sendable {
    private var _value: T
    var onChange: (() -> Void)?

    init(_ value: T) { _value = value }

    var value: T {
        get { _value }
        set {
            guard _value != newValue else { return }
            _value = newValue
            onChange?()
        }
    }
}

// MARK: - Layout Primitives

struct ProposedSize {
    var width: CGFloat
    var height: CGFloat?
}

struct LayoutResult {
    var size: CGSize
    var childFrames: [CGRect] // one per child, in local coordinates
}

protocol DocLayout {
    func layout(children: [CGSize], proposal: ProposedSize) -> LayoutResult
}

struct VStackLayout: DocLayout {
    var spacing: CGFloat = 0

    func layout(children: [CGSize], proposal: ProposedSize) -> LayoutResult {
        var y: CGFloat = 0
        var frames: [CGRect] = []
        var maxWidth: CGFloat = 0

        for (i, childSize) in children.enumerated() {
            if i > 0 { y += spacing }
            frames.append(CGRect(x: 0, y: y, width: childSize.width, height: childSize.height))
            y += childSize.height
            maxWidth = max(maxWidth, childSize.width)
        }

        return LayoutResult(
            size: CGSize(width: proposal.width, height: y),
            childFrames: frames
        )
    }
}

// MARK: - Layout Tree Node

/// A node in the layout tree. Either a container (has layout + children)
/// or a leaf (has content that knows how to measure and draw).
final class LayoutNode {
    let id: String
    var layout: (any DocLayout)?
    var children: [LayoutNode] = []
    var leaf: LeafContent?

    // Layout cache
    var cachedProposal: ProposedSize?
    var cachedResult: LayoutResult?
    var cachedSize: CGSize?

    // Frame in document coordinates, set during layout pass
    var frame: CGRect = .zero

    init(id: String, layout: (any DocLayout)? = nil, leaf: LeafContent? = nil) {
        self.id = id
        self.layout = layout
        self.leaf = leaf
    }

    func invalidate() {
        cachedResult = nil
        cachedSize = nil
        cachedProposal = nil
    }
}

// MARK: - Leaf Content

/// What a leaf node contains: how to measure it, how to draw it.
protocol LeafContent {
    func sizeThatFits(proposal: ProposedSize) -> CGSize
    func draw(in ctx: CGContext, bounds: CGRect)
}

/// A colored rectangle with observable size and color.
final class ColorRect: LeafContent {
    let color: Signal<NSColor>
    let height: Signal<CGFloat>

    init(color: NSColor, height: CGFloat) {
        self.color = Signal(color)
        self.height = Signal(height)
    }

    func sizeThatFits(proposal: ProposedSize) -> CGSize {
        CGSize(width: proposal.width, height: height.value)
    }

    func draw(in ctx: CGContext, bounds: CGRect) {
        ctx.setFillColor(color.value.cgColor)
        ctx.fill(bounds)
    }
}

// MARK: - Layout Engine

/// Walks the tree, computes sizes bottom-up, assigns frames top-down.
enum LayoutEngine {
    /// Measure a node given a size proposal. Returns the node's size.
    static func measure(_ node: LayoutNode, proposal: ProposedSize) -> CGSize {
        if let leaf = node.leaf {
            let size = leaf.sizeThatFits(proposal: proposal)
            node.cachedSize = size
            return size
        }

        guard let layout = node.layout else { return .zero }

        // Measure children
        let childSizes = node.children.map { measure($0, proposal: proposal) }

        // Run layout
        let result = layout.layout(children: childSizes, proposal: proposal)
        node.cachedResult = result
        node.cachedSize = result.size
        return result.size
    }

    /// Assign frames in document coordinates. Call after measure.
    static func assignFrames(_ node: LayoutNode, origin: CGPoint) {
        node.frame = CGRect(origin: origin, size: node.cachedSize ?? .zero)

        guard let result = node.cachedResult else { return }

        for (i, child) in node.children.enumerated() {
            let childFrame = result.childFrames[i]
            let childOrigin = CGPoint(
                x: origin.x + childFrame.origin.x,
                y: origin.y + childFrame.origin.y
            )
            assignFrames(child, origin: childOrigin)
        }
    }

    /// Full layout pass.
    static func layout(_ root: LayoutNode, viewportWidth: CGFloat) {
        let proposal = ProposedSize(width: viewportWidth)
        _ = measure(root, proposal: proposal)
        assignFrames(root, origin: .zero)
    }

    /// Collect all leaf nodes (the things we actually draw).
    static func leaves(_ node: LayoutNode) -> [LayoutNode] {
        if node.leaf != nil { return [node] }
        return node.children.flatMap { leaves($0) }
    }
}

// MARK: - Renderer

/// Manages CALayers for visible leaf nodes. Owns the layer tree.
final class Renderer {
    let container: CALayer
    private var activeLayers: [String: CALayer] = [:]

    init(container: CALayer) {
        self.container = container
    }

    func render(root: LayoutNode, visibleRect: CGRect) {
        let allLeaves = LayoutEngine.leaves(root)

        // Determine visible set
        let visible = allLeaves.filter { $0.frame.intersects(visibleRect) }
        let visibleIDs = Set(visible.map(\.id))

        // Remove layers for leaves no longer visible
        for (id, layer) in activeLayers where !visibleIDs.contains(id) {
            layer.removeFromSuperlayer()
            activeLayers.removeValue(forKey: id)
        }

        // Add/update layers for visible leaves
        for node in visible {
            let layer: CALayer
            if let existing = activeLayers[node.id] {
                layer = existing
            } else {
                layer = DrawLayer()
                container.addSublayer(layer)
                activeLayers[node.id] = layer
            }

            // Update frame
            // Flip Y: CALayer origin is bottom-left, our layout is top-left
            let flippedY = container.bounds.height - node.frame.maxY
            layer.frame = CGRect(
                x: node.frame.origin.x,
                y: flippedY,
                width: node.frame.width,
                height: node.frame.height
            )

            // Attach content for drawing
            (layer as? DrawLayer)?.leafContent = node.leaf
            layer.setNeedsDisplay()
        }
    }
}

/// A CALayer that draws leaf content via Core Graphics.
final class DrawLayer: CALayer {
    var leafContent: LeafContent?

    override func draw(in ctx: CGContext) {
        guard let content = leafContent else { return }
        let bounds = CGRect(origin: .zero, size: self.bounds.size)
        content.draw(in: ctx, bounds: bounds)
    }
}

// MARK: - Document View (NSView host)

final class DocumentView: NSView {
    let root: LayoutNode
    let renderer: Renderer

    init(root: LayoutNode) {
        self.root = root
        let backing = CALayer()
        self.renderer = Renderer(container: backing)
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer = backing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    func relayout() {
        let width = bounds.width
        guard width > 0 else { return }
        LayoutEngine.layout(root, viewportWidth: width)
        renderer.container.bounds = self.bounds
        // For this demo, everything is visible (no scrolling)
        renderer.render(root: root, visibleRect: bounds)
    }

    override func layout() {
        super.layout()
        relayout()
    }
}

// MARK: - App Setup

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var docView: DocumentView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build model
        let rect1 = ColorRect(color: .systemRed, height: 80)
        let rect2 = ColorRect(color: .systemBlue, height: 60)
        let rect3 = ColorRect(color: .systemGreen, height: 100)

        // Build layout tree
        let root = LayoutNode(id: "root", layout: VStackLayout(spacing: 8))
        root.children = [
            LayoutNode(id: "r1", leaf: rect1),
            LayoutNode(id: "r2", leaf: rect2),
            LayoutNode(id: "r3", leaf: rect3),
        ]

        // Wire reactivity: any signal change → relayout
        let scheduleRelayout = { [weak self] in
            DispatchQueue.main.async { self?.docView.relayout() }
        }
        rect1.color.onChange = scheduleRelayout
        rect2.height.onChange = scheduleRelayout
        rect3.color.onChange = scheduleRelayout

        // Create window
        docView = DocumentView(root: root)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        contentView.wantsLayer = true

        docView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(docView)
        NSLayoutConstraint.activate([
            docView.topAnchor.constraint(equalTo: contentView.topAnchor),
            docView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            docView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            docView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        window = NSWindow(
            contentRect: NSRect(x: 200, y: 200, width: 400, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        window.title = "DocEngine Demo"
        window.makeKeyAndOrderFront(nil)

        // Controls: toggle color and size after delays
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            print("→ rect1: red → orange"); fflush(stdout)
            rect1.color.value = .systemOrange
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            print("→ rect2: height 60 → 150"); fflush(stdout)
            rect2.height.value = 150
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            print("→ rect3: green → purple"); fflush(stdout)
            rect3.color.value = .systemPurple
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            print("→ rect2: height 150 → 40"); fflush(stdout)
            rect2.height.value = 40
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) {
            print("✓ demo complete"); fflush(stdout)
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
