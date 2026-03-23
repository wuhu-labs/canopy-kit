import CanopyKit
import CoreGraphics
import CoreText
import Foundation
import Markdown
import Observation
import SwiftUI

#if canImport(AppKit)
  import AppKit
#elseif canImport(UIKit)
  import UIKit
#endif

// MARK: - Observable Models

/// Per-tool-call observable model. Holds mutable `isExpanded` state
/// so tapping a tool call only re-renders that one component.
@Observable
final class ChatToolCallModel: Identifiable {
  let id: String
  var name: String
  var arguments: String
  var result: String
  var isExpanded: Bool

  init(
    id: String,
    name: String,
    arguments: String,
    result: String,
    isExpanded: Bool = false
  ) {
    self.id = id
    self.name = name
    self.arguments = arguments
    self.result = result
    self.isExpanded = isExpanded
  }
}

/// Image attachment — value type is fine, these don't mutate.
struct ChatImageAttachment: Identifiable, Equatable, Sendable {
  let id: String
  var blobURI: String
  var mimeType: String
}

/// Per-message observable model. Each message is its own observable
/// so mutations (e.g. streaming content append) only dirty that one
/// message's component — the root array is untouched.
@Observable
final class ChatMessageModel: Identifiable {
  let id: String
  var role: Role
  var author: String?
  var content: String
  var images: [ChatImageAttachment]
  var timestamp: Date
  var toolCalls: [ChatToolCallModel]

  enum Role {
    case user
    case assistant
  }

  init(
    id: String,
    role: Role,
    author: String? = nil,
    content: String,
    images: [ChatImageAttachment] = [],
    timestamp: Date,
    toolCalls: [ChatToolCallModel] = []
  ) {
    self.id = id
    self.role = role
    self.author = author
    self.content = content
    self.images = images
    self.timestamp = timestamp
    self.toolCalls = toolCalls
  }
}

/// Root session model. The component tree observes this at the top level
/// only for the `messages` array identity (add/remove). Individual message
/// mutations are tracked by each message's own `ChatMessageModel`.
///
/// Streaming is modeled as a dedicated `ChatMessageModel` that gets
/// appended to `messages` while actively streaming, then stays as the
/// finalized message. The `streamingMessageID` tracks which message
/// (if any) is currently being streamed into.
@Observable
final class ChatSessionModel {
  var messages: [ChatMessageModel] = []
  var streamingMessageID: String?
  var isRunning: Bool = false

  init() {}

  /// The message currently being streamed, if any.
  var streamingMessage: ChatMessageModel? {
    guard let id = streamingMessageID else { return nil }
    return messages.last { $0.id == id }
  }

  /// Begin streaming: creates a new assistant message and marks it as
  /// the streaming target. Returns the model for direct mutation.
  @discardableResult
  func beginStreaming(id: String = "__streaming-\(UUID().uuidString)") -> ChatMessageModel {
    let message = ChatMessageModel(
      id: id,
      role: .assistant,
      content: "",
      timestamp: Date()
    )
    messages.append(message)
    streamingMessageID = id
    isRunning = true
    return message
  }

  /// Finalize streaming: clears the streaming marker but keeps the
  /// message in the array as a normal assistant message.
  func finalizeStreaming() {
    streamingMessageID = nil
    isRunning = false
  }
}

// MARK: - Color Constants

private enum SessionColors {
  static let userHeaderColor = CGColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1)
  static let assistantHeaderColor = CGColor(red: 0.6, green: 0.35, blue: 0.85, alpha: 1)
  static let userBubbleBackground = CGColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 0.08)
  static let toolCallBorder = CGColor(gray: 0.85, alpha: 1)
  static let toolCallBackground = CGColor(gray: 0.96, alpha: 1)
  static let toolCallNameColor = CGColor(red: 0.9, green: 0.6, blue: 0.2, alpha: 1)
  static let secondaryTextColor = CGColor(gray: 0.5, alpha: 1)
  static let sectionDividerColor = CGColor(gray: 0.9, alpha: 1)
  static let streamingCursorColor = CGColor(red: 0.6, green: 0.35, blue: 0.85, alpha: 0.6)
  static let imagePlaceholderColor = CGColor(gray: 0.88, alpha: 1)
}

