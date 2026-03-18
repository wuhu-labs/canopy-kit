import Observation
import SwiftUI

public typealias NodeID = [AnyHashable]

public protocol Component {
  func body() -> ComponentBody
}

public enum ComponentBody {
  case component(key: AnyHashable, AnyComponent)
  case layout(key: AnyHashable, layout: AnyLayout, children: [ComponentBody])
  case drawing(key: AnyHashable, drawing: AnyDrawing)
}

public extension ComponentBody {
  static func componentNode(key: some Hashable, _ component: AnyComponent) -> Self {
    .component(key: AnyHashable(key), component)
  }

  static func layoutNode(
    key: some Hashable,
    _ layout: AnyLayout,
    children: [ComponentBody]
  ) -> Self {
    .layout(key: AnyHashable(key), layout: layout, children: children)
  }

  static func drawingNode(key: some Hashable, _ drawing: AnyDrawing) -> Self {
    .drawing(key: AnyHashable(key), drawing: drawing)
  }
}

public struct AnyComponent {
  private let box: any AnyComponentBox

  public init<C: Component & Equatable>(_ component: C) {
    self.init(component) { $0 == $1 }
  }

  public init<C: Component>(_ component: C, isEquivalent: @escaping (C, C) -> Bool) {
    box = ComponentBox(component: component, isEquivalent: isEquivalent)
  }

  public func body() -> ComponentBody {
    box.body()
  }

  public func isEquivalent(to other: AnyComponent) -> Bool {
    box.isEquivalent(to: other.box)
  }

  var identity: ObjectIdentifier {
    ObjectIdentifier(box)
  }
}

private protocol AnyComponentBox: AnyObject {
  func body() -> ComponentBody
  func isEquivalent(to other: any AnyComponentBox) -> Bool
}

private final class ComponentBox<C: Component>: AnyComponentBox {
  let component: C
  let isEquivalent: (C, C) -> Bool

  init(component: C, isEquivalent: @escaping (C, C) -> Bool) {
    self.component = component
    self.isEquivalent = isEquivalent
  }

  func body() -> ComponentBody {
    component.body()
  }

  func isEquivalent(to other: any AnyComponentBox) -> Bool {
    guard let other = other as? ComponentBox<C> else { return false }
    return isEquivalent(component, other.component)
  }
}

public final class ResolvedNode {
  public enum Content {
    case layout(AnyLayout, [ResolvedNode])
    case drawing(AnyDrawing)
  }

  public let id: NodeID
  public let localKey: AnyHashable
  public let content: Content

  public init(id: NodeID, localKey: AnyHashable, content: Content) {
    self.id = id
    self.localKey = localKey
    self.content = content
  }

  public var children: [ResolvedNode] {
    switch content {
    case .drawing:
      []
    case let .layout(_, children):
      children
    }
  }
}

public enum ComponentResolver {
  public static func resolve(_ root: AnyComponent) -> ResolvedNode {
    resolve(root.body(), path: [])
  }

  public static func resolve(_ body: ComponentBody, path: NodeID) -> ResolvedNode {
    switch body {
    case let .component(key, component):
      return resolve(component.body(), path: path + [key])

    case let .layout(key, layout, children):
      let id = path + [key]
      let resolvedChildren = children.map { child in
        resolve(child, path: id)
      }
      return ResolvedNode(
        id: id,
        localKey: key,
        content: .layout(layout, resolvedChildren)
      )

    case let .drawing(key, drawing):
      let id = path + [key]
      return ResolvedNode(
        id: id,
        localKey: key,
        content: .drawing(drawing)
      )
    }
  }
}

@MainActor
@Observable
public final class ComponentRenderer {
  @ObservationIgnored private var root: AnyComponent
  @ObservationIgnored private var refreshScheduled = false

  @ObservationIgnored public private(set) var renderRoot: RenderNode
  public private(set) var revision = 0

  public init(root: AnyComponent) {
    self.root = root
    renderRoot = RenderNode.make(from: ComponentResolver.resolve(root))
    refresh()
  }

  public func updateRoot(_ root: AnyComponent) {
    guard !self.root.isEquivalent(to: root) else { return }
    self.root = root
    refresh()
  }

  public func refresh() {
    let resolved = withObservationTracking {
      ComponentResolver.resolve(root)
    } onChange: {
      Task { @MainActor in
        self.scheduleRefresh()
      }
    }

    renderRoot = RenderNode.reconcile(existing: renderRoot, with: resolved)
    revision &+= 1
  }

  private func scheduleRefresh() {
    guard !refreshScheduled else { return }
    refreshScheduled = true

    Task { @MainActor in
      await Task.yield()
      refreshScheduled = false
      refresh()
    }
  }
}

public struct ComponentTreeView: View {
  @State private var renderer: ComponentRenderer
  private let root: AnyComponent

  public init(root: AnyComponent) {
    self.root = root
    _renderer = State(initialValue: ComponentRenderer(root: root))
  }

  public var body: some View {
    RenderTreeView(root: renderer.renderRoot, revision: renderer.revision)
      .task(id: root.identity) {
        renderer.updateRoot(root)
      }
  }
}
