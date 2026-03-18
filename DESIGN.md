# WuhuUI — Custom Document Layout Engine

A minimal, high-performance document rendering engine for wuhu. Replaces NSCollectionView + SwiftUI hosting views with a direct layout tree → CALayer pipeline.

## Why

- NSCollectionView's diffable data source model is fundamentally at odds with streaming / reactive updates
- NSHostingView measurement is 11-34× slower than CoreText (~150-440 µs vs ~13 µs per item)
- Collection view + IndexPath is too flat for tree-structured documents with nested scroll regions
- We need rich interactive views (table, kanban, timeline, grid) that don't fit the section/item model

## Architecture

```
Observable Model (signals)
  → Build: Model → Layout Tree
  → Layout: Layout Tree + Viewport Size → Frame Table [LeafID: CGRect]
  → Viewport Query: Frame Table + Scroll Offset → Visible Set
  → Render Diff: Old Visible Set vs New Visible Set → Layer Mutations
```

No separate DOM / layout / render trees. One layout tree + a flat frame cache. No CSS, no cascade, no pseudo-elements — so the trees don't structurally diverge.

## Core Principles

### One rendering primitive for text
Text is drawn via CoreText into a CALayer's `draw(in:)`. Everything else uses native layer types:
- `CAShapeLayer` for borders, bars, separators, rounded rects
- `CALayer` with `backgroundColor` for solid fills
- `CALayer` with `contents` (CGImage) for images
- `CAGradientLayer` if needed

### Layout protocol, not enum
```swift
protocol DocLayout {
    func layout(children: [CGSize], proposal: ProposedSize) -> LayoutResult
}
```
VStackLayout, HStackLayout, GridLayout etc. are each small structs. Adding a new layout type = one new struct. No enum cases to match on everywhere.

### Reactivity via signals
Signal changes → mark node dirty → incremental relayout (skip clean subtrees) → visible set diff → update layers. No snapshots, no full-document diffs.

Streaming, toggle/collapse, database updates, resize — all subsumed under the same reactivity model.

### No CTLine/CTFrame retained for off-screen content
The frame table stores only `CGRect` geometry. CoreText objects are created on demand during `draw(in:)` for visible leaves only. Memory scales with viewport, not document size.

### Nested scroll via real NSScrollView
Tables and kanban boards need independent horizontal scroll within the vertically-scrolling document. Each scrollable region gets one NSScrollView (cheap — it's one view). Cell virtualization inside is our own.

### Parallel measurement on resize
Top-level subtrees (sections/messages) are independent. On window resize, measure them in parallel via `concurrentPerform`. CoreText is thread-safe. ~13 µs/leaf × 1000 leaves ÷ 8 cores ≈ 1.6 ms.

### App controls tree size, not the framework
The framework renders whatever's in the tree. The app decides what's in the tree — collapsed sections, "load more" sentinels, evicted old messages. The framework doesn't impose virtualization heuristics.

## Layout Tree Structure

```
Document
├── Section (message)
│   ├── Paragraph              ← leaf cell (CoreText)
│   ├── CodeBlock              ← container
│   │   ├── CodeLine 0         ← leaf cell (one storage line)
│   │   ├── CodeLine 1         ← leaf cell
│   │   └── CodeLine 2         ← leaf cell
│   ├── Table                  ← container (owns column widths)
│   │   ├── HeaderRow          ← leaf cell (sticky)
│   │   ├── Row 0              ← leaf cell
│   │   └── Row 1              ← leaf cell
│   └── Kanban                 ← container (horizontal, scrollable)
│       ├── Column A           ← container (vertical)
│       │   ├── Card           ← leaf cell
│       │   └── Card           ← leaf cell
│       └── Column B
│           └── Card           ← leaf cell
```

Leaf cell granularity follows the natural atom of interaction: a line you click, a row you select, a card you drag.

## Target View Types (Notion-style database views + more)

- **Table** — rows × columns, sortable, filterable
- **Board / Kanban** — columns by property, draggable cards
- **List** — simple vertical list with inline properties
- **Grid / Gallery** — card grid (Pinterest/Notion gallery style)
- **Timeline / Gantt** — horizontal time axis, items as bars
- **Calendar** — month/week/day grid with items placed by date
- **Chart** — bar, line, pie from data
- **Form** — input collection view

## Sticky Headers

Post-processing step on computed frames:
```
header.y = max(naturalY, viewportTop)
header.y = min(header.y, regionBottom - headerHeight)
```
Applies to kanban column headers, table headers, section headers.

## Benchmark Reference (from investigation)

100 paragraphs, single layout pass, width=768:

| Approach | Time |
|----------|------|
| CoreText (CTFramesetter) | 1.4 ms |
| NSAttributedString.boundingRect | 1.6 ms |
| NSHostingView (reused) | 15.2 ms |
| NSHostingView (fresh) | 42.2 ms |

## Demo

`Demo/main.swift` — minimal working prototype. Observable signals, VStackLayout, CALayer rendering, reactive updates. ~280 lines. Run with `swift run DocEngineDemo`.

## Status

Design phase. This file captures the design discussion. Next step: build the real core types in a fresh session.
