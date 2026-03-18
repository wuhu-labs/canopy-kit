import CoreGraphics
import Markdown

public struct MarkdownDocumentComponent: Component, Equatable {
  public var source: String

  public init(source: String) {
    self.source = source
  }

  public func body() -> ComponentBody {
    let document = Document(parsing: source)

    return .layoutNode(
      key: "document",
      AnyLayout(VStackLayout(spacing: 8)),
      children: renderBlocks(Array(document.children), keyPrefix: "block")
    )
  }
}

private func renderBlocks(_ blocks: [Markup], keyPrefix: String) -> [ComponentBody] {
  blocks.enumerated().compactMap { index, block in
    renderBlock(block, key: "\(keyPrefix)-\(index)")
  }
}

private func renderBlock(_ markup: Markup, key: String) -> ComponentBody? {
  switch markup {
  case let heading as Heading:
    let size: CGFloat
    switch heading.level {
    case 1: size = 30
    case 2: size = 24
    case 3: size = 19
    default: size = 16
    }

    return .drawingNode(
      key: key,
      AnyDrawing(TextDrawing(heading.plainText, fontSize: size))
    )

  case let paragraph as Paragraph:
    return .drawingNode(
      key: key,
      AnyDrawing(TextDrawing(paragraph.plainText, fontSize: 14))
    )

  case let unorderedList as UnorderedList:
    let items = Array(unorderedList.children)
    return .layoutNode(
      key: key,
      AnyLayout(VStackLayout(spacing: 6)),
      children: items.enumerated().compactMap { index, child in
        guard let listItem = child as? ListItem else { return nil }
        return renderListItem(
          listItem,
          key: "\(key)-item-\(index)",
          marker: "\u{2022}"
        )
      }
    )

  case let orderedList as OrderedList:
    let items = Array(orderedList.children)
    return .layoutNode(
      key: key,
      AnyLayout(VStackLayout(spacing: 6)),
      children: items.enumerated().compactMap { index, child in
        guard let listItem = child as? ListItem else { return nil }
        return renderListItem(
          listItem,
          key: "\(key)-item-\(index)",
          marker: "\(orderedList.startIndex + UInt(index))."
        )
      }
    )

  case let blockQuote as BlockQuote:
    return .layoutNode(
      key: key,
      AnyLayout(HStackLayout(spacing: 10)),
      children: [
        .drawingNode(
          key: "\(key)-marker",
          AnyDrawing(TextDrawing("\u{275A}", fontSize: 16))
        ),
        .layoutNode(
          key: "\(key)-content",
          AnyLayout(VStackLayout(spacing: 8)),
          children: renderBlocks(Array(blockQuote.children), keyPrefix: "\(key)-quote")
        ),
      ]
    )

  case _ as ThematicBreak:
    return .drawingNode(
      key: key,
      AnyDrawing(RectDrawing(color: CGColor(gray: 0.8, alpha: 1), height: 1))
    )

  case let codeBlock as CodeBlock:
    return .layoutNode(
      key: key,
      AnyLayout(InsetLayout(left: 12, top: 8, right: 12, bottom: 8)),
      children: [
        .drawingNode(
          key: "\(key)-code",
          AnyDrawing(TextDrawing(codeBlock.code, fontSize: 13))
        )
      ]
    )

  default:
    let fallback = plainText(from: markup)
    guard !fallback.isEmpty else { return nil }
    return .drawingNode(
      key: key,
      AnyDrawing(TextDrawing(fallback, fontSize: 14))
    )
  }
}

private func renderListItem(_ item: ListItem, key: String, marker: String) -> ComponentBody {
  .layoutNode(
    key: key,
    AnyLayout(HStackLayout(spacing: 8)),
    children: [
      .drawingNode(
        key: "\(key)-marker",
        AnyDrawing(TextDrawing(marker, fontSize: 14))
      ),
      .layoutNode(
        key: "\(key)-content",
        AnyLayout(VStackLayout(spacing: 6)),
        children: renderBlocks(Array(item.children), keyPrefix: "\(key)-block")
      ),
    ]
  )
}

private func plainText(from markup: Markup) -> String {
  if let markup = markup as? any PlainTextConvertibleMarkup {
    return markup.plainText
  }

  return Array(markup.children)
    .map(plainText(from:))
    .joined()
}
