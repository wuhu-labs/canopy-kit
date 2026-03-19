import Observation
import SwiftUI
import WuhuUI

struct StaticMarkdownDemoView: View {
  var body: some View {
    ComponentTreeView(
      root: AnyComponent(MarkdownDocumentComponent(source: staticMarkdownDocument))
    )
  }
}

struct ComponentDocumentDemoView: View {
  var body: some View {
    ComponentTreeView(root: AnyComponent(StaticDocumentComponent()))
  }
}

struct StaticDocumentComponent: Component, Equatable {
  func body() -> ComponentBody {
    .layoutNode(
      key: "document",
      AnyLayout(VStackLayout(spacing: 10)),
      children: [
        .componentNode(key: "intro", AnyComponent(ArticleSectionComponent(
          title: "Explicit Layout Tree",
          bodyText: paragraphs[0],
          bullets: Array(bulletPoints.prefix(3))
        ))),
        .componentNode(key: "perf", AnyComponent(ArticleSectionComponent(
          title: "Cheap Enough Virtualization",
          bodyText: paragraphs[1],
          bullets: Array(bulletPoints.suffix(3))
        ))),
        .componentNode(key: "reactivity", AnyComponent(ArticleSectionComponent(
          title: "Component Expansion",
          bodyText: paragraphs[2],
          bullets: ["Observation marks components dirty", "Resolved tree stays immutable", "Render tree holds caches"]
        ))),
      ]
    )
  }
}

struct ArticleSectionComponent: Component, Equatable {
  let title: String
  let bodyText: String
  let bullets: [String]

  func body() -> ComponentBody {
    .layoutNode(
      key: "section",
      AnyLayout(VStackLayout(spacing: 6)),
      children: [
        .drawingNode(
          key: "title",
          AnyDrawing(TextDrawing(title, fontSize: 24))
        ),
        .drawingNode(
          key: "body",
          AnyDrawing(TextDrawing(bodyText, fontSize: 14))
        ),
        .layoutNode(
          key: "bullets",
          AnyLayout(VStackLayout(spacing: 4)),
          children: bullets.enumerated().map { offset, bullet in
            .componentNode(
              key: offset,
              AnyComponent(BulletRowComponent(text: bullet))
            )
          }
        ),
        .drawingNode(
          key: "separator",
          AnyDrawing(RectDrawing(color: CGColor(gray: 0.82, alpha: 1), height: 1))
        ),
      ]
    )
  }
}

struct BulletRowComponent: Component, Equatable {
  let text: String

  func body() -> ComponentBody {
    .layoutNode(
      key: "row",
      AnyLayout(InsetLayout(left: 16)),
      children: [
        .layoutNode(
          key: "content",
          AnyLayout(HStackLayout(spacing: 6)),
          children: [
            .drawingNode(key: "bullet", AnyDrawing(TextDrawing("•", fontSize: 14))),
            .drawingNode(key: "text", AnyDrawing(TextDrawing(text, fontSize: 14))),
          ]
        )
      ]
    )
  }
}

@Observable
final class ReactiveFeedModel {
  struct Paragraph: Identifiable, Equatable {
    let id: Int
    let text: String
  }

  var paragraphs: [Paragraph] = (0 ..< 12).map { index in
    Paragraph(id: index, text: demoParagraph(index: index))
  }
  var nextID = 12

  func appendParagraph() {
    paragraphs.append(Paragraph(id: nextID, text: demoParagraph(index: nextID)))
    nextID += 1
  }

  func removeHead() {
    guard !paragraphs.isEmpty else { return }
    paragraphs.removeFirst()
  }
}

struct ReactiveFeedDemoView: View {
  @State private var model = ReactiveFeedModel()

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("\(model.paragraphs.count) paragraphs")
        Spacer()
        Button("Add Tail") { addTailButtonTapped() }
        Button("Remove Head") { removeHeadButtonTapped() }
          .disabled(model.paragraphs.isEmpty)
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      ComponentTreeView(
        root: AnyComponent(
          ReactiveFeedComponent(model: model),
          isEquivalent: { lhs, rhs in lhs.model === rhs.model }
        )
      )
      .autoScrollWhenHeightChanges()
    }
  }

  private func addTailButtonTapped() {
    model.appendParagraph()
  }

  private func removeHeadButtonTapped() {
    model.removeHead()
  }
}

