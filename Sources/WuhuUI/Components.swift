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
final class ComponentRuntimeNode {
  weak var parent: ComponentRuntimeNode?

  let path: NodeID
  var component: AnyComponent

  private(set) var body: ComponentBody?
  private(set) var resolvedSubtree: ResolvedNode?
  private var childComponents: [NodeID: ComponentRuntimeNode] = [:]

  private(set) var dirty = true
  private(set) var subtreeDirty = true

  init(path: NodeID, component: AnyComponent, parent: ComponentRuntimeNode? = nil) {
    self.path = path
    self.component = component
    self.parent = parent
  }

  func updateComponent(_ component: AnyComponent) {
    guard !self.component.isEquivalent(to: component) else { return }
    self.component = component
    markDirty()
  }

  func markDirty() {
    dirty = true
    markSubtreeDirty()
  }

  func refreshIfNeeded(scheduleRefresh: @escaping @Sendable () -> Void) -> Bool {
    guard subtreeDirty || resolvedSubtree == nil else { return false }

    var didChange = resolvedSubtree == nil

    if dirty || body == nil {
      let newBody = withObservationTracking {
        component.body()
      } onChange: {
        Task { @MainActor in
          self.markDirty()
          scheduleRefresh()
        }
      }

      reconcileChildComponents(with: newBody)
      body = newBody
      dirty = false
      didChange = true
    }

    for child in childComponents.values where child.subtreeDirty || child.resolvedSubtree == nil {
      if child.refreshIfNeeded(scheduleRefresh: scheduleRefresh) {
        didChange = true
      }
    }

    if didChange, let body {
      resolvedSubtree = buildResolvedTree(from: body, trail: [])
    }

    subtreeDirty = false
    return didChange
  }

  private func markSubtreeDirty() {
    guard !subtreeDirty else { return }
    subtreeDirty = true
    parent?.markSubtreeDirty()
  }

  private func reconcileChildComponents(with body: ComponentBody) {
    let oldChildren = childComponents
    var newChildren: [NodeID: ComponentRuntimeNode] = [:]
    collectChildComponents(
      in: body,
      trail: [],
      oldChildren: oldChildren,
      newChildren: &newChildren
    )
    childComponents = newChildren
  }

  private func collectChildComponents(
    in body: ComponentBody,
    trail: NodeID,
    oldChildren: [NodeID: ComponentRuntimeNode],
    newChildren: inout [NodeID: ComponentRuntimeNode]
  ) {
    switch body {
    case let .component(key, component):
      let childPath = path + trail + [key]

      if let existing = oldChildren[childPath], existing.component.isEquivalent(to: component) {
        existing.parent = self
        newChildren[childPath] = existing
      } else {
        newChildren[childPath] = ComponentRuntimeNode(
          path: childPath,
          component: component,
          parent: self
        )
      }

    case let .layout(key, _, children):
      let nextTrail = trail + [key]
      for child in children {
        collectChildComponents(
          in: child,
          trail: nextTrail,
          oldChildren: oldChildren,
          newChildren: &newChildren
        )
      }

    case .drawing:
      break
    }
  }

  private func buildResolvedTree(from body: ComponentBody, trail: NodeID) -> ResolvedNode {
    switch body {
    case let .component(key, _):
      let childPath = path + trail + [key]
      guard let child = childComponents[childPath], let resolved = child.resolvedSubtree else {
        preconditionFailure("Missing resolved subtree for child component at path \(childPath)")
      }
      return resolved

    case let .layout(key, layout, children):
      let nextTrail = trail + [key]
      return ResolvedNode(
        id: path + nextTrail,
        localKey: key,
        content: .layout(
          layout,
          children.map { buildResolvedTree(from: $0, trail: nextTrail) }
        )
      )

    case let .drawing(key, drawing):
      let id = path + trail + [key]
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
  @ObservationIgnored private var refreshScheduled = false
  @ObservationIgnored private let rootNode: ComponentRuntimeNode

  @ObservationIgnored public private(set) var renderRoot: RenderNode
  public private(set) var revision = 0

  public init(root: AnyComponent) {
    rootNode = ComponentRuntimeNode(path: [], component: root)
    let initialResolved = ComponentResolver.resolve(root)
    renderRoot = RenderNode.make(from: initialResolved)
    refresh()
  }

  public func updateRoot(_ root: AnyComponent) {
    rootNode.updateComponent(root)
    scheduleRefresh()
  }

  public func refresh() {
    let didChange = rootNode.refreshIfNeeded { [weak self] in
      Task { @MainActor in
        self?.scheduleRefresh()
      }
    }

    guard didChange, let resolved = rootNode.resolvedSubtree else { return }

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