// MARK: - Formatting

private let timestampFormatter: DateFormatter = {
  let f = DateFormatter()
  f.dateStyle = .none
  f.timeStyle = .short
  return f
}()

// MARK: - Root Session Component

/// Root component. Observes `model.messages` (the array) and
/// `model.streamingMessageID` / `model.isRunning`. When a message is
/// appended or removed the root re-evaluates, but each child component
/// is pointer-compared (single class field → O(1)) so unchanged messages
/// are skipped entirely.
struct SessionRootComponent: Component {
  let model: ChatSessionModel

  func body() -> Node {
    let streamingID = model.streamingMessageID
    let isRunning = model.isRunning

    return .vstack(spacing: 0) {
      for message in model.messages {
        let isStreaming = message.id == streamingID
        IdentifiedNode.component(
          key: message.id,
          MessageComponent(
            model: message,
            isStreaming: isStreaming
          )
        )
      }
      if isRunning, streamingID == nil {
        IdentifiedNode.component(
          key: "__thinking",
          ThinkingIndicatorComponent()
        )
      }
    }
  }
}

// MARK: - Message Component

/// Dispatches to the appropriate role-specific body. Holds a single
/// `ChatMessageModel` reference — the engine compares via pointer
/// equality so unchanged messages are O(1) to skip.
///
/// `isStreaming` is a value field, so when streaming ends and this flips
/// from true→false, the component is considered changed and re-evaluates
/// (dropping the cursor). This is cheap since it only affects one message.
struct MessageComponent: Component {
  let model: ChatMessageModel
  let isStreaming: Bool

  func body() -> Node {
    switch model.role {
    case .user:
      userBody()
    case .assistant:
      assistantBody(isStreaming: isStreaming)
    }
  }

  // MARK: - User Body

  private func userBody() -> Node {
    let author = model.author ?? "User"
    let timestamp = timestampFormatter.string(from: model.timestamp)

    return Node.vstack(spacing: 6) {
      IdentifiedNode.drawing(
        key: "header",
        TextDrawing(
          attributedString: makeHeaderAttributedString(
            author: author,
            timestamp: timestamp,
            color: SessionColors.userHeaderColor
          )
        )
      )
      if !model.content.isEmpty {
        IdentifiedNode(
          id: "bubble",
          node: Node.text(model.content)
            .padding(left: 10, top: 8, right: 10, bottom: 8)
            .viewModifier(BubbleBackground(color: SessionColors.userBubbleBackground))
        )
      }
      for image in model.images {
        IdentifiedNode.component(
          key: "img-\(image.id)",
          ImagePlaceholderComponent(
            label: "📎 Image: \(image.blobURI.split(separator: "/").last ?? "image")"
          )
        )
      }
    }
    .padding(left: 16, top: 12, right: 16, bottom: 12)
  }

  private func assistantBody(isStreaming: Bool) -> Node {
    return Node.vstack(spacing: 6) {
      if isStreaming {
        IdentifiedNode.drawing(
          key: "header",
          TextDrawing(
            attributedString: makeStreamingHeaderAttributedString()
          )
        )
      } else {
        let timestamp = timestampFormatter.string(from: model.timestamp)
        IdentifiedNode.drawing(
          key: "header",
          TextDrawing(
            attributedString: makeHeaderAttributedString(
              author: "Agent",
              timestamp: timestamp,
              color: SessionColors.assistantHeaderColor
            )
          )
        )
      }
      if !model.content.isEmpty {
        IdentifiedNode.component(
          key: "markdown",
          RichMarkdownComponent(source: model.content)
        )
      }
      if isStreaming {
        IdentifiedNode(
          id: "cursor",
          node: .shape(Rectangle()).frame(height: 3)
        )
      }
      for image in model.images {
        IdentifiedNode.component(
          key: "img-\(image.id)",
          ImagePlaceholderComponent(
            label: "📎 Image: \(image.blobURI.split(separator: "/").last ?? "image")"
          )
        )
      }
      for tc in model.toolCalls {
        IdentifiedNode.component(
          key: "tc-\(tc.id)",
          ToolCallComponent(model: tc)
        )
      }
      if !isStreaming {
        IdentifiedNode(
          id: "divider",
          node: .shape(Rectangle()).frame(height: 1)
        )
      }
    }
    .padding(left: 16, top: 12, right: 16, bottom: 4)
  }
}

