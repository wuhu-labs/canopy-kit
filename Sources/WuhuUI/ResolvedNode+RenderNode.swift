public extension RenderNode {
  static func make(from resolved: ResolvedNode) -> RenderNode {
    switch resolved.content {
    case let .drawing(drawing):
      return .leaf(drawing, nodeID: resolved.id)

    case let .layout(layout, children):
      return .container(
        layout,
        children.map(Self.make(from:)),
        nodeID: resolved.id
      )
    }
  }

  static func reconcile(existing: RenderNode?, with resolved: ResolvedNode) -> RenderNode {
    guard let existing, existing.nodeID == resolved.id else {
      return make(from: resolved)
    }

    switch resolved.content {
    case let .drawing(drawing):
      existing.content = .leaf(drawing)
      existing.invalidateLayout()
      return existing

    case let .layout(layout, resolvedChildren):
      let existingChildren = Dictionary(
        uniqueKeysWithValues: existing.children.compactMap { child in
          child.nodeID.map { ($0, child) }
        }
      )

      let reconciledChildren = resolvedChildren.map { child in
        reconcile(existing: existingChildren[child.id], with: child)
      }

      existing.content = .container(layout, reconciledChildren)
      existing.invalidateLayout()
      return existing
    }
  }
}
