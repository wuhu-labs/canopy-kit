import Foundation

// MARK: - Layout Engine

/// Pure layout computation over the node tree.
/// Two passes:
///   1. Measure (top-down proposal, bottom-up sizes) — skips nodes with valid cache.
///   2. Assign frames (top-down, absolute coordinates).
@MainActor
public enum LayoutEngine {

    /// Full layout pass: measure then assign frames.
    public static func layout(_ root: Node, viewportWidth: CGFloat) {
        let proposal = ProposedSize(width: viewportWidth)
        _ = measure(root, proposal: proposal)
        assignFrames(root, origin: .zero)
    }

    // MARK: - Measure

    /// Measure a node given a size proposal. Returns the node's computed size.
    /// Skips measurement if the cache is valid for this proposal.
    public static func measure(_ node: Node, proposal: ProposedSize) -> CGSize {
        // Cache hit: same proposal, cached size exists.
        if let cached = node.cachedSize, node.cachedProposal == proposal {
            return cached
        }

        let size: CGSize

        if let colorFill = node.element.as(ColorFillElement.self) {
            // Leaf: color fill knows its own size.
            size = CGSize(width: proposal.width, height: colorFill.height)
        } else if let container = node.element.as(ContainerElement.self) {
            // Container: measure children, run layout.
            let childSizes = node.children.map { measure($0, proposal: proposal) }
            let result = container.layout.layout(children: childSizes, proposal: proposal)

            // Store child frames on children (local coordinates, will be resolved in assignFrames).
            for (i, child) in node.children.enumerated() where i < result.childFrames.count {
                child.frame = result.childFrames[i]
            }

            size = result.size
        } else {
            // Component node: measure through to children.
            // A component node's children are the expanded body's children.
            if node.children.count == 1 {
                // Single child (the expanded body result).
                let childSize = measure(node.children[0], proposal: proposal)
                size = childSize
            } else if node.children.isEmpty {
                size = .zero
            } else {
                // Multiple children at component level — shouldn't normally happen
                // but handle gracefully with a default VStack.
                let childSizes = node.children.map { measure($0, proposal: proposal) }
                let result = VStackLayout().layout(children: childSizes, proposal: proposal)
                for (i, child) in node.children.enumerated() where i < result.childFrames.count {
                    child.frame = result.childFrames[i]
                }
                size = result.size
            }
        }

        node.cachedSize = size
        node.cachedProposal = proposal
        return size
    }

    // MARK: - Assign Frames

    /// Assign absolute frames in document coordinates.
    /// Each node's `frame` is set to its position in the document.
    public static func assignFrames(_ node: Node, origin: CGPoint) {
        let size = node.cachedSize ?? .zero
        node.frame = CGRect(origin: origin, size: size)

        if node.element.as(ContainerElement.self) != nil {
            // Container: children already have local frames from measure pass.
            for child in node.children {
                let childOrigin = CGPoint(
                    x: origin.x + child.frame.origin.x,
                    y: origin.y + child.frame.origin.y
                )
                assignFrames(child, origin: childOrigin)
            }
        } else if node.children.count == 1 {
            // Component wrapper: single child inherits origin.
            assignFrames(node.children[0], origin: origin)
        } else {
            for child in node.children {
                let childOrigin = CGPoint(
                    x: origin.x + child.frame.origin.x,
                    y: origin.y + child.frame.origin.y
                )
                assignFrames(child, origin: childOrigin)
            }
        }
    }

    // MARK: - Queries

    /// Collect all leaf nodes (nodes with no children — the things we draw).
    public static func leaves(_ node: Node) -> [Node] {
        if node.children.isEmpty { return [node] }
        return node.children.flatMap { leaves($0) }
    }

    /// Collect leaves whose frames intersect the given rect.
    public static func visibleLeaves(_ node: Node, in rect: CGRect) -> [Node] {
        // Early exit: if this node's frame doesn't intersect, skip entire subtree.
        guard node.frame.intersects(rect) else { return [] }
        if node.children.isEmpty { return [node] }
        return node.children.flatMap { visibleLeaves($0, in: rect) }
    }
}
