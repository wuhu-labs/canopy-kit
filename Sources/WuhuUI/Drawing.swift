import CoreGraphics
import CoreText

// MARK: - Custom Drawing

/// A leaf knows how to measure itself and draw itself.
/// `Cache` is created once and reused across multiple sizeThatFits / draw calls
/// (e.g. a CTTypesetter for text).
public protocol CustomDrawing {
    associatedtype Cache

    /// Create the cache from the current data. Called once when the node is
    /// created or when its content changes.
    func makeCache() -> Cache

    /// Return the ideal size for the given width constraint.
    /// The cache (e.g. typesetter) makes repeated calls with different widths cheap.
    func sizeThatFits(width: CGFloat, cache: inout Cache) -> CGSize

    /// Draw into the given CGContext at the given rect.
    func draw(in context: CGContext, bounds: CGRect, cache: inout Cache)
}

// MARK: - AnyDrawing (type-erased)

/// Type-erased wrapper so RenderNode can hold any CustomDrawing.
public struct AnyDrawing: @unchecked Sendable {
    private let _makeCache: () -> Any
    private let _sizeThatFits: (CGFloat, inout Any) -> CGSize
    private let _draw: (CGContext, CGRect, inout Any) -> Void

    // The cache, created lazily.
    private var _cache: Any?

    public init<D: CustomDrawing>(_ drawing: D) {
        self._makeCache = { drawing.makeCache() as Any }
        self._sizeThatFits = { width, cache in
            var typed = cache as! D.Cache
            let size = drawing.sizeThatFits(width: width, cache: &typed)
            cache = typed
            return size
        }
        self._draw = { context, bounds, cache in
            var typed = cache as! D.Cache
            drawing.draw(in: context, bounds: bounds, cache: &typed)
            cache = typed
        }
        self._cache = nil
    }

    /// Ensure the cache exists.
    mutating func ensureCache() {
        if _cache == nil {
            _cache = _makeCache()
        }
    }

    public mutating func sizeThatFits(width: CGFloat) -> CGSize {
        ensureCache()
        return _sizeThatFits(width, &_cache!)
    }

    public mutating func draw(in context: CGContext, bounds: CGRect) {
        ensureCache()
        _draw(context, bounds, &_cache!)
    }

    /// Recreate the cache (call when content changes).
    public mutating func invalidateCache() {
        _cache = nil
    }
}
