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
  @State private var selection: DemoKind? = .directRenderTree

  var body: some View {
    NavigationSplitView {
      List(DemoKind.allCases, selection: $selection) { demo in
        Text(demo.title)
      }
      .navigationTitle("WuhuUI")
    } detail: {
      Group {
        switch selection ?? .directRenderTree {
        case .directRenderTree:
          DirectRenderTreeDemoView()
        case .componentDocument:
          ComponentDocumentDemoView()
        case .reactiveFeed:
          ReactiveFeedDemoView()
        case .markdownStream:
          MarkdownStreamDemoView()
        }
      }
      .navigationTitle((selection ?? .directRenderTree).title)
    }
  }
}

enum DemoKind: String, CaseIterable, Identifiable {
  case directRenderTree
  case componentDocument
  case reactiveFeed
  case markdownStream

  var id: Self { self }

  var title: String {
    switch self {
    case .directRenderTree:
      "Direct Render Tree"
    case .componentDocument:
      "Component Document"
    case .reactiveFeed:
      "Reactive Feed"
    case .markdownStream:
      "Markdown Stream"
    }
  }
}
