import CoreGraphics
import WuhuUI

let paragraphs: [String] = [
  "The system is designed around a small set of composable primitives. Each primitive handles exactly one concern, and they combine through well-defined interfaces.",
  "Measurements show that the bottleneck is almost always I/O, not CPU. The layout engine completes a full pass over 10,000 nodes in under 2ms on a single core.",
  "The layout algorithm is a single top-down pass. The parent proposes a width, each child reports its height, and the parent places children sequentially.",
  "Concurrency is handled through structured task groups. Each top-level operation spawns a task group, and child tasks inherit the parent's cancellation token.",
  "The test suite runs in under 10 seconds because every test operates on in-memory fixtures. Dependencies are replaced with lightweight fakes that record calls.",
  "Accessibility is not an afterthought. Every visual element in the render tree carries semantic metadata that can later feed a platform bridge.",
]

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

let staticMarkdownDocument = markdownStreamingPrelude + "\n\n" + streamingMarkdownChunk(index: 1)
