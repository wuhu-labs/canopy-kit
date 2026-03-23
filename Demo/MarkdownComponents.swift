import CanopyKit
import CoreGraphics
import Markdown
import SwiftUI

// MARK: - Document Component

struct MarkdownDocumentComponent: Component, Equatable {
  var source: String

  func body() -> Node {
    let document = Document(parsing: source)
    let blocks = Array(document.children)

    return Canopy.VStack(spacing: 8) {
      for (index, block) in blocks.enumerated() {
        if let node = blockComponent(block, key: "block-\(index)") {
          node
        }
      }
    }
  }
}

// MARK: - Block Components

struct HeadingBlockComponent: Component, Equatable {
  let text: String
  let level: Int

  func body() -> Node {
    let size: CGFloat = switch level {
    case 1: 30
    case 2: 24
    case 3: 19
    default: 16
    }
    return Canopy.Text(text, fontSize: size)
  }
}

struct ParagraphBlockComponent: Component, Equatable {
  let text: String

  func body() -> Node {
    Canopy.Text(text)
  }
}

struct CodeBlockComponent: Component, Equatable {
  let code: String

  func body() -> Node {
    Canopy.Text(code, fontSize: 13)
      .padding(left: 12, top: 8, right: 12, bottom: 8)
  }
}

struct ThematicBreakComponent: Component, Equatable {
  func body() -> Node {
    Canopy.Shape(Rectangle())
      .frame(height: 1)
  }
}

struct BlockQuoteComponent: Component, Equatable {
  nonisolated let childBlocks: [BlockData]

  func body() -> Node {
    Canopy.ZStack {
      Canopy.Shape(Rectangle()).frame(width: 3).id("bar")

      Canopy.VStack(spacing: 8) {
        for (index, block) in childBlocks.enumerated() {
          if let node = blockComponentFromData(block, key: "quote-\(index)") {
            node
          }
        }
      }
      .padding(left: 13)
      .id("content")
    }
  }
}

struct UnorderedListComponent: Component, Equatable {
  nonisolated let items: [ListItemData]

  func body() -> Node {
    Canopy.VStack(spacing: 6) {
      for (index, item) in items.enumerated() {
        ListItemComponent(marker: "\u{2022}", item: item)
          .id("item-\(index)")
      }
    }
  }
}

struct OrderedListComponent: Component, Equatable {
  nonisolated let startIndex: UInt
  nonisolated let items: [ListItemData]

  func body() -> Node {
    Canopy.VStack(spacing: 6) {
      for (index, item) in items.enumerated() {
        ListItemComponent(
          marker: "\(startIndex + UInt(index)).",
          item: item
        )
        .id("item-\(index)")
      }
    }
  }
}

struct ListItemComponent: Component, Equatable {
  nonisolated let marker: String
  nonisolated let item: ListItemData

  func body() -> Node {
    Canopy.HStack(spacing: 8) {
      Canopy.Text(marker).id("marker")

      Canopy.VStack(spacing: 6) {
        for (index, block) in item.childBlocks.enumerated() {
          if let node = blockComponentFromData(block, key: "block-\(index)") {
            node
          }
        }
      }.id("content")
    }
  }
}

struct FallbackTextComponent: Component, Equatable {
  let text: String

  func body() -> Node {
    Canopy.Text(text)
  }
}

// MARK: - Extracted Data (Equatable, value types)

enum BlockData: Equatable, Sendable {
  case heading(text: String, level: Int)
  case paragraph(text: String)
  case codeBlock(code: String)
  case thematicBreak
  case blockQuote(children: [BlockData])
  case unorderedList(items: [ListItemData])
  case orderedList(startIndex: UInt, items: [ListItemData])
  case fallbackText(text: String)
}

struct ListItemData: Equatable, Sendable {
  let childBlocks: [BlockData]
}

// MARK: - Markup → Data Extraction

private func extractBlockData(_ markup: Markup) -> BlockData? {
  switch markup {
  case let heading as Heading:
    return .heading(text: heading.plainText, level: heading.level)

  case let paragraph as Paragraph:
    return .paragraph(text: paragraph.plainText)

  case let codeBlock as CodeBlock:
    return .codeBlock(code: codeBlock.code)

  case _ as ThematicBreak:
    return .thematicBreak

  case let blockQuote as BlockQuote:
    let children = Array(blockQuote.children).compactMap(extractBlockData)
    return .blockQuote(children: children)

  case let unorderedList as UnorderedList:
    let items = Array(unorderedList.children).compactMap { child -> ListItemData? in
      guard let listItem = child as? ListItem else { return nil }
      return ListItemData(childBlocks: Array(listItem.children).compactMap(extractBlockData))
    }
    return .unorderedList(items: items)

  case let orderedList as OrderedList:
    let items = Array(orderedList.children).compactMap { child -> ListItemData? in
      guard let listItem = child as? ListItem else { return nil }
      return ListItemData(childBlocks: Array(listItem.children).compactMap(extractBlockData))
    }
    return .orderedList(startIndex: orderedList.startIndex, items: items)

  default:
    let text = plainText(from: markup)
    guard !text.isEmpty else { return nil }
    return .fallbackText(text: text)
  }
}

// MARK: - Data → Component Nodes

@MainActor
private func blockComponentFromData(_ block: BlockData, key: String) -> IdentifiedNode? {
  switch block {
  case let .heading(text, level):
    HeadingBlockComponent(text: text, level: level).id(key)

  case let .paragraph(text):
    ParagraphBlockComponent(text: text).id(key)

  case let .codeBlock(code):
    CodeBlockComponent(code: code).id(key)

  case .thematicBreak:
    ThematicBreakComponent().id(key)

  case let .blockQuote(children):
    BlockQuoteComponent(childBlocks: children).id(key)

  case let .unorderedList(items):
    UnorderedListComponent(items: items).id(key)

  case let .orderedList(startIndex, items):
    OrderedListComponent(startIndex: startIndex, items: items).id(key)

  case let .fallbackText(text):
    FallbackTextComponent(text: text).id(key)
  }
}

/// Bridge from Markup AST directly to component node (used by MarkdownDocumentComponent.body).
@MainActor
private func blockComponent(_ markup: Markup, key: String) -> IdentifiedNode? {
  guard let data = extractBlockData(markup) else { return nil }
  return blockComponentFromData(data, key: key)
}

// MARK: - Helpers

private func plainText(from markup: Markup) -> String {
  if let markup = markup as? any PlainTextConvertibleMarkup {
    return markup.plainText
  }
  return Array(markup.children)
    .map(plainText(from:))
    .joined()
}
