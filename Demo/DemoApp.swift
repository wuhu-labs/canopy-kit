import SwiftUI

@main
struct CanopyKitDemoApp: App {
  var body: some Scene {
    WindowGroup {
      DemoRootView()
      #if os(macOS)
        .frame(minWidth: 720, minHeight: 540)
      #endif
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
      .navigationTitle("CanopyKit")
    } detail: {
      Group {
        switch selection ?? .staticMarkdown {
        case .staticMarkdown:
          StaticMarkdownDemoView()
        case .reactiveFeed:
          ReactiveFeedDemoView()
        case .markdownStream:
          MarkdownStreamDemoView()
        case .tapGesture:
          TapGestureDemoView()
        case .sessionView:
          SessionDemoView()
        }
      }
      .navigationTitle((selection ?? .staticMarkdown).title)
    }
  }
}

enum DemoKind: String, CaseIterable, Identifiable {
  case staticMarkdown
  case reactiveFeed
  case markdownStream
  case tapGesture
  case sessionView

  var id: Self {
    self
  }

  var title: String {
    switch self {
    case .staticMarkdown:
      "Static Markdown"
    case .reactiveFeed:
      "Reactive Feed"
    case .markdownStream:
      "Markdown Stream"
    case .tapGesture:
      "Tap Gesture"
    case .sessionView:
      "Session View"
    }
  }
}
