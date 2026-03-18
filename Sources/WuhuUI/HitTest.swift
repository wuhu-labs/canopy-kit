import Foundation

// MARK: - Hit Testing

/// Standalone hit-testing against the node tree's frame table.
/// Finds the deepest node whose frame contains a given point.
/// This lives entirely outside the reactive system.
@MainActor
public enum HitTest {

    /// Result of a hit test.
    public struct Result {
        public let node: Node
        public let path: NodePath
        /// The point in the node's local coordinate space.
        public let localPoint: CGPoint
    }

    /// Find the deepest leaf node at the given point (in document coordinates).
    /// Returns `nil` if the point is outside all nodes.
    public static func test(point: CGPoint, root: Node) -> Result? {
        return deepestHit(point: point, node: root)
    }

    /// Find all nodes along the path from root to the deepest hit,
    /// in order from root to leaf. Useful for event bubbling.
    public static func hitPath(point: CGPoint, root: Node) -> [Result] {
        var results: [Result] = []
        collectHits(point: point, node: root, results: &results)
        return results
    }

    // MARK: - Internal

    private static func deepestHit(point: CGPoint, node: Node) -> Result? {
        guard node.frame.contains(point) else { return nil }

        // Try children in reverse order (last child is "on top").
        for child in node.children.reversed() {
            if let hit = deepestHit(point: point, node: child) {
                return hit
            }
        }

        // No child hit — this node is the deepest.
        let localPoint = CGPoint(
            x: point.x - node.frame.origin.x,
            y: point.y - node.frame.origin.y
        )
        return Result(node: node, path: node.path, localPoint: localPoint)
    }

    private static func collectHits(point: CGPoint, node: Node, results: inout [Result]) {
        guard node.frame.contains(point) else { return }

        let localPoint = CGPoint(
            x: point.x - node.frame.origin.x,
            y: point.y - node.frame.origin.y
        )
        results.append(Result(node: node, path: node.path, localPoint: localPoint))

        for child in node.children {
            collectHits(point: point, node: child, results: &results)
        }
    }
}
