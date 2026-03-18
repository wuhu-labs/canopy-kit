import Foundation

// MARK: - Node Path

/// Identifies a node's position in the tree.
/// Each segment is the child index at that level.
/// Example: [0, 2, 1] means root's child 0, then child 2, then child 1.
public struct NodePath: Hashable, Comparable, Sendable, CustomStringConvertible {
    public var segments: [Int]

    public init(_ segments: [Int] = []) {
        self.segments = segments
    }

    public func appending(_ index: Int) -> NodePath {
        NodePath(segments + [index])
    }

    public var depth: Int { segments.count }

    /// True if `self` is a prefix of (or equal to) `other`.
    public func isAncestor(of other: NodePath) -> Bool {
        guard segments.count <= other.segments.count else { return false }
        return other.segments.starts(with: segments)
    }

    public var description: String {
        segments.isEmpty ? "/" : "/" + segments.map(String.init).joined(separator: "/")
    }

    // Sort by depth-first: lexicographic on segments, shorter first.
    public static func < (lhs: NodePath, rhs: NodePath) -> Bool {
        let minLen = min(lhs.segments.count, rhs.segments.count)
        for i in 0..<minLen {
            if lhs.segments[i] != rhs.segments[i] {
                return lhs.segments[i] < rhs.segments[i]
            }
        }
        return lhs.segments.count < rhs.segments.count
    }
}

// MARK: - Node

/// A persistent node in the retained tree. Holds:
/// - The last element it was reconciled with (for diffing)
/// - Cached layout results
/// - Child nodes
/// - Its path in the tree (for dirty-set membership)
///
/// Nodes are reference types — they persist across reconciliation cycles.
/// The element is the ephemeral descriptor; the node is the long-lived state.
@MainActor
public final class Node {
    public let path: NodePath
    public internal(set) var element: AnyElement
    public internal(set) var children: [Node] = []

    // Layout cache — invalidated when element changes or children change.
    public internal(set) var cachedSize: CGSize?
    public internal(set) var cachedProposal: ProposedSize?

    // Frame in document coordinates, assigned during the layout pass.
    public internal(set) var frame: CGRect = .zero

    // For component nodes: the expanded body element from last render.
    // This is what we diff against when the component re-renders.
    internal var expandedBody: AnyElement?

    // For component nodes: the observation tracking cancellation.
    // When the observed state changes, we add this node's path to the dirty set.
    internal var observationCancellation: (@Sendable () -> Void)?

    public init(path: NodePath, element: AnyElement) {
        self.path = path
        self.element = element
    }

    deinit {
        observationCancellation?()
    }

    /// Invalidate layout cache. Called when element changes or children are modified.
    public func invalidateLayout() {
        cachedSize = nil
        cachedProposal = nil
    }

    /// Whether this node needs layout (no cache, or proposal changed).
    public func needsLayout(for proposal: ProposedSize) -> Bool {
        cachedSize == nil || cachedProposal != proposal
    }
}
