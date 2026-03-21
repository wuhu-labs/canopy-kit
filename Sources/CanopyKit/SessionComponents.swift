import CoreGraphics
import CoreText
import Foundation
import IdentifiedCollections
import Markdown
import Observation

#if canImport(AppKit)
import AppKit
#endif

// MARK: - Observable Models

/// Per-tool-call observable model. Holds mutable `isExpanded` state
/// so tapping a tool call only re-renders that one component.
@Observable
public final class ChatToolCallModel: Identifiable {
  public let id: String
  public var name: String
  public var arguments: String
  public var result: String
  public var isExpanded: Bool

  public init(
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
public struct ChatImageAttachment: Identifiable, Equatable, Sendable {
  public let id: String
  public var blobURI: String
  public var mimeType: String

  public init(id: String, blobURI: String, mimeType: String) {
    self.id = id
    self.blobURI = blobURI
    self.mimeType = mimeType
  }
}

/// Per-message observable model. Each message is its own observable
/// so mutations (e.g. streaming content append) only dirty that one
/// message's component — the root array is untouched.
@Observable
public final class ChatMessageModel: Identifiable {
  public let id: String
  public var role: Role
  public var author: String?
  public var content: String
  public var images: [ChatImageAttachment]
  public var timestamp: Date
  public var toolCalls: [ChatToolCallModel]

  public enum Role {
    case user
    case assistant
  }

  public init(
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
public final class ChatSessionModel {
  public var messages: [ChatMessageModel] = []
  public var streamingMessageID: String?
  public var isRunning: Bool = false

  public init() {}

  /// The message currently being streamed, if any.
  public var streamingMessage: ChatMessageModel? {
    guard let id = streamingMessageID else { return nil }
    return messages.last { $0.id == id }
  }

  /// Begin streaming: creates a new assistant message and marks it as
  /// the streaming target. Returns the model for direct mutation.
  @discardableResult
  public func beginStreaming(id: String = "__streaming-\(UUID().uuidString)") -> ChatMessageModel {
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
  public func finalizeStreaming() {
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
public struct SessionRootComponent: Component {
  public let model: ChatSessionModel

  public init(model: ChatSessionModel) {
    self.model = model
  }

  public func body() -> Node {
    let streamingID = model.streamingMessageID
    let isRunning = model.isRunning

    var children: [IdentifiedNode] = []

    for message in model.messages {
      let isStreaming = message.id == streamingID
      children.append(
        .component(
          key: message.id,
          AnyComponent(MessageComponent(
            model: message,
            isStreaming: isStreaming
          ))
        )
      )
    }

    // Thinking indicator: running but no streaming message yet
    if isRunning && streamingID == nil {
      children.append(
        .component(
          key: "__thinking",
          AnyComponent(ThinkingIndicatorComponent())
        )
      )
    }

    return .layout(
      AnyLayout(VStackLayout(spacing: 0)),
      children: IdentifiedArray(uniqueElements: children)
    )
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
    var children: [IdentifiedNode] = []

    // Header
    let author = model.author ?? "User"
    let timestamp = timestampFormatter.string(from: model.timestamp)
    children.append(
      .drawing(
        key: "header",
        AnyDrawing(TextDrawing(
          attributedString: makeHeaderAttributedString(
            author: author,
            timestamp: timestamp,
            color: SessionColors.userHeaderColor
          )
        ))
      )
    )

    // Bubble
    if !model.content.isEmpty {
      children.append(
        .layout(
          key: "bubble",
          AnyLayout(ZStackLayout()),
          children: [
            .drawing(
              key: "bg",
              AnyDrawing(RectDrawing(
                color: SessionColors.userBubbleBackground,
                height: 0
              ))
            ),
            .layout(
              key: "text-inset",
              AnyLayout(InsetLayout(left: 10, top: 8, right: 10, bottom: 8)),
              children: [
                .drawing(
                  key: "text",
                  AnyDrawing(TextDrawing(model.content, fontSize: 14))
                ),
              ]
            ),
          ]
        )
      )
    }

    // Images
    for image in model.images {
      children.append(
        .component(
          key: "img-\(image.id)",
          AnyComponent(ImagePlaceholderComponent(
            label: "📎 Image: \(image.blobURI.split(separator: "/").last ?? "image")"
          ))
        )
      )
    }

    return .layout(
      AnyLayout(InsetLayout(left: 16, top: 12, right: 16, bottom: 12)),
      children: [
        .layout(
          key: "content",
          AnyLayout(VStackLayout(spacing: 6)),
          children: IdentifiedArray(uniqueElements: children)
        ),
      ]
    )
  }

  // MARK: - Assistant Body

  private func assistantBody(isStreaming: Bool) -> Node {
    var children: [IdentifiedNode] = []

    // Tool calls — each is its own observable component
    for tc in model.toolCalls {
      children.append(
        .component(
          key: "tc-\(tc.id)",
          AnyComponent(ToolCallComponent(model: tc))
        )
      )
    }


    return .layout(
      AnyLayout(InsetLayout(left: 16, top: 12, right: 16, bottom: 4)),
      children: [
        .layout(
          key: "content",
          AnyLayout(VStackLayout(spacing: 6)),
          children: IdentifiedArray(uniqueElements: children)
        ),
      ]
    )
  }
}

// MARK: - Thinking Indicator Component

struct ThinkingIndicatorComponent: Component {
  func body() -> Node {
    .layout(
      AnyLayout(InsetLayout(left: 16, top: 12, right: 16, bottom: 12)),
      children: [
        .drawing(
          key: "thinking",
          AnyDrawing(TextDrawing(
            attributedString: makeThinkingAttributedString()
          ))
        ),
      ]
    )
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
    var children: [IdentifiedNode] = []

    // Tool name + args header
    children.append(
      .drawing(
        key: "label",
        AnyDrawing(TextDrawing(
          attributedString: makeToolCallAttributedString(
            name: model.name,
            args: model.arguments,
            isExpanded: model.isExpanded,
            hasResult: !model.result.isEmpty
          )
        ))
      )
    )

    // Result — shown in full when expanded, truncated when collapsed
    if !model.result.isEmpty && model.isExpanded {
      children.append(
        .layout(
          key: "result-bg",
          AnyLayout(ZStackLayout()),
          children: [
            .drawing(
              key: "bg",
              AnyDrawing(RectDrawing(color: SessionColors.toolCallBackground, height: 0))
            ),
            .layout(
              key: "result-inset",
              AnyLayout(InsetLayout(left: 8, top: 6, right: 8, bottom: 6)),
              children: [
                .drawing(
                  key: "result-text",
                  AnyDrawing(TextDrawing(
                    attributedString: makeMonoAttributedString(
                      model.result,
                      fontSize: 11,
                      color: SessionColors.secondaryTextColor
                    )
                  ))
                ),
              ]
            ),
          ]
        )
      )
    }

    // Wrap in container with left accent bar
    return .layout(
      AnyLayout(ZStackLayout()),
      children: [
        // Left bar
        .layout(
          key: "bar",
          AnyLayout(FrameLayout(width: 2)),
          children: [
            .drawing(
              key: "bar-rect",
              AnyDrawing(RectDrawing(color: SessionColors.toolCallBorder, height: 0))
            ),
          ]
        ),
        // Content
        .layout(
          key: "tool-content",
          AnyLayout(InsetLayout(left: 10, top: 4, right: 0, bottom: 4)),
          children: [
            .layout(
              key: "tool-vstack",
              AnyLayout(VStackLayout(spacing: 4)),
              children: IdentifiedArray(uniqueElements: children)
            ),
          ]
        ),
      ]
    )
    .onTapGesture { [weak model] in
      model?.isExpanded.toggle()
    }
  }
}

// MARK: - Image Placeholder Component

struct ImagePlaceholderComponent: Component, Equatable {
  let label: String

  func body() -> Node {
    .layout(
      AnyLayout(ZStackLayout()),
      children: [
        .drawing(
          key: "bg",
          AnyDrawing(RectDrawing(color: SessionColors.imagePlaceholderColor, height: 60))
        ),
        .layout(
          key: "label-inset",
          AnyLayout(InsetLayout(left: 12, top: 20, right: 12, bottom: 20)),
          children: [
            .drawing(
              key: "label",
              AnyDrawing(TextDrawing(
                attributedString: makeMonoAttributedString(label, fontSize: 12, color: SessionColors.secondaryTextColor)
              ))
            ),
          ]
        ),
      ]
    )
  }
}

// MARK: - Rich Markdown Component

/// Parses markdown source into a CanopyKit tree with rich inline
/// rendering via NSAttributedString (bold, italic, code, links).
public struct RichMarkdownComponent: Component, Equatable {
  public var source: String

  public init(source: String) {
    self.source = source
  }

  public func body() -> Node {
    let document = Document(parsing: source)
    let blocks = Array(document.children)

    return .layout(
      AnyLayout(VStackLayout(spacing: 8)),
      children: IdentifiedArray(
        uniqueElements: blocks.enumerated().compactMap { index, block in
          richBlockNode(block, key: "block-\(index)")
        }
      )
    )
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
    return .drawing(
      key: key,
      AnyDrawing(TextDrawing(attributedString: attrString))
    )

  case let paragraph as Paragraph:
    let attrString = renderInlinesRich(paragraph.inlineChildren, baseFontSize: 14, bold: false)
    return .drawing(
      key: key,
      AnyDrawing(TextDrawing(attributedString: attrString))
    )

  case let codeBlock as CodeBlock:
    return .component(
      key: key,
      AnyComponent(RichCodeBlockComponent(
        code: codeBlock.code,
        language: codeBlock.language
      ))
    )

  case _ as ThematicBreak:
    return .drawing(
      key: key,
      AnyDrawing(RectDrawing(color: CGColor(gray: 0.8, alpha: 1), height: 1))
    )

  case let blockQuote as BlockQuote:
    let childNodes = Array(blockQuote.children).enumerated().compactMap { i, child in
      richBlockNode(child, key: "bq-\(i)")
    }
    guard !childNodes.isEmpty else { return nil }

    return .layout(
      key: key,
      AnyLayout(ZStackLayout()),
      children: [
        .layout(
          key: "bar",
          AnyLayout(FrameLayout(width: 3)),
          children: [
            .drawing(
              key: "rect",
              AnyDrawing(RectDrawing(color: CGColor(gray: 0.7, alpha: 1), height: 0))
            ),
          ]
        ),
        .layout(
          key: "content-inset",
          AnyLayout(InsetLayout(left: 13)),
          children: [
            .layout(
              key: "content",
              AnyLayout(VStackLayout(spacing: 6)),
              children: IdentifiedArray(uniqueElements: childNodes)
            ),
          ]
        ),
      ]
    )

  case let unorderedList as UnorderedList:
    let items = Array(unorderedList.listItems).enumerated().map { i, item in
      richListItemNode(item, marker: "•", key: "li-\(i)")
    }
    return .layout(
      key: key,
      AnyLayout(VStackLayout(spacing: 4)),
      children: IdentifiedArray(uniqueElements: items)
    )

  case let orderedList as OrderedList:
    let items = Array(orderedList.listItems).enumerated().map { i, item in
      richListItemNode(item, marker: "\(orderedList.startIndex + UInt(i)).", key: "li-\(i)")
    }
    return .layout(
      key: key,
      AnyLayout(VStackLayout(spacing: 4)),
      children: IdentifiedArray(uniqueElements: items)
    )

  case let table as Markdown.Table:
    return richTableNode(table, key: key)

  default:
    let text = plainTextFromMarkup(markup)
    guard !text.isEmpty else { return nil }
    return .drawing(
      key: key,
      AnyDrawing(TextDrawing(text, fontSize: 14))
    )
  }
}

private func richListItemNode(_ item: ListItem, marker: String, key: String) -> IdentifiedNode {
  let childNodes = Array(item.children).enumerated().compactMap { i, child in
    richBlockNode(child, key: "item-\(i)")
  }

  return .layout(
    key: key,
    AnyLayout(HStackLayout(spacing: 6)),
    children: [
      .drawing(
        key: "marker",
        AnyDrawing(TextDrawing(marker, fontSize: 14))
      ),
      .layout(
        key: "content",
        AnyLayout(VStackLayout(spacing: 4)),
        children: IdentifiedArray(uniqueElements: childNodes)
      ),
    ]
  )
}

private func richTableNode(_ table: Markdown.Table, key: String) -> IdentifiedNode {
  let headers = Array(table.head.cells.map { $0.plainText })
  let rows = Array(table.body.rows.map { row in
    Array(row.cells.map { $0.plainText })
  })

  var text = headers.joined(separator: " │ ") + "\n"
  text += String(repeating: "─", count: min(text.count, 60)) + "\n"
  for row in rows {
    text += row.joined(separator: " │ ") + "\n"
  }

  return .component(
    key: key,
    AnyComponent(RichCodeBlockComponent(code: text, language: nil))
  )
}

// MARK: - Rich Code Block

struct RichCodeBlockComponent: Component, Equatable {
  let code: String
  let language: String?

  func body() -> Node {
    var children: [IdentifiedNode] = []

    if let language, !language.isEmpty {
      children.append(
        .drawing(
          key: "lang",
          AnyDrawing(TextDrawing(
            attributedString: makeMonoAttributedString(
              language,
              fontSize: 10,
              color: SessionColors.secondaryTextColor
            )
          ))
        )
      )
    }

    children.append(
      .drawing(
        key: "code",
        AnyDrawing(TextDrawing(
          attributedString: makeMonoAttributedString(
            code.hasSuffix("\n") ? String(code.dropLast()) : code,
            fontSize: 12,
            color: CGColor(gray: 0.15, alpha: 1)
          )
        ))
      )
    )

    return .layout(
      AnyLayout(ZStackLayout()),
      children: [
        .drawing(
          key: "bg",
          AnyDrawing(RectDrawing(color: CGColor(gray: 0.95, alpha: 1), height: 0))
        ),
        .layout(
          key: "inset",
          AnyLayout(InsetLayout(left: 12, top: 8, right: 12, bottom: 8)),
          children: [
            .layout(
              key: "vstack",
              AnyLayout(VStackLayout(spacing: 4)),
              children: IdentifiedArray(uniqueElements: children)
            ),
          ]
        ),
      ]
    )
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
