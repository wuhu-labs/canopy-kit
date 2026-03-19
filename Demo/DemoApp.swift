import SwiftUI

@main
struct WuhuUIDemoApp: App {
  var body: some Scene {
    WindowGroup {
      DemoRootView()
        .frame(minWidth: 720, minHeight: 540)
    }
  }
}

struct DemoRootView: View {
  @State private var selection: DemoKind? = .staticMarkdown

  var body: some View {
    NavigationSplitView {
      List(DemoKind.allCases, selection: $selection) { demo in
        Text(demo.title)
      }
      .navigationTitle("WuhuUI")
    } detail: {
      Group {
        switch selection ?? .staticMarkdown {
        case .staticMarkdown:
          StaticMarkdownDemoView()
        case .componentDocument:
          ComponentDocumentDemoView()
        case .reactiveFeed:
          ReactiveFeedDemoView()
        case .markdownStream:
          MarkdownStreamDemoView()
        }
      }
      .navigationTitle((selection ?? .staticMarkdown).title)
    }
  }
}

enum DemoKind: String, CaseIterable, Identifiable {
  case staticMarkdown
  case componentDocument
  case reactiveFeed
  case markdownStream

  var id: Self { self }

  var title: String {
    switch self {
    case .staticMarkdown:
      "Static Markdown"
    case .componentDocument:
      "Component Document"
    case .reactiveFeed:
      "Reactive Feed"
    case .markdownStream:
      "Markdown Stream"
    }
  }
}