// MARK: - Thinking Indicator Component

struct ThinkingIndicatorComponent: Component {
  func body() -> Node {
    Node.text(attributedString: makeThinkingAttributedString())
      .padding(left: 16, top: 12, right: 16, bottom: 12)
  }
}

// MARK: - Tool Call Component

/// Each tool call is its own component with its own `ChatToolCallModel`.
/// Tapping toggles `model.isExpanded`, which only re-renders this one
/// component. The parent message component is untouched because the
/// `toolCalls` array reference didn't change.
struct ToolCallComponent: Component {
  let model: ChatToolCallModel

  func body() -> Node {
    return Node.zstack {
      Node.shape(Rectangle()).frame(width: 2).keyed("bar")

      Node.vstack(spacing: 4) {
        IdentifiedNode.drawing(
        key: "label",
        TextDrawing(
          attributedString: makeToolCallAttributedString(
            name: model.name,
            args: model.arguments,
            isExpanded: model.isExpanded,
            hasResult: !model.result.isEmpty
          )
        )
      )
        if !model.result.isEmpty, model.isExpanded {
        IdentifiedNode(
          id: "result-bg",
          node: Node.text(attributedString: makeMonoAttributedString(
            model.result,
            fontSize: 11,
            color: SessionColors.secondaryTextColor
          ))
          .padding(left: 8, top: 6, right: 8, bottom: 6)
          .viewModifier(BubbleBackground(color: SessionColors.toolCallBackground))
        )
        }
      }
      .padding(left: 10, top: 4, bottom: 4)
      .keyed("tool-content")
    }
    .viewModifier(TapGestureModifier(action: { [weak model] in
      model?.isExpanded.toggle()
    }))
  }
}

private struct TapGestureModifier: ViewModifier {
  let action: () -> Void

  func body(content: Content) -> some View {
    content.onTapGesture(perform: action)
  }
}

private struct BubbleBackground: ViewModifier {
  let color: CGColor

  func body(content: Content) -> some View {
    content.background(Color(cgColor: color))
  }
}

// MARK: - Image Placeholder Component

struct ImagePlaceholderComponent: Component, Equatable {
  let label: String

  func body() -> Node {
    Node.text(attributedString: makeMonoAttributedString(label, fontSize: 12, color: SessionColors.secondaryTextColor))
      .padding(left: 12, top: 20, right: 12, bottom: 20)
      .frame(height: 60)
      .viewModifier(BubbleBackground(color: SessionColors.imagePlaceholderColor))
  }
}

// MARK: - Rich Markdown Component

/// Parses markdown source into a CanopyKit tree with rich inline
/// rendering via NSAttributedString (bold, italic, code, links).
struct RichMarkdownComponent: Component, Equatable {
  var source: String

  func body() -> Node {
    let document = Document(parsing: source)
    let blocks = Array(document.children)

    return .vstack(spacing: 8) {
      for (index, block) in blocks.enumerated() {
        if let node = richBlockNode(block, key: "block-\(index)") {
          node
        }
      }
    }
  }
}

// MARK: - Rich Block Rendering

