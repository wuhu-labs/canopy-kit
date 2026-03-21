import CanopyKit
import IdentifiedCollections
import Observation
import SwiftUI

// MARK: - Streaming Controller

@MainActor
@Observable
final class StreamingController {
  var charIndex = 0
  let fullText: String
  var isActive = false

  init(fullText: String) {
    self.fullText = fullText
  }

  func advance(count: Int = 3) -> String? {
    guard isActive else { return nil }
    let charsToAdd = min(count, fullText.count - charIndex)
    guard charsToAdd > 0 else {
      isActive = false
      return nil
    }
    let start = fullText.index(fullText.startIndex, offsetBy: charIndex)
    let end = fullText.index(start, offsetBy: charsToAdd)
    charIndex += charsToAdd
    return String(fullText[start ..< end])
  }

  func reset() {
    charIndex = 0
    isActive = false
  }
}

// MARK: - Session Demo View

struct SessionDemoView: View {
  @State private var model = makeMockSessionModel()
  @State private var streamController = StreamingController(fullText: streamingDemoText)
  @State private var streamingMessage: ChatMessageModel?
  private let timer = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

  var body: some View {
    VStack(spacing: 0) {
      // Status bar
      HStack(spacing: 12) {
        Circle()
          .fill(model.isRunning ? .green : .gray)
          .frame(width: 8, height: 8)
        Text("CanopyKit Session PoC")
          .font(.headline)
        Spacer()
        Text("\(model.messages.count) messages")
          .font(.caption)
          .foregroundStyle(.secondary)
        Button(model.isRunning ? "Stop Streaming" : "Start Streaming") {
          toggleStreaming()
        }
        Button("Add User Msg") {
          addUserMessage()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.bar)

      Divider()

      ComponentTreeView(
        root: AnyComponent(
          SessionRootComponent(model: model),
          isEquivalent: { lhs, rhs in lhs.model === rhs.model }
        )
      )
      .autoScrollWhenHeightChanges(model.streamingMessageID != nil)
    }
    .frame(maxWidth: 800)
    .onReceive(timer) { _ in
      tickStreaming()
    }
  }

  private func toggleStreaming() {
    if model.isRunning {
      finalizeStreaming()
    } else {
      streamController.reset()
      streamController.isActive = true
      let msg = model.beginStreaming()
      streamingMessage = msg
    }
  }

  private func tickStreaming() {
    guard streamController.isActive, let msg = streamingMessage else { return }

    if let chars = streamController.advance() {
      // Mutate the message model directly — only its component re-renders
      msg.content.append(chars)
    } else {
      finalizeStreaming()
    }
  }

  private func finalizeStreaming() {
    model.finalizeStreaming()
    streamController.isActive = false
    streamingMessage = nil
  }

  private func addUserMessage() {
    let userTexts = [
      "Can you help me refactor this module?",
      "What's the performance impact of this change?",
      "Show me the test coverage for this file.",
      "Let's add error handling to the network layer.",
      "Can you explain how the layout algorithm works?",
    ]
    let msg = ChatMessageModel(
      id: "user-\(model.messages.count)-\(Int(Date().timeIntervalSince1970))",
      role: .user,
      author: "Minsheng",
      content: userTexts[model.messages.count % userTexts.count],
      timestamp: Date()
    )
    model.messages.append(msg)
  }
}

// MARK: - Mock Data

@MainActor
private func makeMockSessionModel() -> ChatSessionModel {
  let now = Date()
  let model = ChatSessionModel()

  model.messages = [

    ChatMessageModel(
      id: "msg-2",
      role: .assistant,
      content: """
      # Session View Architecture
      """,
      timestamp: now.addingTimeInterval(-240),
      toolCalls: [
        ChatToolCallModel(
          id: "tc-1",
          name: "read",
          arguments: "{\"path\": \"canopy-kit/Sources/CanopyKit/Components.swift\"}",
          result: "// CanopyKit components...\npublic protocol Component {\n  func body() -> Node\n}\n\npublic struct Node {\n  public var content: NodeContent\n  public var values: NodeValues\n}\n// ... 400 more lines"
        )
      ]
    ),
  ]

  return model
}

// MARK: - Streaming Demo Text

private let streamingDemoText = """
## Streaming Response

Let me walk through the implementation details step by step.

### Component Identity

The key insight is that each message gets a **stable component key** based on its `id`. This means:

1. When a new message arrives, only the new `IdentifiedNode` is added
2. Existing components are pointer-compared and skipped if unchanged
3. The `ComponentRenderer` tracks observation per-component, so only the *changed* component's body is re-evaluated

### Performance Characteristics

The rendering pipeline is:

```
Model change → Observation notification → Component body() → Reconciliation → Layout → Viewport projection → SwiftUI render
```

Each step is incremental:
- **Observation**: Only the observing component is marked dirty
- **Reconciliation**: Reference equality checks skip unchanged subtrees
- **Layout**: Cached measurements avoid redundant work
- **Viewport**: Off-screen nodes are never materialized into SwiftUI views

> This is fundamentally different from the `DocView` approach where the entire
> document must be re-diffed on every change. With CanopyKit, the diff is
> structural and O(1) for unchanged components.

### What's Next

- Add image rendering primitive to CanopyKit
- Add interactive state (tap to expand tool calls)
- Wire up the real `SessionFeature` state
"""

// MARK: - Preview

#Preview {
  SessionDemoView()
    .frame(width: 800, height: 700)
}
