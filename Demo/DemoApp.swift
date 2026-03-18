import SwiftUI
import WuhuUI

// MARK: - Content Pools

let headings: [String] = [
  "Introduction to the System",
  "Architecture Overview",
  "Getting Started",
  "Core Concepts",
  "Advanced Configuration",
  "Performance Tuning",
  "Security Considerations",
  "Deployment Guide",
  "Troubleshooting",
  "API Reference",
  "Data Model Design",
  "Concurrency and Threading",
  "Networking Layer",
  "Storage and Persistence",
  "Plugin Architecture",
  "Error Handling Patterns",
  "Testing Strategies",
  "Migration Guide",
  "Accessibility",
  "Internationalization",
]

let subheadings: [String] = [
  "Overview",
  "Prerequisites",
  "Configuration Options",
  "Usage Examples",
  "Common Pitfalls",
  "Best Practices",
  "Implementation Details",
  "Performance Characteristics",
  "Thread Safety",
  "Memory Management",
  "Key Interfaces",
  "Extension Points",
  "Serialization Format",
  "Caching Strategy",
  "Rate Limiting",
  "Retry Policies",
  "Monitoring and Alerts",
  "Log Levels",
  "Feature Flags",
  "Backward Compatibility",
]

let paragraphs: [String] = [
  "The system is designed around a small set of composable primitives. Each primitive handles exactly one concern, and they combine through well-defined interfaces. This keeps the codebase modular and easy to reason about in isolation.",
  "When a request arrives, it passes through a pipeline of middleware stages. Each stage can inspect, transform, or short-circuit the request. The pipeline is configured at startup and cannot be modified at runtime, which eliminates an entire class of concurrency bugs.",
  "Measurements show that the bottleneck is almost always I/O, not CPU. The layout engine completes a full pass over 10,000 nodes in under 2ms on a single core. By contrast, a single network round-trip to the database takes 5-15ms.",
  "Error handling follows a simple rule: functions that can fail return a Result. Functions that indicate programmer error call preconditionFailure. There are no throws in the core library — all error propagation is explicit and typed.",
  "The cache uses a two-level strategy. Hot data lives in an in-memory LRU cache sized to fit in L2. Cold data spills to a memory-mapped file that the OS can page out. This gives us sub-microsecond reads for the common case without unbounded memory growth.",
  "Each module declares its dependencies as protocol requirements. The dependency injection container resolves these at app launch, and the resolved instances are immutable for the lifetime of the process. This makes the dependency graph easy to visualize and test.",
  "Strings are stored as UTF-8 throughout the pipeline. We never convert to UTF-16 except at the CoreText boundary, and even there we use CFStringCreateWithBytesNoCopy to avoid allocation. This halves memory usage for ASCII-heavy workloads.",
  "The layout algorithm is a single top-down pass. The parent proposes a width, each child reports its height, and the parent places children sequentially. There is no negotiation, no intrinsic content size queries, and no second pass. This is what makes it fast.",
  "Concurrency is handled through structured task groups. Each top-level operation spawns a task group, and child tasks inherit the parent's cancellation token. When the user navigates away, cancellation propagates automatically to all in-flight work.",
  "The plugin system exposes a narrow protocol with three methods: activate, handle, and deactivate. Plugins cannot access internal state directly — they communicate through an event bus. This keeps the core stable even when third-party plugins misbehave.",
  "We chose SQLite over a client-server database for several reasons. It requires no daemon process, supports concurrent readers with WAL mode, and its file format is stable across decades. For our access patterns — many reads, few writes — it is optimal.",
  "The test suite runs in under 10 seconds because every test operates on in-memory fixtures. No network, no disk, no file system. Dependencies are replaced with lightweight fakes that record calls for assertion. This also makes tests deterministic.",
  "Accessibility is not an afterthought. Every visual element in the render tree carries semantic metadata: role, label, value, and available actions. The accessibility bridge reads this metadata and exposes it to VoiceOver without any special-casing.",
  "Internationalization uses a compile-time approach. String keys are generated from a YAML file, and the compiler verifies that every key has a translation in every supported locale. Missing translations are a build error, not a runtime surprise.",
  "The animation system is intentionally minimal. It supports linear interpolation between two states over a fixed duration. No springs, no keyframes, no gesture-driven animations. When we need those, we drop down to Core Animation directly.",
  "Log output is structured JSON. Each log entry includes a timestamp, severity, module name, and a dictionary of typed fields. This makes logs trivially parseable by any observability tool without custom parsing rules.",
  "Version upgrades follow a strict protocol. The new binary reads the old data format, migrates it in a background task, and writes a version marker. If the migration fails, the old binary can still read the data. There is always a rollback path.",
  "Memory is managed through a region-based allocator for short-lived objects. A layout pass allocates into a bump region, and the entire region is freed in one operation when the pass completes. This eliminates thousands of individual deallocations.",
  "The networking layer retries failed requests with exponential backoff and jitter. It distinguishes between transient errors (retry) and permanent errors (fail fast). Circuit breakers prevent cascading failures when a downstream service is unhealthy.",
  "Configuration is loaded from a single TOML file at startup. There are no environment variable overrides, no command-line flags, no runtime configuration endpoints. One file, one source of truth, validated at startup with clear error messages.",
]

