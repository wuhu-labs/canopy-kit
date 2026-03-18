import AppKit
import CoreGraphics

// MARK: - Drawing Layer

/// A CALayer subclass that draws via a CustomDrawing.
/// We store the drawing on the layer so `draw(in:)` can invoke it.
final class DrawingLayer: CALayer {
    var drawing: AnyDrawing?

    override func draw(in ctx: CGContext) {
        guard var drawing else { return }
        drawing.draw(in: ctx, bounds: bounds)
        self.drawing = drawing  // write back (cache may have mutated)
    }
}

// MARK: - Renderer

/// Projects the render tree's visible leaves into a CALayer hierarchy.
/// Keyed by object identity of the RenderNode.
@MainActor
public final class Renderer {
    public let container: CALayer
    private var activeLayers: [ObjectIdentifier: DrawingLayer] = [:]
    private var previousVisible: Set<ObjectIdentifier> = []

    public init(container: CALayer) {
        self.container = container
    }

    public func render(root: RenderNode, visibleRect: CGRect) {
        let visible = root.visibleLeaves(in: visibleRect)
        let visibleByID = Dictionary(
            uniqueKeysWithValues: visible.map { (ObjectIdentifier($0), $0) }
        )
        let newVisible = Set(visibleByID.keys)

        // Remove disappeared.
        for id in previousVisible.subtracting(newVisible) {
            if let layer = activeLayers.removeValue(forKey: id) {
                layer.removeFromSuperlayer()
            }
        }

        // Update / create.
        for (id, node) in visibleByID {
            let layer: DrawingLayer
            if let existing = activeLayers[id] {
                layer = existing
            } else {
                layer = DrawingLayer()
                layer.contentsScale = container.contentsScale
                container.addSublayer(layer)
                activeLayers[id] = layer
            }

            // Flip Y: our layout is top-left origin, CALayer is bottom-left.
            let flippedY = container.bounds.height - node.frame.maxY
            let newFrame = CGRect(
                x: node.frame.origin.x,
                y: flippedY,
                width: node.frame.width,
                height: node.frame.height
            )

            if layer.frame != newFrame {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.frame = newFrame
                CATransaction.commit()
            }

            // Attach drawing and mark for redraw.
            if case .leaf(let drawing) = node.content {
                layer.drawing = drawing
                layer.setNeedsDisplay()
            }
        }

        previousVisible = newVisible
    }
}