private func richBlockNode(_ markup: Markup, key: String) -> IdentifiedNode? {
  switch markup {
  case let heading as Heading:
    let fontSize: CGFloat = switch heading.level {
    case 1: 26
    case 2: 22
    case 3: 18
    default: 16
    }
    let attrString = renderInlinesRich(heading.inlineChildren, baseFontSize: fontSize, bold: true)
    return Node.text(attributedString: attrString).keyed(key)

  case let paragraph as Paragraph:
    let attrString = renderInlinesRich(paragraph.inlineChildren, baseFontSize: 14, bold: false)
    return Node.text(attributedString: attrString).keyed(key)

  case let codeBlock as CodeBlock:
    return .component(
      key: key,
      RichCodeBlockComponent(
        code: codeBlock.code,
        language: codeBlock.language
      )
    )

  case _ as ThematicBreak:
    return IdentifiedNode(
      id: key,
      node: .shape(Rectangle()).frame(height: 1)
    )

  case let blockQuote as BlockQuote:
    let childNodes = Array(blockQuote.children).enumerated().compactMap { i, child in
      richBlockNode(child, key: "bq-\(i)")
    }
    guard !childNodes.isEmpty else { return nil }

    return Node.zstack {
      Node.shape(Rectangle()).frame(width: 3).keyed("bar")
      Node.vstack(spacing: 6) {
        for childNode in childNodes {
          childNode
        }
      }
      .padding(left: 13)
      .keyed("content")
    }
    .keyed(key)

  case let unorderedList as UnorderedList:
    let items = Array(unorderedList.listItems).enumerated().map { i, item in
      richListItemNode(item, marker: "•", key: "li-\(i)")
    }
    return Node.vstack(spacing: 4) {
      for item in items {
        item
      }
    }.keyed(key)

  case let orderedList as OrderedList:
    let items = Array(orderedList.listItems).enumerated().map { i, item in
      richListItemNode(item, marker: "\(orderedList.startIndex + UInt(i)).", key: "li-\(i)")
    }
    return Node.vstack(spacing: 4) {
      for item in items {
        item
      }
    }.keyed(key)

  case let table as Markdown.Table:
    return richTableNode(table, key: key)

  default:
    let text = plainTextFromMarkup(markup)
    guard !text.isEmpty else { return nil }
    return Node.text(text).keyed(key)
  }
}

private func richListItemNode(_ item: ListItem, marker: String, key: String) -> IdentifiedNode {
  let childNodes = Array(item.children).enumerated().compactMap { i, child in
    richBlockNode(child, key: "item-\(i)")
  }

  return Node.hstack(spacing: 6) {
    Node.text(marker).keyed("marker")
    Node.vstack(spacing: 4) {
      for node in childNodes {
        node
      }
    }.keyed("content")
  }.keyed(key)
}

private func richTableNode(_ table: Markdown.Table, key: String) -> IdentifiedNode {
  let headers = Array(table.head.cells.map(\.plainText))
  let rows = Array(table.body.rows.map { row in
    Array(row.cells.map(\.plainText))
  })

  var text = headers.joined(separator: " │ ") + "\n"
  text += String(repeating: "─", count: min(text.count, 60)) + "\n"
  for row in rows {
    text += row.joined(separator: " │ ") + "\n"
  }

  return .component(
    key: key,
    RichCodeBlockComponent(code: text, language: nil)
  )
}

// MARK: - Rich Code Block

struct RichCodeBlockComponent: Component, Equatable {
  let code: String
  let language: String?

  func body() -> Node {
    return Node.vstack(spacing: 4) {
      if let language, !language.isEmpty {
        IdentifiedNode.drawing(
          key: "lang",
          TextDrawing(
            attributedString: makeMonoAttributedString(
              language,
              fontSize: 10,
              color: SessionColors.secondaryTextColor
            )
          )
        )
      }
      IdentifiedNode.drawing(
        key: "code",
        TextDrawing(
          attributedString: makeMonoAttributedString(
            code.hasSuffix("\n") ? String(code.dropLast()) : code,
            fontSize: 12,
            color: CGColor(gray: 0.15, alpha: 1)
          )
        )
      )
    }
    .padding(left: 12, top: 8, right: 12, bottom: 8)
    .viewModifier(BubbleBackground(color: CGColor(gray: 0.95, alpha: 1)))
  }
}

