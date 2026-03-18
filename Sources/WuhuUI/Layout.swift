import Foundation

// MARK: - Layout Protocol

/// Pure geometry: given child sizes and a size proposal, produce
/// the container's size and each child's frame in local coordinates.
///
/// Layout conformances are value types and must be equatable so the
/// reconciler can detect when a container's layout strategy changed.
public protocol Layout: Equatable, Sendable {
    func layout(children: [CGSize], proposal: ProposedSize) -> LayoutResult
}

// MARK: - Supporting Types

public struct ProposedSize: Equatable, Sendable {
    public var width: CGFloat
    public var height: CGFloat?

    public init(width: CGFloat, height: CGFloat? = nil) {
        self.width = width
        self.height = height
    }
}

public struct LayoutResult: Equatable, Sendable {
    public var size: CGSize
    public var childFrames: [CGRect]

    public init(size: CGSize, childFrames: [CGRect]) {
        self.size = size
        self.childFrames = childFrames
    }
}

// MARK: - AnyLayout (type-erased wrapper)

public struct AnyLayout: Equatable, Sendable {
    private let _typeID: ObjectIdentifier
    private let _layout: any Layout
    private let _isEqual: @Sendable (any Layout) -> Bool
    private let _run: @Sendable ([CGSize], ProposedSize) -> LayoutResult

    public init<L: Layout>(_ layout: L) {
        self._typeID = ObjectIdentifier(L.self)
        self._layout = layout
        self._isEqual = { other in
            guard let other = other as? L else { return false }
            return layout == other
        }
        self._run = { children, proposal in
            layout.layout(children: children, proposal: proposal)
        }
    }

    public func layout(children: [CGSize], proposal: ProposedSize) -> LayoutResult {
        _run(children, proposal)
    }

    public static func == (lhs: AnyLayout, rhs: AnyLayout) -> Bool {
        guard lhs._typeID == rhs._typeID else { return false }
        return lhs._isEqual(rhs._layout)
    }
}

// MARK: - Built-in Layouts

public struct VStackLayout: Layout, Sendable {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 0) {
        self.spacing = spacing
    }

    public func layout(children: [CGSize], proposal: ProposedSize) -> LayoutResult {
        var y: CGFloat = 0
        var frames: [CGRect] = []

        for (i, childSize) in children.enumerated() {
            if i > 0 { y += spacing }
            frames.append(CGRect(x: 0, y: y, width: childSize.width, height: childSize.height))
            y += childSize.height
        }

        return LayoutResult(
            size: CGSize(width: proposal.width, height: y),
            childFrames: frames
        )
    }
}

public struct HStackLayout: Layout, Sendable {
    public var spacing: CGFloat

    public init(spacing: CGFloat = 0) {
        self.spacing = spacing
    }

    public func layout(children: [CGSize], proposal: ProposedSize) -> LayoutResult {
        var x: CGFloat = 0
        var frames: [CGRect] = []
        var maxHeight: CGFloat = 0

        for (i, childSize) in children.enumerated() {
            if i > 0 { x += spacing }
            frames.append(CGRect(x: x, y: 0, width: childSize.width, height: childSize.height))
            x += childSize.width
            maxHeight = max(maxHeight, childSize.height)
        }

        return LayoutResult(
            size: CGSize(width: x, height: proposal.height ?? maxHeight),
            childFrames: frames
        )
    }
}
