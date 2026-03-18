import Foundation
import AppKit

// MARK: - Renderer

/// Platform projection: takes the node tree's frame table, intersects with
/// the viewport, and produces minimal CALayer mutations.
///
/// Completely decoupled from the element/component/reconciliation system.
/// It only reads `node.frame` and `node.element` to decide what to draw.
@MainActor
public final class Renderer {
    public let container: CALayer
    private var activeLayers: [NodePath: CALayer] = [:]
    private var previousVisibleSet: Set<NodePath> = []

    /// Called when a node enters the visible set.
    public var onAppear: ((NodePath) -> Void)?
    /// Called when a node leaves the visible set.
    public var onDisappear: ((NodePath) -> Void)?

    public init(container: CALayer) {
        self.container = container
    }

    /// Render visible leaves from the node tree into the container layer.
    public func render(root: Node, visibleRect: CGRect) {
        let visible = LayoutEngine.visibleLeaves(root, in: visibleRect)
        let visibleByPath = Dictionary(uniqueKeysWithValues: visible.map { ($0.path, $0) })
        let newVisibleSet = Set(visibleByPath.keys)

        // Lifecycle: diff visible sets.
        let appeared = newVisibleSet.subtracting(previousVisibleSet)
        let disappeared = previousVisibleSet.subtracting(newVisibleSet)

        for path in disappeared {
            onDisappear?(path)
            if let layer = activeLayers.removeValue(forKey: path) {
                layer.removeFromSuperlayer()
            }
        }

        for path in appeared {
            onAppear?(path)
        }

        // Update/create layers for visible leaves.
        for (path, node) in visibleByPath {
            let layer: CALayer
            if let existing = activeLayers[path] {
                layer = existing
            } else {
                layer = makeLayer(for: node)
                container.addSublayer(layer)
                activeLayers[path] = layer
            }

            updateLayer(layer, for: node, containerBounds: container.bounds)
        }

        previousVisibleSet = newVisibleSet
    }

    // MARK: - Layer Factory

    private func makeLayer(for node: Node) -> CALayer {
        if node.element.as(ColorFillElement.self) != nil {
            return CALayer()
        }
        // Default fallback.
        return CALayer()
    }

    // MARK: - Layer Update

    private func updateLayer(_ layer: CALayer, for node: Node, containerBounds: CGRect) {
        // Flip Y: CALayer origin is bottom-left, our layout is top-left.
        let flippedY = containerBounds.height - node.frame.maxY
        let newFrame = CGRect(
            x: node.frame.origin.x,
            y: flippedY,
            width: node.frame.width,
            height: node.frame.height
        )

        // Only update if frame actually changed.
        if layer.frame != newFrame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.frame = newFrame
            CATransaction.commit()
        }

        // Update content.
        if let colorFill = node.element.as(ColorFillElement.self) {
            let cgColor = CGColor(
                red: colorFill.color.red,
                green: colorFill.color.green,
                blue: colorFill.color.blue,
                alpha: colorFill.color.alpha
            )
            if layer.backgroundColor != cgColor {
                layer.backgroundColor = cgColor
            }
        }
    }
}