// MARK: - Inline Rendering (Rich)

private func renderInlinesRich(
  _ inlines: some Sequence<InlineMarkup>,
  baseFontSize: CGFloat,
  bold: Bool
) -> CFAttributedString {
  let result = NSMutableAttributedString()
  for inline in inlines {
    result.append(renderInlineRich(inline, baseFontSize: baseFontSize, inheritedBold: bold))
  }
  return result as CFAttributedString
}

private func renderInlineRich(
  _ inline: InlineMarkup,
  baseFontSize: CGFloat,
  inheritedBold: Bool
) -> NSAttributedString {
  switch inline {
  case let text as Markdown.Text:
    return NSAttributedString(
      string: text.string,
      attributes: textAttributes(fontSize: baseFontSize, bold: inheritedBold)
    )

  case let strong as Strong:
    let result = NSMutableAttributedString()
    for child in strong.inlineChildren {
      result.append(renderInlineRich(child, baseFontSize: baseFontSize, inheritedBold: true))
    }
    return result

  case let emphasis as Emphasis:
    let result = NSMutableAttributedString()
    for child in emphasis.inlineChildren {
      result.append(renderInlineRich(child, baseFontSize: baseFontSize, inheritedBold: inheritedBold))
    }
    result.addAttribute(
      .obliqueness,
      value: NSNumber(value: 0.2),
      range: NSRange(location: 0, length: result.length)
    )
    return result

  case let code as InlineCode:
    return NSAttributedString(
      string: code.code,
      attributes: monoAttributes(fontSize: baseFontSize * 0.9, color: CGColor(gray: 0.15, alpha: 1))
    )

  case let link as Markdown.Link:
    let result = NSMutableAttributedString()
    for child in link.inlineChildren {
      result.append(renderInlineRich(child, baseFontSize: baseFontSize, inheritedBold: inheritedBold))
    }
    if link.destination != nil {
      result.addAttribute(
        .foregroundColor,
        value: CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1),
        range: NSRange(location: 0, length: result.length)
      )
      result.addAttribute(
        .underlineStyle,
        value: NSNumber(value: NSUnderlineStyle.single.rawValue),
        range: NSRange(location: 0, length: result.length)
      )
    }
    return result

  case is SoftBreak:
    return NSAttributedString(
      string: " ",
      attributes: textAttributes(fontSize: baseFontSize, bold: inheritedBold)
    )

  case is LineBreak:
    return NSAttributedString(
      string: "\n",
      attributes: textAttributes(fontSize: baseFontSize, bold: inheritedBold)
    )

  case let strikethrough as Strikethrough:
    let result = NSMutableAttributedString()
    for child in strikethrough.inlineChildren {
      result.append(renderInlineRich(child, baseFontSize: baseFontSize, inheritedBold: inheritedBold))
    }
    result.addAttribute(
      .strikethroughStyle,
      value: NSNumber(value: NSUnderlineStyle.single.rawValue),
      range: NSRange(location: 0, length: result.length)
    )
    return result

  default:
    return NSAttributedString(
      string: inline.plainText,
      attributes: textAttributes(fontSize: baseFontSize, bold: inheritedBold)
    )
  }
}

// MARK: - Attributed String Factories

private func textAttributes(fontSize: CGFloat, bold: Bool) -> [NSAttributedString.Key: Any] {
  let fontName = bold ? "Helvetica-Bold" : "Helvetica"
  let font = CTFontCreateWithName(fontName as CFString, fontSize, nil)
  return [
    .font: font,
    .foregroundColor: CGColor(gray: 0.1, alpha: 1),
  ]
}

private func monoAttributes(fontSize: CGFloat, color: CGColor) -> [NSAttributedString.Key: Any] {
  let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
  return [
    .font: font,
    .foregroundColor: color,
  ]
}