let bulletPoints: [String] = [
  "Supports macOS 14 and later",
  "Requires Xcode 16 or newer for building",
  "All layout computations are performed on the main thread",
  "CoreText handles text measurement and rendering",
  "Nodes are reference types for identity-based tracking",
  "The frame table is flat — no nested coordinate spaces",
  "Cache invalidation propagates upward to ancestors",
  "Visible set is recomputed on every scroll event",
  "Memory scales with viewport size, not document size",
  "Parallel measurement is possible because CoreText is thread-safe",
  "No CSS, no cascade, no inherited styles",
  "Layout protocol is open for extension",
  "Each leaf draws into its own CGContext region",
  "Separators are thin RectDrawing nodes",
  "The tree structure mirrors the document structure",
  "Scroll offset drives viewport culling",
  "Identity is based on ObjectIdentifier of the node",
  "Type erasure keeps the node enum small",
  "Width proposal flows top-down, size flows bottom-up",
  "No retained CTLine objects for off-screen content",
]

// MARK: - Seeded RNG

struct SeededRNG: RandomNumberGenerator {
  var state: UInt64
  init(seed: UInt64) {
    state = seed
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}

// MARK: - Tree Builder

enum BlockKind: CaseIterable {
  case h1, h2, h3, body, bulletList, separator
}

func buildMarkdownTree() -> RenderNode {
  var rng = SeededRNG(seed: 42)
  var children: [RenderNode] = []

  /// Weighted distribution: body-heavy, with periodic headings and lists
  func pickBlock(_ index: Int) -> BlockKind {
    // Every ~50 blocks, insert an H1
    if index % 50 == 0 { return .h1 }
    // Every ~20 blocks, insert an H2
    if index % 20 == 0 { return .h2 }
    // Every ~10 blocks, insert an H3
    if index % 10 == 0 { return .h3 }

    let roll = Int.random(in: 0 ..< 10, using: &rng)
    switch roll {
    case 0 ..< 6: return .body
    case 6 ..< 8: return .bulletList
    case 8: return .separator
    default: return .body
    }
  }

  for i in 0 ..< 1000 {
    let kind = pickBlock(i)

    switch kind {
    case .h1:
      let text = headings[Int.random(in: 0 ..< headings.count, using: &rng)]
      children.append(spacer(20))
      children.append(RenderNode.leaf(AnyDrawing(TextDrawing(text, fontSize: 28))))
      children.append(
        RenderNode.leaf(AnyDrawing(RectDrawing(color: CGColor(gray: 0.3, alpha: 1), height: 2)))
      )

    case .h2:
      let text = subheadings[Int.random(in: 0 ..< subheadings.count, using: &rng)]
      children.append(spacer(16))
      children.append(RenderNode.leaf(AnyDrawing(TextDrawing(text, fontSize: 22))))

    case .h3:
      let text = subheadings[Int.random(in: 0 ..< subheadings.count, using: &rng)]
      children.append(spacer(12))
      children.append(RenderNode.leaf(AnyDrawing(TextDrawing(text, fontSize: 18))))

    case .body:
      let text = paragraphs[Int.random(in: 0 ..< paragraphs.count, using: &rng)]
      children.append(RenderNode.leaf(AnyDrawing(TextDrawing(text, fontSize: 14))))

    case .bulletList:
      let count = Int.random(in: 3 ... 6, using: &rng)
      for _ in 0 ..< count {
        let text = bulletPoints[Int.random(in: 0 ..< bulletPoints.count, using: &rng)]
        let bullet = RenderNode.leaf(AnyDrawing(TextDrawing("•", fontSize: 14)))
        let body = RenderNode.leaf(AnyDrawing(TextDrawing(text, fontSize: 14)))
        let row = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, body])
        let indented = RenderNode.container(AnyLayout(InsetLayout(left: 16)), [row])
        children.append(indented)
      }

    case .separator:
      children.append(spacer(8))
      children.append(
        RenderNode.leaf(AnyDrawing(RectDrawing(color: CGColor(gray: 0.8, alpha: 1), height: 1)))
      )
      children.append(spacer(8))
    }
  }

  return RenderNode.container(AnyLayout(VStackLayout(spacing: 4)), children)
}

