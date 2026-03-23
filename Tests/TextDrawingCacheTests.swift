import AppKit
@testable import CanopyKit
import CoreText
import Testing

@Suite struct TextDrawingCacheTests {
  @Test func foregroundColorChangeReusesTypesetter() {
    let original = TextDrawing(attributedString: attributedString(text: "Hello", color: .red))
    var cache = original.makeCache()
    let originalTypesetter = ObjectIdentifier(cache.typesetter as AnyObject)

    let updated = TextDrawing(attributedString: attributedString(text: "Hello", color: .blue))
    updated.updateCache(&cache)

    #expect(ObjectIdentifier(cache.typesetter as AnyObject) == originalTypesetter)
  }

  @Test func contentChangeRecreatesTypesetter() {
    let original = TextDrawing(attributedString: attributedString(text: "Hello", color: .red))
    var cache = original.makeCache()
    let originalTypesetter = ObjectIdentifier(cache.typesetter as AnyObject)

    let updated = TextDrawing(attributedString: attributedString(text: "Hello there", color: .red))
    updated.updateCache(&cache)

    #expect(ObjectIdentifier(cache.typesetter as AnyObject) != originalTypesetter)
  }
}

private func attributedString(text: String, color: NSColor) -> CFAttributedString {
  NSAttributedString(
    string: text,
    attributes: [
      .font: CTFontCreateWithName("Helvetica" as CFString, 14, nil),
      .foregroundColor: color.cgColor,
    ]
  )
}
