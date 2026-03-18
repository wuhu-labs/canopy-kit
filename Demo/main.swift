import Foundation
import AppKit
import Observation
import WuhuUI

// Debug logger — GUI apps may not flush stdout.
@MainActor
func log(_ msg: String) {
    print(msg)
    fflush(stdout)
}

// MARK: - App Model

/// The app's state. Plain @Observable — no signals, no framework coupling.
@Observable
@MainActor
final class DocModel {
    var items: [ItemModel] = [
        ItemModel(color: .red, height: 80),
        ItemModel(color: .blue, height: 60),
        ItemModel(color: .green, height: 100),
    ]
}

@Observable
@MainActor
final class ItemModel {
    var color: PlatformColor
    var height: CGFloat

    init(color: PlatformColor, height: CGFloat) {
        self.color = color
        self.height = height
    }
}

// MARK: - Components

/// Root component: reads the model, produces a VStack of color fills.
struct DocRoot: Component, Equatable {
    // Components are value types and equatable.
    // They capture what they need from the model as props.
    // For this demo, the root reads the model directly.
    let model: ObjectIdentifier  // identity-based equality for the observable

    @MainActor static var _model: DocModel?

    @MainActor func body() -> ContainerElement {
        let model = Self._model!
        let children = model.items.enumerated().map { i, item in
            AnyElement(ColorFillElement(color: item.color, height: item.height))
        }
        return ContainerElement(
            layout: AnyLayout(VStackLayout(spacing: 8)),
            children: children
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.model == rhs.model
    }
}

// MARK: - Document View

@MainActor
final class DocumentView: NSView {
    let reconciler = Reconciler()
    let renderer: Renderer
    let model: DocModel
    private var pendingDirtyPaths: Set<NodePath> = []
    private var updateScheduled = false

    init(model: DocModel) {
        self.model = model
        let backing = CALayer()
        self.renderer = Renderer(container: backing)
        super.init(frame: .zero)
        self.wantsLayer = true
        self.layer = backing

        // Set up the component's model reference.
        DocRoot._model = model

        // Build the initial tree.
        let rootComponent = DocRoot(model: ObjectIdentifier(model))
        let rootElement = AnyElement(ComponentElement(rootComponent))
        reconciler.mount(element: rootElement)

        // Wire observation: when a node becomes dirty, schedule an update.
        reconciler.onDirty = { @Sendable [weak self] path in
            Task { @MainActor in
                self?.scheduleDirty(path)
            }
        }

        // Wire lifecycle callbacks.
        renderer.onAppear = { path in
            log("  appear: \(path)")
        }
        renderer.onDisappear = { path in
            log("  disappear: \(path)")
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    private func scheduleDirty(_ path: NodePath) {
        pendingDirtyPaths.insert(path)
        guard !updateScheduled else { return }
        updateScheduled = true
        // Batch: collect all dirty paths in this runloop tick, then process.
        DispatchQueue.main.async { [weak self] in
            self?.processDirtyPaths()
        }
    }

    private func processDirtyPaths() {
        updateScheduled = false
        let paths = pendingDirtyPaths
        pendingDirtyPaths = []

        guard !paths.isEmpty else { return }

        log("⟳ reconcile: \(paths.map(\.description).sorted())")

        // 1. Reconcile dirty nodes.
        reconciler.transaction(dirtyPaths: paths)

        // 2. Layout.
        relayout()
    }

    func relayout() {
        let width = bounds.width
        guard width > 0, let root = reconciler.root else { return }

        // Layout pass.
        LayoutEngine.layout(root, viewportWidth: width)

        // Update container bounds.
        renderer.container.bounds = self.bounds

        // Render (for now, everything is visible — no scrolling).
        renderer.render(root: root, visibleRect: bounds)
    }

    override func layout() {
        super.layout()
        relayout()
    }

    // MARK: - Hit Testing (wired outside the framework)

    override func mouseDown(with event: NSEvent) {
        guard let root = reconciler.root else { return }

        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)

        // Our layout is top-left origin, NSView with isFlipped=true matches.
        let point = CGPoint(x: locationInView.x, y: locationInView.y)

        if let hit = HitTest.test(point: point, root: root) {
            log("🎯 hit: \(hit.path) at local(\(Int(hit.localPoint.x)), \(Int(hit.localPoint.y)))")

            // Demonstrate the hit path (root to leaf).
            let path = HitTest.hitPath(point: point, root: root)
            log("   path: \(path.map(\.path.description).joined(separator: " → "))")
        } else {
            log("🎯 miss")
        }
    }
}

// MARK: - Preference Demo: collect all leaf frames

/// A preference key that collects all leaf frames in tree order.
/// Demonstrates the "mirrored layout tree via preference" idea.
struct LeafFrameEntry: Equatable {
    var path: NodePath
    var frame: CGRect
}

struct LeafFrameKey: PreferenceKey {
    typealias Value = [LeafFrameEntry]
    static var defaultValue: [LeafFrameEntry] { [] }
    static func reduce(value: inout [LeafFrameEntry], nextValue: [LeafFrameEntry]) {
        value.append(contentsOf: nextValue)
    }
}

@MainActor
func demoPreferences(root: Node) {
    let frames: [LeafFrameEntry] = PreferenceEngine.collect(
        key: LeafFrameKey.self,
        from: root
    ) { node -> [LeafFrameEntry]? in
        // Only leaves report.
        guard node.children.isEmpty else { return nil }
        return [LeafFrameEntry(path: node.path, frame: node.frame)]
    }

    log("📐 leaf frames (via preference):")
    for entry in frames {
        log("   \(entry.path): \(Int(entry.frame.origin.x)),\(Int(entry.frame.origin.y)) \(Int(entry.frame.width))×\(Int(entry.frame.height))")
    }
}

// MARK: - App Setup

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var docView: DocumentView!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = DocModel()

        docView = DocumentView(model: model)

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
        window.title = "WuhuUI Demo"
        window.makeKeyAndOrderFront(nil)

        // Reactive updates: mutate the model, framework handles the rest.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            log("\n→ item[0]: red → orange")
            model.items[0].color = .orange
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            log("\n→ item[1]: height 60 → 150")
            model.items[1].height = 150
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            log("\n→ item[2]: green → purple")
            model.items[2].color = .purple
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            log("\n→ item[1]: height 150 → 40")
            model.items[1].height = 40
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) {
            log("\n→ add new item (gray, height 50)")
            model.items.append(ItemModel(color: .gray, height: 50))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
            // Demonstrate preference collection.
            if let root = self.docView.reconciler.root {
                demoPreferences(root: root)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
            log("\n✓ demo complete — click anywhere to hit-test, or close the window")
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
