import CanopyKit
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

      ComponentTreeView(root: SessionRootComponent(model: model))
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
      id: "msg-1",
      role: .user,
      author: "Minsheng",
      content: "Can you help me build a CanopyKit-based session view? I want to replace the current WuhuDocView-backed chat UI with something that uses the reactive component tree for better incremental updates.",
      timestamp: now.addingTimeInterval(-300)
    ),

    ChatMessageModel(
      id: "msg-2",
      role: .assistant,
      content: """
      # Session View Architecture

      Sure! Here's what I'm thinking for the **component tree structure**:

      1. Each **user message** becomes a `UserMessageComponent`
      2. Each **assistant message** becomes an `AssistantMessageComponent`
      3. The **streaming section** is a separate component that appears/disappears

      ## Key Benefits

      - Stable component references mean *only changed messages re-render*
      - The `@Observable` model provides fine-grained observation tracking
      - CanopyKit's viewport culling means off-screen messages are essentially free

      > The main challenge is that CanopyKit doesn't have interactive widgets like
      > `DisclosureGroup` or `ProgressView`. We'll need to use text-based
      > alternatives for now.

      Here's a rough outline of the component:

      ```swift
      struct SessionRootComponent: Component {
        let model: ChatSessionModel

        func body() -> Node {
          Canopy.VStack(spacing: 0) {
            for msg in model.messages {
              MessageComponent(...).id(msg.id)
            }
          }
        }
      }
      ```

      The explicit `.id(msg.id)` ensures each message maintains its identity across re-renders.
      """,
      timestamp: now.addingTimeInterval(-240),
      toolCalls: [
        ChatToolCallModel(
          id: "tc-1",
          name: "read",
          arguments: "{\"path\": \"canopy-kit/Sources/CanopyKit/Components.swift\"}",
          result: "// CanopyKit components...\npublic protocol Component {\n  func body() -> Node\n}\n\npublic struct Node {\n  public var content: NodeContent\n  public var values: NodeValues\n}\n// ... 400 more lines"
        ),
        ChatToolCallModel(
          id: "tc-2",
          name: "write",
          arguments: "{\"path\": \"SessionComponents.swift\"}",
          result: "Successfully wrote 15000 bytes to SessionComponents.swift"
        ),
      ]
    ),

    ChatMessageModel(
      id: "msg-3",
      role: .user,
      author: "Minsheng",
      content: "That looks great! What about tool calls and images?",
      timestamp: now.addingTimeInterval(-180)
    ),

    ChatMessageModel(
      id: "msg-4",
      role: .assistant,
      content: """
      Good question! Here's how I'm handling those:

      ### Tool Calls
      Tool calls are rendered as compact blocks with:
      - A **left accent bar** (like a blockquote) for visual grouping
      - The tool name in `monospace` with an ⚙ icon
      - **Tap to expand/collapse** the result — try clicking the tool calls above!

      ### Images
      Images can't be rendered yet — CanopyKit has no image primitive. I'm showing a **placeholder block** with the blob URI.

      ### Things That Can't Work Yet

      | Feature | Status | Notes |
      |---------|--------|-------|
      | Bold/Italic | ✅ Works | Via `NSAttributedString` |
      | Code blocks | ✅ Works | Monospace + background |
      | Tool call toggle | ✅ Works | Tap gesture + observable model |
      | Links | ⚠️ Visual only | Colored+underlined, not clickable |
      | Images | ❌ Placeholder | Need image primitive |
      | Animations | ❌ N/A | No animation primitives |
      """,
      timestamp: now.addingTimeInterval(-120),
      toolCalls: [
        ChatToolCallModel(
          id: "tc-3",
          name: "bash",
          arguments: "{\"command\": \"swift build 2>&1\"}",
          result: "Building for debugging...\n[1/5] Compiling CanopyKit SessionComponents.swift\n[2/5] Compiling CanopyKit Components.swift\n[3/5] Compiling CanopyKit RenderRuntime.swift\n[4/5] Emitting module CanopyKit\n[5/5] Linking CanopyKitTests\nBuild complete! (14.23s)"
        ),
      ]
    ),

    ChatMessageModel(
      id: "msg-5",
      role: .user,
      author: "Minsheng",
      content: "Here's a screenshot of the current UI for reference:",
      images: [
        ChatImageAttachment(
          id: "img-1",
          blobURI: "blob://session-123/screenshot.png",
          mimeType: "image/png"
        ),
      ],
      timestamp: now.addingTimeInterval(-60)
    ),

    ChatMessageModel(
      id: "msg-6",
      role: .assistant,
      content: """
      I can see the screenshot reference. The current UI has a clean layout with:

      - Status bar at the top
      - Chat thread with `DocView`
      - Input field at the bottom

      The CanopyKit version will maintain the same *visual structure* but with much better **incremental update performance**. Each message being its own component means when a new message arrives, only the new component needs to be resolved — everything else is pointer-equal and skipped.

      Let me know if you want me to proceed with the implementation!
      """,
      timestamp: now.addingTimeInterval(-30)
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
