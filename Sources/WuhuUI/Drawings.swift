import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - Text Drawing

/// A leaf that draws text via CoreText.
/// The CTTypesetter is cached — it's the expensive part.
/// sizeThatFits with different widths just re-does line breaking (cheap).
public struct TextDrawing: CustomDrawing {
  public var attributedString: CFAttributedString

  public init(_ string: String, fontSize: CGFloat = 14) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
      .foregroundColor: CGColor(gray: 0, alpha: 1),
    ]
    attributedString = NSAttributedString(string: string, attributes: attrs)
  }

  public init(attributedString: CFAttributedString) {
    self.attributedString = attributedString
  }

  // MARK: - Cache

  public struct Cache {
    var typesetter: CTTypesetter
  }

  public func makeCache() -> Cache {
    Cache(typesetter: CTTypesetterCreateWithAttributedString(attributedString))
  }

  // MARK: - Size

  public func sizeThatFits(width: CGFloat, cache: inout Cache) -> CGSize {
    let length = CFAttributedStringGetLength(attributedString)
    var offset = 0
    var height: CGFloat = 0

    while offset < length {
      let count = CTTypesetterSuggestLineBreak(cache.typesetter, offset, Double(width))
      let line = CTTypesetterCreateLine(cache.typesetter, CFRange(location: offset, length: count))

      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      height += ascent + descent + leading

      offset += count
    }

    return CGSize(width: width, height: height)
  }

  // MARK: - Draw

  public func draw(in context: CGContext, bounds: CGRect, cache: inout Cache) {
    let length = CFAttributedStringGetLength(attributedString)
    var offset = 0
    // CoreText draws with origin at bottom-left. We work top-down.
    // Flip the context.
    context.saveGState()
    context.translateBy(x: bounds.origin.x, y: bounds.origin.y + bounds.height)
    context.scaleBy(x: 1, y: -1)

    var y: CGFloat = 0

    while offset < length {
      let count = CTTypesetterSuggestLineBreak(cache.typesetter, offset, Double(bounds.width))
      let line = CTTypesetterCreateLine(cache.typesetter, CFRange(location: offset, length: count))

      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

      y += ascent
      context.textPosition = CGPoint(x: 0, y: bounds.height - y)
      CTLineDraw(line, context)
      y += descent + leading

      offset += count
    }

    context.restoreGState()
  }
}

// MARK: - Rect Drawing

/// A leaf that draws a filled rectangle. Simplest possible renderable.
public struct RectDrawing: CustomDrawing {
  public var color: CGColor
  public var height: CGFloat

  public init(color: CGColor, height: CGFloat) {
    self.color = color
    self.height = height
  }

  public struct Cache {}

  public func makeCache() -> Cache {
    Cache()
  }

  public func sizeThatFits(width: CGFloat, cache _: inout Cache) -> CGSize {
    CGSize(width: width, height: height)
  }

  public func draw(in context: CGContext, bounds: CGRect, cache _: inout Cache) {
    context.setFillColor(color)
    context.fill(bounds)
  }
}
