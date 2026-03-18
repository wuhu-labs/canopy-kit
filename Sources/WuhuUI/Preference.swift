import Foundation

// MARK: - Preference Key

/// A type that defines a preference value that children can report upward.
/// The collecting ancestor sees all child values merged in tree order.
public protocol PreferenceKey {
    associatedtype Value: Equatable
    /// The initial value before any child reports.
    static var defaultValue: Value { get }
    /// Combine a new child value into the accumulated value.
    static func reduce(value: inout Value, nextValue: Value)
}

// MARK: - Preference Storage

/// Holds collected preference values for a node, keyed by preference type.
/// Attached to nodes that act as preference collectors.
@MainActor
public final class PreferenceStore {
    private var values: [ObjectIdentifier: Any] = [:]

    /// Read a preference value.
    public func value<K: PreferenceKey>(for key: K.Type) -> K.Value {
        values[ObjectIdentifier(K.self)] as? K.Value ?? K.defaultValue
    }

    /// Write a preference value.
    internal func setValue<K: PreferenceKey>(_ value: K.Value, for key: K.Type) {
        values[ObjectIdentifier(K.self)] = value
    }
}

// MARK: - Preference Collection

/// Walks the node tree bottom-up, collecting preference values from leaves
/// toward the nearest ancestor that has a PreferenceStore.
///
/// For now, preference collection is a separate post-layout pass.
/// Later it can be integrated into the layout pass itself.
@MainActor
public enum PreferenceEngine {

    /// Collect all preferences from the subtree rooted at `node`.
    /// Returns the merged value for the given key.
    public static func collect<K: PreferenceKey>(
        key: K.Type,
        from node: Node,
        reader: (Node) -> K.Value?
    ) -> K.Value {
        var result = K.defaultValue
        collectRecursive(key: key, node: node, reader: reader, result: &result)
        return result
    }

    private static func collectRecursive<K: PreferenceKey>(
        key: K.Type,
        node: Node,
        reader: (Node) -> K.Value?,
        result: inout K.Value
    ) {
        // If this node reports a value, merge it.
        if let value = reader(node) {
            K.reduce(value: &result, nextValue: value)
        }

        // Recurse into children (tree order).
        for child in node.children {
            collectRecursive(key: key, node: child, reader: reader, result: &result)
        }
    }
}