private func makeHeaderAttributedString(
  author: String,
  timestamp: String,
  color: CGColor
) -> CFAttributedString {
  let result = NSMutableAttributedString()

  let authorFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
  result.append(NSAttributedString(
    string: author,
    attributes: [.font: authorFont, .foregroundColor: color]
  ))

  if !timestamp.isEmpty {
    let sepFont = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
    let gray = CGColor(gray: 0.55, alpha: 1)
    result.append(NSAttributedString(
      string: "  ·  ",
      attributes: [.font: sepFont, .foregroundColor: gray]
    ))
    result.append(NSAttributedString(
      string: timestamp,
      attributes: [.font: sepFont, .foregroundColor: gray]
    ))
  }

  return result as CFAttributedString
}

private func makeStreamingHeaderAttributedString() -> CFAttributedString {
  let result = NSMutableAttributedString()

  let authorFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
  result.append(NSAttributedString(
    string: "Agent",
    attributes: [.font: authorFont, .foregroundColor: SessionColors.assistantHeaderColor]
  ))

  let sepFont = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
  result.append(NSAttributedString(
    string: "  ▍ streaming…",
    attributes: [.font: sepFont, .foregroundColor: CGColor(gray: 0.55, alpha: 1)]
  ))

  return result as CFAttributedString
}

private func makeThinkingAttributedString() -> CFAttributedString {
  let result = NSMutableAttributedString()

  let authorFont = CTFontCreateWithName("Helvetica-Bold" as CFString, 12, nil)
  result.append(NSAttributedString(
    string: "Agent",
    attributes: [.font: authorFont, .foregroundColor: SessionColors.assistantHeaderColor]
  ))

  let sepFont = CTFontCreateWithName("Helvetica" as CFString, 11, nil)
  result.append(NSAttributedString(
    string: "  ⟳ Working…",
    attributes: [.font: sepFont, .foregroundColor: CGColor(gray: 0.55, alpha: 1)]
  ))

  return result as CFAttributedString
}

private func makeToolCallAttributedString(
  name: String,
  args: String,
  isExpanded: Bool,
  hasResult: Bool
) -> CFAttributedString {
  let result = NSMutableAttributedString()

  let labelFont = CTFontCreateWithName("Menlo" as CFString, 11, nil)

  // Disclosure indicator (if has result)
  if hasResult {
    let indicator = isExpanded ? "▾ " : "▸ "
    result.append(NSAttributedString(
      string: indicator,
      attributes: [.font: labelFont, .foregroundColor: SessionColors.secondaryTextColor]
    ))
  }

  // Gear icon
  result.append(NSAttributedString(
    string: "⚙ ",
    attributes: [.font: labelFont, .foregroundColor: SessionColors.toolCallNameColor]
  ))

  // Tool name
  let nameFont = CTFontCreateWithName("Menlo-Bold" as CFString, 11, nil)
  result.append(NSAttributedString(
    string: name,
    attributes: [.font: nameFont, .foregroundColor: CGColor(gray: 0.2, alpha: 1)]
  ))

  // Args (truncated)
  if !args.isEmpty {
    let truncatedArgs = String(args.prefix(80))
    let argsFont = CTFontCreateWithName("Menlo" as CFString, 10, nil)
    result.append(NSAttributedString(
      string: "  \(truncatedArgs)",
      attributes: [.font: argsFont, .foregroundColor: SessionColors.secondaryTextColor]
    ))
  }

  return result as CFAttributedString
}

private func makeMonoAttributedString(_ text: String, fontSize: CGFloat, color: CGColor) -> CFAttributedString {
  let font = CTFontCreateWithName("Menlo" as CFString, fontSize, nil)
  return NSAttributedString(
    string: text,
    attributes: [.font: font, .foregroundColor: color]
  ) as CFAttributedString
}

// MARK: - Helpers

private func plainTextFromMarkup(_ markup: Markup) -> String {
  if let markup = markup as? any PlainTextConvertibleMarkup {
    return markup.plainText
  }
  return Array(markup.children)
    .map(plainTextFromMarkup)
    .joined()
}

private extension Markup {
  var inlineChildren: [InlineMarkup] {
    children.compactMap { $0 as? InlineMarkup }
  }
}
