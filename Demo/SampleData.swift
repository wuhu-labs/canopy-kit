import CoreGraphics
import WuhuUI

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
]

let paragraphs: [String] = [
  "The system is designed around a small set of composable primitives. Each primitive handles exactly one concern, and they combine through well-defined interfaces.",
  "Measurements show that the bottleneck is almost always I/O, not CPU. The layout engine completes a full pass over 10,000 nodes in under 2ms on a single core.",
  "The layout algorithm is a single top-down pass. The parent proposes a width, each child reports its height, and the parent places children sequentially.",
  "Concurrency is handled through structured task groups. Each top-level operation spawns a task group, and child tasks inherit the parent's cancellation token.",
  "The test suite runs in under 10 seconds because every test operates on in-memory fixtures. Dependencies are replaced with lightweight fakes that record calls.",
  "Accessibility is not an afterthought. Every visual element in the render tree carries semantic metadata that can later feed a platform bridge.",
]

let bulletPoints: [String] = [
  "Supports macOS 14 and later",
  "CoreText handles text measurement and rendering",
  "Visible set is recomputed on every scroll event",
  "Memory scales with viewport size, not document size",
  "Layout protocol is open for extension",
  "Width proposal flows top-down, size flows bottom-up",
]

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

enum BlockKind: CaseIterable {
  case h1
  case h2
  case body
  case bulletList
  case separator
}

func buildMarkdownRenderTree(blockCount: Int = 700) -> RenderNode {
  var rng = SeededRNG(seed: 42)
  var children: [RenderNode] = []

  func pickBlock(_ index: Int) -> BlockKind {
    if index % 50 == 0 { return .h1 }
    if index % 20 == 0 { return .h2 }

    let roll = Int.random(in: 0 ..< 10, using: &rng)
    switch roll {
    case 0 ..< 6: return .body
    case 6 ..< 8: return .bulletList
    default: return .separator
    }
  }

  for index in 0 ..< blockCount {
    switch pickBlock(index) {
    case .h1:
      children.append(renderSpacer(20))
      children.append(
        .leaf(
          AnyDrawing(TextDrawing(headings.randomElement(using: &rng)!, fontSize: 28))
        )
      )

    case .h2:
      children.append(renderSpacer(12))
      children.append(
        .leaf(
          AnyDrawing(TextDrawing(subheadings.randomElement(using: &rng)!, fontSize: 20))
        )
      )

    case .body:
      children.append(
        .leaf(
          AnyDrawing(TextDrawing(paragraphs.randomElement(using: &rng)!, fontSize: 14))
        )
      )

    case .bulletList:
      let count = Int.random(in: 3 ... 5, using: &rng)
      for _ in 0 ..< count {
        let bullet = RenderNode.leaf(AnyDrawing(TextDrawing("•", fontSize: 14)))
        let text = RenderNode.leaf(
          AnyDrawing(TextDrawing(bulletPoints.randomElement(using: &rng)!, fontSize: 14))
        )
        let row = RenderNode.container(AnyLayout(HStackLayout(spacing: 6)), [bullet, text])
        children.append(
          .container(AnyLayout(InsetLayout(left: 16)), [row])
        )
      }

    case .separator:
      children.append(renderSpacer(8))
      children.append(
        .leaf(
          AnyDrawing(RectDrawing(color: CGColor(gray: 0.8, alpha: 1), height: 1))
        )
      )
      children.append(renderSpacer(8))
    }
  }

  return .container(AnyLayout(VStackLayout(spacing: 4)), children)
}

func renderSpacer(_ height: CGFloat) -> RenderNode {
  .leaf(AnyDrawing(RectDrawing(color: CGColor(gray: 1, alpha: 0), height: height)))
}

func demoParagraph(index: Int) -> String {
  paragraphs[index % paragraphs.count]
}

func streamingMarkdownChunk(index: Int) -> String {
  """
  ## Update \(index)

  \(demoParagraph(index: index))

  - Bullet \(index).1
  - Bullet \(index).2

  > Quoted thought \(index)
  >
  > - nested quote item \(index).a
  > - nested quote item \(index).b
  >
  > \(demoParagraph(index: index + 1))
  """
}

let markdownStreamingPrelude = """
# Streaming Markdown

This demo parses real Markdown into the component tree.

> A block quote is a real node.
>
> - It can hold a nested list.
> - It can keep growing as content streams in.
"""

func makeStreamingMarkdownDocument(multiplier: Int) -> String {
  let body = (1 ... multiplier)
    .map { streamingMarkdownChunk(index: $0) }
    .joined(separator: "\n\n")

  return markdownStreamingPrelude + "\n\n" + body
}
