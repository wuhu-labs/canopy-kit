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
    var layoutAttributedString: NSAttributedString
    var drawingAttributedString: NSAttributedString
    var typesetter: CTTypesetter
  }

  public struct Commitment {
    var bounds: CGRect
    var lines: [Line]
  }

  public struct Line {
    var line: CTLine
    var position: CGPoint
  }

  public func makeCache() -> Cache {
    let drawingAttributedString = attributedString as NSAttributedString
    let layoutAttributedString = Self.layoutAttributedString(from: drawingAttributedString)
    return Cache(
      layoutAttributedString: layoutAttributedString,
      drawingAttributedString: drawingAttributedString,
      typesetter: CTTypesetterCreateWithAttributedString(layoutAttributedString)
    )
  }

  public func updateCache(_ cache: inout Cache) {
    let drawingAttributedString = attributedString as NSAttributedString
    let layoutAttributedString = Self.layoutAttributedString(from: drawingAttributedString)

    if cache.layoutAttributedString.isEqual(to: layoutAttributedString) {
      cache.drawingAttributedString = drawingAttributedString
    } else {
      cache = Cache(
        layoutAttributedString: layoutAttributedString,
        drawingAttributedString: drawingAttributedString,
        typesetter: CTTypesetterCreateWithAttributedString(layoutAttributedString)
      )
    }
  }

  // MARK: - Size

  public func sizeThatFits(proposal: ProposedSize, cache: inout Cache) -> CGSize {
    let width = proposal.width ?? .greatestFiniteMagnitude
    let length = cache.layoutAttributedString.length
    var offset = 0
    var height: CGFloat = 0
    var maxLineWidth: CGFloat = 0

    while offset < length {
      let count = CTTypesetterSuggestLineBreak(cache.typesetter, offset, Double(width))
      let line = CTTypesetterCreateLine(cache.typesetter, CFRange(location: offset, length: count))

      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      let lineWidth = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
      height += ascent + descent + leading
      maxLineWidth = max(maxLineWidth, ceil(lineWidth))

      offset += count
    }

    return CGSize(width: min(CGFloat(maxLineWidth), width), height: height)
  }

  // MARK: - Draw

  public func makeCommitment(in bounds: CGRect, cache: Cache) -> Commitment {
    let length = cache.drawingAttributedString.length
    var offset = 0
    var y: CGFloat = 0
    var lines: [Line] = []

    while offset < length {
      let count = CTTypesetterSuggestLineBreak(cache.typesetter, offset, Double(bounds.width))
      let line = CTLineCreateWithAttributedString(
        cache.drawingAttributedString.attributedSubstring(
          from: NSRange(location: offset, length: count)
        )
      )

      var ascent: CGFloat = 0
      var descent: CGFloat = 0
      var leading: CGFloat = 0
      CTLineGetTypographicBounds(line, &ascent, &descent, &leading)

      y += ascent
      lines.append(Line(line: line, position: CGPoint(x: 0, y: bounds.height - y)))
      y += descent + leading

      offset += count
    }

    return Commitment(bounds: bounds, lines: lines)
  }

  public func draw(in context: CGContext, commitment: Commitment) {
    // CoreText draws with origin at bottom-left. We work top-down.
    // Flip the context.
    context.saveGState()
    context.translateBy(
      x: commitment.bounds.origin.x,
      y: commitment.bounds.origin.y + commitment.bounds.height
    )
    context.scaleBy(x: 1, y: -1)

    for line in commitment.lines {
      context.textPosition = line.position
      CTLineDraw(line.line, context)
    }

    context.restoreGState()
  }

  private static func layoutAttributedString(from attributedString: NSAttributedString) -> NSAttributedString {
    let normalized = NSMutableAttributedString(attributedString: attributedString)
    normalized.enumerateAttribute(
      .foregroundColor,
      in: NSRange(location: 0, length: normalized.length)
    ) { value, range, _ in
      guard value != nil else { return }
      normalized.removeAttribute(.foregroundColor, range: range)
    }
    return normalized
  }
}
