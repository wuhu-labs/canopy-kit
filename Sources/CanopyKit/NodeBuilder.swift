import IdentifiedCollections

// MARK: - NodeBuilder

/// A result builder that collects ``IdentifiedNode`` values into an
/// ``IdentifiedArrayOf<IdentifiedNode>``.
///
/// Children that don't carry an explicit key are automatically keyed by
/// their positional index within the enclosing `buildBlock`.
@resultBuilder
public struct NodeBuilder {
  /// Single IdentifiedNode expression
  public static func buildExpression(_ node: IdentifiedNode) -> [IdentifiedNode] {
    [node]
  }

  /// Bare Node expression — auto-keyed by position
  public static func buildExpression(_ node: Node) -> [IdentifiedNode] {
    [IdentifiedNode(id: _AutoKey.unkeyed, node: node)]
  }

  /// Bare Component expression — auto-keyed by position
  @MainActor
  public static func buildExpression(_ component: some Component) -> [IdentifiedNode] {
    [Node.component(component).id(_AutoKey.unkeyed)]
  }

  /// Variadic block
  public static func buildBlock(_ components: [IdentifiedNode]...) -> [IdentifiedNode] {
    var result: [IdentifiedNode] = []
    for group in components {
      result.append(contentsOf: group)
    }
    return result
  }

  /// if
  public static func buildOptional(_ component: [IdentifiedNode]?) -> [IdentifiedNode] {
    component ?? []
  }

  /// if/else — first branch
  public static func buildEither(first component: [IdentifiedNode]) -> [IdentifiedNode] {
    component
  }

  /// if/else — second branch
  public static func buildEither(second component: [IdentifiedNode]) -> [IdentifiedNode] {
    component
  }

  /// for...in
  public static func buildArray(_ components: [[IdentifiedNode]]) -> [IdentifiedNode] {
    components.flatMap(\.self)
  }

  /// #available
  public static func buildLimitedAvailability(_ component: [IdentifiedNode]) -> [IdentifiedNode] {
    component
  }

  /// Auto-key by position
  public static func buildFinalResult(_ component: [IdentifiedNode]) -> IdentifiedArrayOf<IdentifiedNode> {
    var keyed: [IdentifiedNode] = []
    keyed.reserveCapacity(component.count)
    for (index, var child) in component.enumerated() {
      if child.id == AnyHashable(_AutoKey.unkeyed) {
        child.id = AnyHashable(_AutoKey.position(index))
      }
      keyed.append(child)
    }
    return IdentifiedArray(uniqueElements: keyed)
  }
}

// MARK: - Auto-keying sentinel

/// Keys used by ``NodeBuilder`` for positional auto-keying.
public enum _AutoKey: Hashable, Sendable {
  /// Sentinel value for nodes that haven't been explicitly keyed.
  case unkeyed
  /// Positional key assigned by `buildFinalResult`.
  case position(Int)
}
