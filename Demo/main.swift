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
        ItemModel(id: "a", color: .red, height: 80),
        ItemModel(id: "b", color: .blue, height: 60),
        ItemModel(id: "c", color: .green, height: 100),
    ]
}

@Observable
@MainActor
final class ItemModel {
    let id: String
    var color: PlatformColor
    var height: CGFloat

    init(id: String, color: PlatformColor, height: CGFloat) {
        self.id = id
        self.color = color
        self.height = height
    }
}

// MARK: - Components

/// Root component: reads model.items to produce Item components.
/// Only observes the items array — NOT individual item properties.
struct DocRoot: Component, Equatable {
    let modelID: ObjectIdentifier

    @MainActor static var _model: DocModel?

    @MainActor func body() -> ContainerElement {
        let model = Self._model!
        log("  ⚙︎ DocRoot.body()")
        // We read model.items (array identity) but NOT item.color or item.height.
        // Each Item component will read those independently.
        let children = model.items.map { item in
            AnyElement(ComponentElement(Item(modelID: ObjectIdentifier(item))))
        }
        return ContainerElement(
            layout: AnyLayout(VStackLayout(spacing: 8)),
            children: children
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.modelID == rhs.modelID
    }
}

/// Item component: reads directly from its own ItemModel.
/// When item.color or item.height changes, only THIS component re-renders.
struct Item: Component, Equatable {
    let modelID: ObjectIdentifier

    // Static lookup table — in a real framework this would be an environment/context.
    @MainActor static var _models: [ObjectIdentifier: ItemModel] = [:]

    @MainActor func body() -> ColorFillElement {
        let model = Self._models[modelID]!
        log("  ⚙︎ Item.body() [\(model.id)]: color=\(model.color), h=\(model.height)")
        return ColorFillElement(color: model.color, height: model.height)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.modelID == rhs.modelID
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

        // Set up the component model references.
        DocRoot._model = model
        for item in model.items {
            Item._models[ObjectIdentifier(item)] = item
        }

        // Build the initial tree.
        let rootComponent = DocRoot(modelID: ObjectIdentifier(model))
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

        reconciler.transaction(dirtyPaths: paths)
        relayout()
    }

    func relayout() {
        let width = bounds.width
        guard width > 0, let root = reconciler.root else { return }

        LayoutEngine.layout(root, viewportWidth: width)
        renderer.container.bounds = self.bounds
        renderer.render(root: root, visibleRect: bounds)
    }

    override func layout() {
        super.layout()
        relayout()
    }

    override func mouseDown(with event: NSEvent) {
        guard let root = reconciler.root else { return }

        let locationInWindow = event.locationInWindow
        let locationInView = convert(locationInWindow, from: nil)
        let point = CGPoint(x: locationInView.x, y: locationInView.y)

        if let hit = HitTest.test(point: point, root: root) {
            log("🎯 hit: \(hit.path) at local(\(Int(hit.localPoint.x)), \(Int(hit.localPoint.y)))")
            let path = HitTest.hitPath(point: point, root: root)
            log("   path: \(path.map(\.path.description).joined(separator: " → "))")
        } else {
            log("🎯 miss")
        }
    }
}

// MARK: - Preference Demo

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
    // Debug: dump the tree structure.
    log("🌳 tree structure:")
    dumpNode(root, indent: 0)

    let frames: [LeafFrameEntry] = PreferenceEngine.collect(
        key: LeafFrameKey.self,
        from: root
    ) { node -> [LeafFrameEntry]? in
        guard node.children.isEmpty else { return nil }
        return [LeafFrameEntry(path: node.path, frame: node.frame)]
    }

    log("📐 leaf frames (via preference):")
    for entry in frames {
        log("   \(entry.path): \(Int(entry.frame.origin.x)),\(Int(entry.frame.origin.y)) \(Int(entry.frame.width))×\(Int(entry.frame.height))")
    }
}

@MainActor
func dumpNode(_ node: Node, indent: Int) {
    let pad = String(repeating: "  ", count: indent)
    let typeDesc: String
    if node.element.as(ContainerElement.self) != nil {
        typeDesc = "Container"
    } else if node.element.as(ColorFillElement.self) != nil {
        typeDesc = "ColorFill"
    } else {
        typeDesc = "Component"
    }
    let f = node.frame
    log("\(pad)\(node.path) [\(typeDesc)] frame=(\(Int(f.origin.x)),\(Int(f.origin.y)) \(Int(f.width))×\(Int(f.height))) cached=\(node.cachedSize.map { "\(Int($0.width))×\(Int($0.height))" } ?? "nil")")
    for child in node.children {
        dumpNode(child, indent: indent + 1)
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

        // --- Scenario 1: mutate individual item properties ---
        // These should dirty only the specific Item component, NOT the root.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            log("\n→ item[0].color: red → orange  (should dirty only Item 'a')")
            model.items[0].color = .orange
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            log("\n→ item[1].height: 60 → 150  (should dirty only Item 'b')")
            model.items[1].height = 150
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5) {
            log("\n→ item[2].color: green → purple  (should dirty only Item 'c')")
            model.items[2].color = .purple
        }

        // --- Scenario 2: mutate the items array itself ---
        // This should dirty the root (which reads model.items).
        DispatchQueue.main.asyncAfter(deadline: .now() + 6.0) {
            let newItem = ItemModel(id: "d", color: .gray, height: 50)
            Item._models[ObjectIdentifier(newItem)] = newItem
            log("\n→ append item 'd'  (should dirty DocRoot)")
            model.items.append(newItem)
        }

        // --- Scenario 3: mutate the new item ---
        // Should dirty only Item 'd'.
        DispatchQueue.main.asyncAfter(deadline: .now() + 7.5) {
            log("\n→ item[3].height: 50 → 90  (should dirty only Item 'd')")
            model.items[3].height = 90
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 9.0) {
            if let root = self.docView.reconciler.root {
                demoPreferences(root: root)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.5) {
            log("\n✓ demo complete")
        }
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
