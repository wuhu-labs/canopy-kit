import CanopyKit
import IdentifiedCollections
import Observation
import SwiftUI

// MARK: - Static Markdown Demo

struct StaticMarkdownDemoView: View {
  var body: some View {
    ComponentTreeView(root: MarkdownDocumentComponent(source: staticMarkdownDocument))
  }
}

// MARK: - Reactive Feed Demo

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

      ComponentTreeView(root: ReactiveFeedComponent(model: model))
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

struct ReactiveFeedComponent: Component {
  let model: ReactiveFeedModel

  func body() -> Node {
    .layout(
      VStackLayout(spacing: 8),
      children: IdentifiedArray(
        uniqueElements: model.paragraphs.map { paragraph in
          IdentifiedNode.component(
            key: paragraph.id,
            ParagraphCardComponent(paragraph: paragraph)
          )
        }
      )
    )
  }
}

struct ParagraphCardComponent: Component, Equatable {
  let paragraph: ReactiveFeedModel.Paragraph

  func body() -> Node {
    .layout(
      VStackLayout(spacing: 6),
      children: [
        .drawing(
          key: "label",
          TextDrawing("Paragraph \(paragraph.id)", fontSize: 12)
        ),
        .drawing(
          key: "text",
          TextDrawing(paragraph.text, fontSize: 14)
        ),
        .layout(
          key: "rule",
          FrameLayout(height: 1),
          children: [
            .shape(
              key: "shape",
              Rectangle()
            ),
          ]
        ),
      ]
    )
  }
}

// MARK: - Markdown Stream Demo (Multi-Document)

/// A single markdown document being streamed character by character.
@Observable
final class DocumentModel: Identifiable {
  let id: Int
  @ObservationIgnored let fullCharacters: [Character]
  var visibleCharacterCount: Int
  var visibleMarkdown: String

  var isComplete: Bool {
    visibleCharacterCount >= fullCharacters.count
  }

  init(id: Int, markdown: String, prefillCount: Int = 0) {
    self.id = id
    fullCharacters = Array(markdown)
    let clamped = min(prefillCount, fullCharacters.count)
    visibleCharacterCount = clamped
    visibleMarkdown = String(fullCharacters.prefix(clamped))
  }

  /// Append the next batch of characters. Returns true if the document just completed.
  func advance(count: Int = 5) -> Bool {
    guard !isComplete else { return false }
    let end = min(visibleCharacterCount + count, fullCharacters.count)
    visibleMarkdown.append(contentsOf: fullCharacters[visibleCharacterCount ..< end])
    visibleCharacterCount = end
    return isComplete
  }
}

/// Top-level model: holds many documents, streams into the active one.
@Observable
final class AppModel {
  let totalDocumentCount: Int
  var documents: [DocumentModel] = []
  var isStreaming = false

  @ObservationIgnored private var nextDocumentIndex = 0

  init(documentCount: Int = 100) {
    totalDocumentCount = documentCount
    // Pre-fill a batch of completed documents to simulate history
    let prefillCount = max(0, documentCount - 5)
    for i in 0 ..< prefillCount {
      let markdown = makeDocumentMarkdown(index: i)
      let doc = DocumentModel(id: i, markdown: markdown, prefillCount: markdown.count)
      documents.append(doc)
    }
    // Create the first active document
    if prefillCount < documentCount {
      let doc = DocumentModel(id: prefillCount, markdown: makeDocumentMarkdown(index: prefillCount))
      documents.append(doc)
      nextDocumentIndex = prefillCount + 1
    } else {
      nextDocumentIndex = documentCount
    }
  }

  var activeDocument: DocumentModel? {
    documents.last { !$0.isComplete } ?? documents.last
  }

  var progressText: String {
    let completedDocs = documents.filter(\.isComplete).count
    let active = activeDocument
    let activeProgress = active.map { "\($0.visibleCharacterCount)/\($0.fullCharacters.count)" } ?? "done"
    return "Doc \(completedDocs)/\(totalDocumentCount) | Active: \(activeProgress)"
  }

  func startStreaming() {
    isStreaming = true
  }

  func pauseStreaming() {
    isStreaming = false
  }

  func reset() {
    pauseStreaming()
    // Reset all documents to prefilled state
    documents.removeAll()
    nextDocumentIndex = 0
    let prefillCount = max(0, totalDocumentCount - 5)
    for i in 0 ..< prefillCount {
      let markdown = makeDocumentMarkdown(index: i)
      let doc = DocumentModel(id: i, markdown: markdown, prefillCount: markdown.count)
      documents.append(doc)
    }
    if prefillCount < totalDocumentCount {
      let doc = DocumentModel(id: prefillCount, markdown: makeDocumentMarkdown(index: prefillCount))
      documents.append(doc)
      nextDocumentIndex = prefillCount + 1
    } else {
      nextDocumentIndex = totalDocumentCount
    }
  }

  /// Called every tick. Advances the active document; if it finishes, starts a new one.
  func tick() {
    guard isStreaming else { return }

    guard let active = documents.last, !active.isComplete else {
      // No active document or last one is complete — try to start a new one
      if nextDocumentIndex < totalDocumentCount {
        let doc = DocumentModel(id: nextDocumentIndex, markdown: makeDocumentMarkdown(index: nextDocumentIndex))
        documents.append(doc)
        nextDocumentIndex += 1
      } else {
        isStreaming = false
      }
      return
    }

    let justCompleted = active.advance(count: 5)
    if justCompleted, nextDocumentIndex < totalDocumentCount {
      // Document finished — start the next one. This mutates AppModel.documents.
      let doc = DocumentModel(id: nextDocumentIndex, markdown: makeDocumentMarkdown(index: nextDocumentIndex))
      documents.append(doc)
      nextDocumentIndex += 1
    } else if justCompleted {
      isStreaming = false
    }
  }
}

// MARK: - Multi-Document Components

/// Root component: observes AppModel, emits one child component per document.
struct MultiDocumentComponent: Component {
  let appModel: AppModel

  func body() -> Node {
    .layout(
      VStackLayout(spacing: 16),
      children: IdentifiedArray(
        uniqueElements: appModel.documents.map { doc in
          IdentifiedNode.component(
            key: doc.id,
            SingleDocumentComponent(document: doc)
          )
        }
      )
    )
  }
}

/// Per-document component: observes its DocumentModel's visibleMarkdown.
struct SingleDocumentComponent: Component {
  let document: DocumentModel

  func body() -> Node {
    MarkdownDocumentComponent(source: document.visibleMarkdown).body()
  }
}

// MARK: - Markdown Stream Demo View

struct MarkdownStreamDemoView: View {
  @State private var appModel: AppModel
  private let timer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

  init() {
    _appModel = State(initialValue: AppModel(documentCount: 100))
  }

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text(appModel.progressText)
        Spacer()
        Button(appModel.isStreaming ? "Pause" : "Start") { startPauseButtonTapped() }
        Button("Reset") { resetButtonTapped() }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      ComponentTreeView(root: MultiDocumentComponent(appModel: appModel))
      .autoScrollWhenHeightChanges()
    }
    .onReceive(timer) { _ in
      appModel.tick()
    }
    .task { appModel.startStreaming() }
  }

  private func startPauseButtonTapped() {
    if appModel.isStreaming {
      appModel.pauseStreaming()
    } else {
      appModel.startStreaming()
    }
  }

  private func resetButtonTapped() {
    appModel.reset()
    appModel.startStreaming()
  }
}
