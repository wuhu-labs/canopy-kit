import Foundation
import Observation

// MARK: - Component Protocol

/// A component has a body that produces an element tree.
/// Components can hold @Observable state; the framework uses
/// `withObservationTracking` to detect when a component needs re-render.
public protocol Component: Equatable, Sendable {
    associatedtype Body: Element
    @MainActor func body() -> Body
}

// MARK: - ComponentElement

/// An element that wraps a component. During reconciliation, the component's
/// body is invoked to produce the actual element subtree.
///
/// Identity for reconciliation is by component type (via `elementType`).
/// Two `ComponentElement<C>`s with the same `C` type reconcile against each other;
/// equality is determined by the wrapped component.
public struct ComponentElement<C: Component>: Element, Sendable {
    public var component: C

    public init(_ component: C) {
        self.component = component
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.component == rhs.component
    }
}

// MARK: - AnyElement + Component Support

extension AnyElement {
    /// Create a type-erased element from a component element,
    /// preserving the ability to expand its body during reconciliation.
    public init<C: Component>(_ componentElement: ComponentElement<C>) {
        self.typeID = ComponentElement<C>.elementType
        self._value = componentElement
        self._isEqual = { other in
            guard let other = other as? ComponentElement<C> else { return false }
            return componentElement == other
        }
        self._expandBody = { @MainActor node, onDirty in
            let component = componentElement.component

            // Cancel previous observation.
            node.observationCancellation?()
            node.observationCancellation = nil

            // Run body with observation tracking.
            var body: C.Body!
            let path = node.path

            // Set up a flag so we only fire once per tracking cycle.
            // Re-registration happens on next reconciliation.
            nonisolated(unsafe) var fired = false

            withObservationTracking {
                body = component.body()
            } onChange: {
                if !fired {
                    fired = true
                    Task { @MainActor in
                        onDirty(path)
                    }
                }
            }

            return AnyElement(body)
        }
    }
}