func spacer(_ height: CGFloat) -> RenderNode {
  RenderNode.leaf(AnyDrawing(RectDrawing(color: CGColor(gray: 1, alpha: 0), height: height)))
}

// MARK: - Render Tree View

struct RenderTreeView: View {
  let root: RenderNode

  var body: some View {
    GeometryReader { outerGeo in
      ScrollView {
        GeometryReader { innerGeo in
          let innerFrame = innerGeo.frame(in: .named("scroll"))
          let visibleRect = CGRect(
            x: 0,
            y: -innerFrame.origin.y,
            width: outerGeo.size.width,
            height: outerGeo.size.height
          )

          ForEach(visibleNodes(visibleRect: visibleRect), id: \.id) { entry in
            DrawingCanvas(node: entry.node)
              .frame(width: entry.frame.width, height: entry.frame.height)
              .offset(x: entry.frame.origin.x, y: entry.frame.origin.y)
          }
        }
        .frame(height: contentHeight(width: outerGeo.size.width))
      }
      .coordinateSpace(name: "scroll")
    }
  }

  private func contentHeight(width: CGFloat) -> CGFloat {
    guard width > 0 else { return 0 }
    root.layoutPass(width: width)
    return root.cachedSize?.height ?? 0
  }

  private func visibleNodes(visibleRect: CGRect) -> [VisibleEntry] {
    let width = visibleRect.width
    guard width > 0 else { return [] }
    root.layoutPass(width: width)
    root.assignFrames(origin: .zero)

    let leaves = root.visibleLeaves(in: visibleRect)
    return leaves.map { node in
      VisibleEntry(node: node, frame: node.frame)
    }
  }
}

struct VisibleEntry: Identifiable {
  var id: ObjectIdentifier {
    ObjectIdentifier(node)
  }

  let node: RenderNode
  let frame: CGRect
}

// MARK: - Canvas that draws via AnyDrawing

struct DrawingCanvas: View {
  let node: RenderNode

  var body: some View {
    Canvas { context, size in
      guard case var .leaf(drawing) = node.content else { return }
      context.withCGContext { cgContext in
        drawing.draw(in: cgContext, bounds: CGRect(origin: .zero, size: size))
      }
      node.content = .leaf(drawing)
    }
  }
}

// MARK: - App

@main
struct WuhuUIDemoApp: App {
  let root = buildMarkdownTree()

  var body: some Scene {
    WindowGroup {
      RenderTreeView(root: root)
        .frame(minWidth: 400, minHeight: 400)
    }
  }
}
