import Foundation

// MARK: - Element Protocol

/// A lightweight, value-type descriptor of UI structure.
/// Elements are cheap to create, equatable, and carry no layout state.
/// They describe *what* to render, not *how* it's laid out on screen.
public protocol Element: Equatable, Sendable {
    /// A stable type identifier used during reconciliation.
    /// Two elements with different `elementType` are never reconciled — the old
    /// node is torn down and a new one is created.
    static var elementType: ObjectIdentifier { get }
}

extension Element {
    public static var elementType: ObjectIdentifier {
        ObjectIdentifier(Self.self)
    }
}

// MARK: - AnyElement (type-erased wrapper)

/// Type-erased element for heterogeneous child arrays.
public struct AnyElement: Equatable, Sendable {
    public let typeID: ObjectIdentifier
    let _value: any Element & Sendable
    let _isEqual: @Sendable (any Element) -> Bool

    /// For component elements: a closure that expands the body with observation tracking.
    /// `nil` for non-component elements.
    internal let _expandBody: (@MainActor @Sendable (Node, @Sendable @escaping (NodePath) -> Void) -> AnyElement)?

    public init<E: Element>(_ element: E) {
        self.typeID = E.elementType
        self._value = element
        self._isEqual = { other in
            guard let other = other as? E else { return false }
            return element == other
        }
        self._expandBody = nil
    }

    /// Access the underlying element.
    public func `as`<E: Element>(_ type: E.Type) -> E? {
        _value as? E
    }

    public static func == (lhs: AnyElement, rhs: AnyElement) -> Bool {
        guard lhs.typeID == rhs.typeID else { return false }
        return lhs._isEqual(rhs._value)
    }
}

// MARK: - Built-in Elements

/// A container element: groups children under a layout strategy.
public struct ContainerElement: Element, Sendable {
    public var layout: AnyLayout
    public var children: [AnyElement]

    public init(layout: AnyLayout, children: [AnyElement]) {
        self.layout = layout
        self.children = children
    }
}

/// A leaf element that draws a filled rectangle.
/// Kept as the simplest possible renderable for now.
public struct ColorFillElement: Element, Sendable {
    public var color: PlatformColor
    public var height: CGFloat

    public init(color: PlatformColor, height: CGFloat) {
        self.color = color
        self.height = height
    }
}

/// Platform-independent color representation.
/// Avoids importing AppKit in the core library.
public struct PlatformColor: Equatable, Hashable, Sendable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let red = PlatformColor(red: 1, green: 0.23, blue: 0.19)
    public static let blue = PlatformColor(red: 0, green: 0.48, blue: 1)
    public static let green = PlatformColor(red: 0.2, green: 0.78, blue: 0.35)
    public static let orange = PlatformColor(red: 1, green: 0.58, blue: 0)
    public static let purple = PlatformColor(red: 0.69, green: 0.32, blue: 0.87)
    public static let gray = PlatformColor(red: 0.56, green: 0.56, blue: 0.58)
}
