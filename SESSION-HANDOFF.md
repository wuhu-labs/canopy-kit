# Session Handoff — Lazy Visible Tree Projection

## Branch & Latest Commits
- **Branch:** `instrumentation`
- **Latest:** `55dea96` (Stop tracking .trace files)
- **Key perf commits:** `c1d84f3` (incremental GC), `6c34712` (skip pointer-equal reconcile), `073d239` (rebuildIDs threading)
- All 64 tests pass. Benchmarks in `Benchmarks/` (reports are `.txt`, traces are `.trace/` gitignored).

## Current Performance (no-gc-walk benchmark)
```
refresh         746 µs    (was 18,374 µs at baseline)
reconcile       221 µs    (was  2,396 µs)
sizeThatFits    176 µs    (was  2,669 µs)
layout          184 µs    (was  3,588 µs)
App exclusive   14.5%     (was 33.9%)
```
All pipeline stages sub-millisecond. The remaining app cost is dominated by
`ResolvedRenderNodeView.init` at 4.1% exclusive (24 samples) and ARC/COW
overhead from `ResolvedRenderNode.Content` copying.

## The Problem: Eager Tree Materialization

**Spec (TODO-v2.md §8, line 256) says:**
> "This is a lazy projection — children are computed by intersecting child
>  frames with the viewport."

**What's actually implemented:** The exact opposite.

### Layer 1: `ResolvedRenderNodeView.init` (RenderRuntime.swift:58–99)

```swift
public struct ResolvedRenderNodeView {
  public let children: [ResolvedRenderNodeView]  // ← STORED, not computed

  public init?(node: ResolvedRenderNode, absoluteOrigin: CGPoint = .zero, viewport: CGRect) {
    // Eagerly recurses into ALL children before checking visibility
    let children = node.children.compactMap { child in
      ResolvedRenderNodeView(node: child, absoluteOrigin: ..., viewport: viewport)
    }
    // Visibility check comes AFTER full recursion, and never culls non-leaves
    let isVisible = display.frame.intersects(viewport) || !children.isEmpty
    guard isVisible else { return nil }
    self.children = children  // stores the fully-materialized array
  }
}
```

Problems:
1. `children` is a **stored** `[ResolvedRenderNodeView]` — the entire tree is
   materialized into heap-allocated arrays at construction time.
2. The `compactMap` recurses into every child **before** the visibility guard,
   so the full ~2,800 node tree is walked every frame regardless of viewport.
3. `|| !children.isEmpty` means any non-leaf node survives the guard even if
   its frame is completely off-screen. Only childless nodes get culled.
4. Every level allocates a new `[ResolvedRenderNodeView]` array (heap alloc).
5. Accessing `node.children` is a computed property on `ResolvedRenderNode`
   that constructs a new `IdentifiedArrayOf` each time — more allocations.

### Layer 2: `VisibleRenderNodeView` (RenderTreeView.swift:112–151)

The SwiftUI view consumes the pre-materialized array:
```swift
ForEach(nodeView.children, id: \.node.id) { childView in
  VisibleRenderNodeView(nodeView: childView)
}
```
Since layer 1 already built the whole tree, SwiftUI evaluates `body` for every
non-leaf node — creates `GeometryReader`s, offsets, frames, etc. for the entire
tree including off-screen content.

## What the Spec Intended

`ResolvedRenderNodeView` should be a **lightweight wrapper** that holds a
`ResolvedRenderNode` + `viewport` and computes visible children lazily on
access. Something like:

```swift
public struct ResolvedRenderNodeView {
  public let node: ResolvedRenderNode
  public let viewport: CGRect         // in local coordinates
  public let displayFrame: CGRect
  // ... other display properties

  // NO stored children array. Computed on access, filtered by viewport.
  public var children: [ResolvedRenderNodeView] {
    node.children.compactMap { child in
      let childFrame = child.frame
      // Cull entire subtree if frame doesn't intersect viewport
      guard childFrame.intersects(viewport) else { return nil }
      return ResolvedRenderNodeView(node: child, viewport: localViewport)
    }
  }
}
```

This way:
- Construction is O(1) — just stores references
- Children only materialized when SwiftUI evaluates a visible node's body
- Off-screen subtrees never visited at all
- ~2,800 nodes → ~50 visible nodes actually touched per frame

## Files to Change

1. **`Sources/WuhuUI/RenderRuntime.swift` lines 58–99** — `ResolvedRenderNodeView`
   - Remove stored `children: [ResolvedRenderNodeView]`
   - Make `init` non-failable, just store node + viewport + display properties
   - Add computed `children` property that does viewport intersection
   - The viewport effects (`applyViewportEffects` at line 443) still need to run,
     but only for nodes that are actually accessed

2. **`Sources/WuhuUI/RenderTreeView.swift` lines 112–151** — `VisibleRenderNodeView`
   - Should work as-is once layer 1 is lazy (it already iterates `.children`)
   - But verify SwiftUI isn't re-evaluating the computed property multiple times
     per frame — if it is, may need a caching strategy

3. **`Tests/RenderRuntimeTests.swift` lines 114–160** — Three tests use
   `visibleView` and check `.children.count`, `.leaves()` etc.
   - These should still pass if the lazy projection returns the same visible
     subset, but verify

## Design Considerations

- **`applyViewportEffects`**: Sticky headers, parallax, and scroll transitions
  modify the display frame based on viewport position. These must still be
  computed for visible nodes. The question is whether to compute them in the
  computed `children` getter or cache them.

- **Viewport intersection for culling**: Need to decide whether to cull based
  on the node's layout frame (pre-viewport-effects) or display frame
  (post-effects). Layout frame is cheaper and correct for most cases. Sticky
  headers could push a node into view that was out of view by layout frame,
  but that's an edge case we can handle later.

- **`|| !children.isEmpty` removal**: The current code keeps any node alive if
  it has visible children even if the node's own frame is off-screen. This is
  wrong for culling but might matter for hit-testing — a container with zero
  size could have positioned children. For now, cull by frame intersection
  and revisit if needed.

- **`ResolvedRenderNode.children` computed property**: Returns
  `IdentifiedArrayOf<ResolvedRenderNode>` which allocates each time. Could be
  improved to return the stored array directly for `.layout` case, and a
  single-element wrapper for `.component` case. Lower priority but contributes
  to ARC traffic.

## Benchmark Commands
```bash
# Run benchmark (builds release, records trace, analyzes)
Scripts/benchmark.sh <run-name>

# Just analyze an existing trace
python3 Scripts/analyze_trace.py Benchmarks/<run-name>

# Run tests
swift test
```

## Profile Reading Notes
- **Inclusive %** = time spent in function + everything it calls
- **Exclusive %** = time spent in function itself (top of stack)
- `visibleTree` at 38.6% inclusive means everything inside it (reconcile +
  layout + ResolvedRenderNodeView.init + viewport effects) totals 38.6%
- The 4.1% exclusive on `ResolvedRenderNodeView.init` is the struct
  construction + array allocation overhead, not the recursive children
- The real cost of eagerness is spread across: array allocs, ARC retain/release
  on ResolvedRenderNode references, Content enum copying, IdentifiedArray
  construction in the `.children` getter