@Observable
final class MarkdownStreamModel {
  @ObservationIgnored private let fullMarkdownCharacters: [Character]
  @ObservationIgnored private let initialCharacterCount: Int

  var visibleMarkdown = ""
  var visibleCharacterCount = 0
  var isStreaming = false

  init(multiplier: Int = 100, initialCharacterCount: Int = 22000) {
    fullMarkdownCharacters = Array(makeStreamingMarkdownDocument(multiplier: multiplier))
    self.initialCharacterCount = min(initialCharacterCount, fullMarkdownCharacters.count)
    visibleCharacterCount = self.initialCharacterCount
    visibleMarkdown = String(fullMarkdownCharacters.prefix(self.initialCharacterCount))
  }

  var totalCharacterCount: Int {
    fullMarkdownCharacters.count
  }

  var progressText: String {
    "\(visibleCharacterCount) / \(totalCharacterCount) chars"
  }

  func startStreaming() {
    guard !isStreaming, visibleCharacterCount < totalCharacterCount else { return }
    isStreaming = true
  }

  func pauseStreaming() {
    isStreaming = false
  }

  func reset() {
    pauseStreaming()
    visibleCharacterCount = initialCharacterCount
    visibleMarkdown = String(fullMarkdownCharacters.prefix(initialCharacterCount))
  }

  func advanceOneCharacter() {
    guard isStreaming else { return }
    guard visibleCharacterCount < totalCharacterCount else {
      isStreaming = false
      return
    }

    visibleMarkdown.append(contentsOf: fullMarkdownCharacters[visibleCharacterCount..<visibleCharacterCount + 5])
    visibleCharacterCount += 5

    if visibleCharacterCount == totalCharacterCount {
      isStreaming = false
    }
  }
}

struct MarkdownStreamDemoView: View {
  @State private var model: MarkdownStreamModel
  @State private var renderer: ComponentRenderer
  private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

  init() {
    let model = MarkdownStreamModel()
    _model = State(initialValue: model)
    _renderer = State(
      initialValue: ComponentRenderer(
        root: AnyComponent(
          StreamingMarkdownComponent(model: model),
          isEquivalent: { lhs, rhs in lhs.model === rhs.model }
        )
      )
    )
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(model.progressText)
        Spacer()
        Button(model.isStreaming ? "Pause" : "Start") { startPauseButtonTapped() }
        Button("Reset") { resetButtonTapped() }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      RenderTreeView(root: renderer.renderRoot, revision: renderer.revision)
        .autoScrollWhenHeightChanges()
    }
    .onReceive(timer) { _ in
      model.advanceOneCharacter()
    }
    .task { model.startStreaming() }
  }

  private func startPauseButtonTapped() {
    if model.isStreaming {
      model.pauseStreaming()
    } else {
      model.startStreaming()
    }
  }

  private func resetButtonTapped() {
    model.reset()
    model.startStreaming()
  }
}

struct StreamingMarkdownComponent: Component {
  let model: MarkdownStreamModel

  func body() -> ComponentBody {
    MarkdownDocumentComponent(source: model.visibleMarkdown).body()
  }
}

struct ReactiveFeedComponent: Component {
  let model: ReactiveFeedModel

  func body() -> ComponentBody {
    .layoutNode(
      key: "feed",
      AnyLayout(VStackLayout(spacing: 8)),
      children: model.paragraphs.map { paragraph in
        .componentNode(
          key: paragraph.id,
          AnyComponent(ParagraphCardComponent(paragraph: paragraph))
        )
      }
    )
  }
}

struct ParagraphCardComponent: Component, Equatable {
  let paragraph: ReactiveFeedModel.Paragraph

  func body() -> ComponentBody {
    .layoutNode(
      key: "card",
      AnyLayout(VStackLayout(spacing: 6)),
      children: [
        .drawingNode(
          key: "label",
          AnyDrawing(TextDrawing("Paragraph \(paragraph.id)", fontSize: 12))
        ),
        .drawingNode(
          key: "text",
          AnyDrawing(TextDrawing(paragraph.text, fontSize: 14))
        ),
        .drawingNode(
          key: "rule",
          AnyDrawing(RectDrawing(color: CGColor(gray: 0.88, alpha: 1), height: 1))
        ),
      ]
    )
  }
}
