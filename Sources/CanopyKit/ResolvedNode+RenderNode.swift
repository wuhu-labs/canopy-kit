import IdentifiedCollections

public extension RenderNode {
  static func make(from resolved: ResolvedNode) -> RenderNode {
    switch resolved.content {
    case let .component(component, child):
      RenderNode(
        .component(component, make(from: child)),
        nodeID: resolved.id,
        values: resolved.values,
        resolvedNode: resolved
      )

    case let .layout(layout, children):
      RenderNode(
        .container(layout, children.map(Self.make(from:))),
        nodeID: resolved.id,
        values: resolved.values,
        resolvedNode: resolved
      )

    case let .primitive(primitive):
      RenderNode(
        .primitive(primitive),
        nodeID: resolved.id,
        values: resolved.values,
        resolvedNode: resolved
      )
    }
  }

  static func reconcile(existing: RenderNode?, with resolved: ResolvedNode) -> RenderNode {
    guard let existing else {
      return make(from: resolved)
    }

    if existing.resolvedNode === resolved {
      return existing
    }

    guard existing.nodeID == resolved.id else {
      return make(from: resolved)
    }

    existing.values = resolved.values
    existing.resolvedNode = resolved

    switch resolved.content {
    case let .component(component, child):
      let shouldInvalidateLayout: Bool
      let reconciledChild: RenderNode
      switch existing.content {
      case let .component(existingComponent, existingChild):
        reconciledChild = reconcile(existing: existingChild, with: child)
        shouldInvalidateLayout =
          !existingComponent.isEquivalent(to: component) || reconciledChild !== existingChild
      default:
        reconciledChild = make(from: child)
        shouldInvalidateLayout = true
      }

      existing.content = .component(component, reconciledChild)
      if shouldInvalidateLayout {
        existing.invalidateLayout()
      }
      return existing

    case let .layout(layout, resolvedChildren):
      let shouldInvalidateLayout: Bool
      let existingChildrenByID = Dictionary(
        uniqueKeysWithValues: existing.children.map { ($0.nodeID, $0) }
      )
      let reconciledChildren = resolvedChildren.map { child in
        reconcile(existing: existingChildrenByID[child.id], with: child)
      }
      switch existing.content {
      case let .container(existingLayout, existingChildren):
        shouldInvalidateLayout =
          !existingLayout.isEquivalent(to: layout)
            || existingChildren.count != reconciledChildren.count
            || zip(existingChildren, reconciledChildren).contains(where: { existingChild, child in
              existingChild !== child
            })
      default:
        shouldInvalidateLayout = true
      }

      existing.content = .container(layout, reconciledChildren)
      if shouldInvalidateLayout {
        existing.invalidateLayout()
      }
      return existing

    case let .primitive(primitive):
      let shouldResetPrimitiveCache: Bool = switch existing.content {
      case let .primitive(existingPrimitive):
        !existingPrimitive.isEquivalent(to: primitive)
      default:
        true
      }

      existing.content = .primitive(primitive)
      if shouldResetPrimitiveCache {
        existing.primitiveCache = nil
        existing.invalidateLayout()
      }
      return existing
    }
  }
}
