import Foundation
import Observation

// MARK: - Reconciler

/// The reconciler takes a set of dirty node paths and processes them
/// in depth-first order. For each dirty node, it re-runs the component
/// body (or re-evaluates the element), diffs children by index, and
/// reuses unchanged subtrees.
///
/// The dirty set only ever has entries added *ahead* of the current
/// processing cursor (strictly deeper paths), so the algorithm terminates
/// in a single pass.
@MainActor
public final class Reconciler {
    /// The root node of the persistent tree.
    public private(set) var root: Node?

    /// Callback invoked when an observed value changes and a node becomes dirty.
    /// The host (e.g. DocumentView) should schedule a transaction.
    public var onDirty: (@Sendable (NodePath) -> Void)?

    public init() {}

    // MARK: - Build (initial mount)

    /// Build the initial node tree from a root element.
    public func mount(element: AnyElement) {
        root = buildNode(element: element, path: NodePath())
    }

    // MARK: - Transaction (incremental update)

    /// Process a set of dirty paths. This is the main update entry point.
    /// Call this when observation fires or when the root element changes.
    public func transaction(dirtyPaths: Set<NodePath>) {
        guard let root else { return }

        // Sort by depth-first order so parents are processed before children.
        var remaining = dirtyPaths.sorted()

        var i = 0
        while i < remaining.count {
            let path = remaining[i]

            // Find the node at this path.
            guard let node = findNode(at: path, from: root) else {
                i += 1
                continue
            }

            // Reconcile this node's subtree.
            let subsumed = reconcileNode(node)

            // Remove any remaining dirty paths that were subsumed
            // (i.e., they were re-reconciled as part of this node's update).
            remaining.removeAll { candidate in
                candidate != path && subsumed.contains(candidate)
            }

            i += 1
        }
    }

    /// Convenience: reconcile with a single new root element (full rebuild).
    public func updateRoot(element: AnyElement) {
        guard let root else {
            mount(element: element)
            return
        }
        reconcileChildren(
            parent: root,
            oldChildren: root.element == element ? root.children : [],
            newElements: resolveChildren(of: element, path: root.path)
        )
        root.element = element
        root.invalidateLayout()
    }

    // MARK: - Internal: Build

    /// Create a new node for an element, recursively building children.
    private func buildNode(element: AnyElement, path: NodePath) -> Node {
        let node = Node(path: path, element: element)

        if let componentBody = expandComponent(element: element, node: node) {
            // Component node: expand body, build children from body.
            node.expandedBody = componentBody
            let childElements = resolveChildren(of: componentBody, path: path)
            node.children = childElements.enumerated().map { i, childElem in
                buildNode(element: childElem, path: path.appending(i))
            }
        } else {
            // Container or leaf: build children directly.
            let childElements = resolveChildren(of: element, path: path)
            node.children = childElements.enumerated().map { i, childElem in
                buildNode(element: childElem, path: path.appending(i))
            }
        }

        return node
    }

    // MARK: - Internal: Reconcile

    /// Reconcile a single dirty node. Returns the set of deeper paths
    /// that were subsumed (re-reconciled as part of this update).
    @discardableResult
    private func reconcileNode(_ node: Node) -> Set<NodePath> {
        var subsumed = Set<NodePath>()

        if let newBody = expandComponent(element: node.element, node: node) {
            // Component node: re-run body, diff against old body.
            let oldBody = node.expandedBody
            node.expandedBody = newBody

            if oldBody != newBody {
                // Body changed — reconcile children.
                let newChildElements = resolveChildren(of: newBody, path: node.path)
                let reconciledPaths = reconcileChildren(
                    parent: node,
                    oldChildren: node.children,
                    newElements: newChildElements
                )
                subsumed = reconciledPaths
                node.invalidateLayout()
            }
        } else {
            // Non-component node: resolve children from element.
            let newChildElements = resolveChildren(of: node.element, path: node.path)
            let reconciledPaths = reconcileChildren(
                parent: node,
                oldChildren: node.children,
                newElements: newChildElements
            )
            subsumed = reconciledPaths
            node.invalidateLayout()
        }

        return subsumed
    }

    /// Reconcile children by index. Returns paths of children that were
    /// re-reconciled (newly created or updated).
    @discardableResult
    private func reconcileChildren(
        parent: Node,
        oldChildren: [Node],
        newElements: [AnyElement]
    ) -> Set<NodePath> {
        var newChildren: [Node] = []
        var reconciledPaths = Set<NodePath>()

        for (i, newElem) in newElements.enumerated() {
            let childPath = parent.path.appending(i)

            if i < oldChildren.count {
                let oldChild = oldChildren[i]

                if oldChild.element.typeID == newElem.typeID && oldChild.element == newElem {
                    // Same type, same value → reuse entirely, skip.
                    newChildren.append(oldChild)
                } else if oldChild.element.typeID == newElem.typeID {
                    // Same type, different value → update in place, recurse.
                    oldChild.element = newElem
                    oldChild.invalidateLayout()
                    reconcileNode(oldChild)
                    reconciledPaths.insert(childPath)
                    newChildren.append(oldChild)
                } else {
                    // Different type → tear down old, build new.
                    let newChild = buildNode(element: newElem, path: childPath)
                    reconciledPaths.insert(childPath)
                    newChildren.append(newChild)
                }
            } else {
                // New child (list grew).
                let newChild = buildNode(element: newElem, path: childPath)
                reconciledPaths.insert(childPath)
                newChildren.append(newChild)
            }
        }

        parent.children = newChildren
        return reconciledPaths
    }

    // MARK: - Internal: Component Expansion

    /// If the element wraps a component, run its body (with observation tracking)
    /// and return the body element. Otherwise return nil.
    private func expandComponent(element: AnyElement, node: Node) -> AnyElement? {
        guard let expandBody = element._expandBody else {
            return nil
        }
        // Capture self weakly — onDirty is read at fire time, not capture time.
        let sendableDirtyCallback: @Sendable (NodePath) -> Void = { [weak self] path in
            Task { @MainActor in
                self?.onDirty?(path)
            }
        }
        return expandBody(node, sendableDirtyCallback)
    }

    // MARK: - Internal: Resolve Children

    /// Extract child elements from an element.
    /// Containers have children; leaves have none; components are expanded separately.
    private func resolveChildren(of element: AnyElement, path: NodePath) -> [AnyElement] {
        if let container = element.as(ContainerElement.self) {
            return container.children
        }
        // Leaf or unknown → no children.
        return []
    }

    // MARK: - Internal: Tree Navigation

    /// Find a node at a given path, starting from a root.
    private func findNode(at path: NodePath, from root: Node) -> Node? {
        var current = root
        // The root is at NodePath([]), skip its segments.
        for segment in path.segments {
            guard segment < current.children.count else { return nil }
            current = current.children[segment]
        }
        return current
    }
}

