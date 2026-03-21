# CanopyKit v2 — Design TODO

This captures the full redesign discussed on 2025-07-14. Issues are ordered
by natural dependency — each builds on the ones above it.

---

## 1. Rename Node types and introduce `NodeValues`

**Component declaration layer.** Replace `ComponentBody` enum with a struct + enum split:

```swift
struct Node {
  var content: NodeContent
  var values: NodeValues
}

enum NodeContent {
  case component(AnyComponent)
  case layout(AnyLayout, IdentifiedArrayOf<IdentifiedNode>)
  case primitive(Primitive)
}

struct IdentifiedNode: Identifiable {
  var id: AnyHashable
  var node: Node
}
```

`NodeValues` is a single type-indexed dictionary (`[ObjectIdentifier: Any]`),
same pattern as SwiftUI `EnvironmentValues`. All per-node metadata lives here:
layout values, visual effects, gesture handlers, accessibility — one bag,
many consumers.

```swift
protocol NodeValueKey {
  associatedtype Value
  static var defaultValue: Value { get }
}

struct NodeValues {
  subscript<K: NodeValueKey>(key: K.Type) -> K.Value { get set }
}
```

`LayoutValues` (which already exists) is subsumed by `NodeValues`.

Keys are only on `IdentifiedNode` — they exist solely to identify children
within a parent layout's child list. Root nodes use a conventional sentinel.

**Dependency:** swift-identified-collections.

---

## 2. Introduce `Primitive` enum — shapes and custom drawing

Replace `AnyDrawing` as the sole leaf type with a `Primitive` enum:

```swift
enum Primitive {
  case shape(AnyShape)      // returns a SwiftUI `Path`, participates in layout
  case customDrawing(AnyDrawing)  // imperative CGContext escape hatch
}
```

- **Shape:** author provides a `(ProposedSize) -> Path`. Flexible by default
  (accepts proposed size). Fill/stroke style comes from `NodeValues`.
  `Path` is the currency type (bidirectional with `CGPath`).
- **CustomDrawing:** what exists today. Full `CGContext` control.

Having two cases forces the design to be honest about the primitive
abstraction. Text, view hosting, etc. come later.

---

## 3. Preserve component nodes in `ResolvedNode`

Today, component nodes are stripped during resolution — only layout and
drawing survive. Change this: component nodes survive as identity/passthrough
wrappers with a single child.

```swift
final class ResolvedNode {
  enum Content {
    case component(AnyComponent, ResolvedNode)
    case layout(AnyLayout, IdentifiedArrayOf<ResolvedNode>)
    case primitive(Primitive)
  }

  let id: NodeID
  let content: Content
  let values: NodeValues
}
```

`ResolvedNode` is an immutable, `Sendable` class. Component boundaries in the
resolved tree enable reflection, debugging, accessibility region discovery,
hit-test scoping, and lifecycle hooks.

---

## 4. Cheap `NodeID` — integer-based identity

Replace `NodeID = [AnyHashable]` with a cheap integer ID. The runtime assigns
a monotonically incrementing integer to each node. The key-path is derivable
by walking the parent chain when needed (debugging, error messages) but is
never used for hot-path operations like hashing or dictionary lookup.

The ancestor chain mapping (`[InternalID: ...]`) and resolved node dictionary
(`[InternalID: ResolvedNode]`) are keyed by this integer.

---

## 5. Equatable-by-default type erasure

`AnyComponent`, `AnyLayout`, `AnyDrawing`, and `AnyShape` should all follow
the same equality convention:

- If the erased type conforms to `Equatable`, use `Equatable`.
- Otherwise, fall back to `memcmp` on the value's bytes.
- Different erased types are never equal.

For classes: conform to `Equatable` using `ObjectIdentifier` exclusively,
unless the class is fully immutable (all `let` stored properties).

This enables pointer-stable persistent trees — unchanged nodes are detected
cheaply, enabling skip-on-pointer-equality throughout the pipeline.

---

## 6. Rework the reactive runtime — heap-driven dirty resolution

Replace the distributed tree of `ComponentRuntimeNode` with a centralized,
flat runtime:

### Data structures

- **Node registry:** `[InternalID: RuntimeEntry]` — flat dictionary, no tree.
  Each entry holds the `AnyComponent`, its last `Node` (body output), its
  preparation cache, and a reference to its current `ResolvedNode`.
- **Dirty set:** unordered set of internal IDs, fed by observation callbacks.
- **Dirty heap:** min-heap ordered by path depth. Built synchronously at the
  start of each refresh cycle by resolving the dirty set against the registry
  (non-existent IDs are dropped — this is the GC path for stale observations).

### Refresh cycle

**Phase 1 — Collect.** Observation callbacks dump raw internal IDs into the
dirty set. On refresh, resolve into the heap, discarding dead IDs.

**Phase 2 — Shallow diff.** Pull shallowest dirty ID from heap. Run
`body()` with `withObservationTracking`. Diff new body against previous body.
The diff is shallow — stops at component boundaries and primitives. Produces
a patch list per node:

| Patch | Target |
|---|---|
| `insert(at:, node)` | Child list |
| `delete(at:)` | Child list |
| `move(from:, to:)` | Child list (via stdlib collection diffing) |
| `updateComponent(at:)` | Pushes component's internal ID onto dirty heap |
| `updatePrimitive(at:, primitive)` | Leaf content |
| `updateLayout(layout)` | Container's layout object |
| `updateValues(at:, values)` | Node's metadata |

Equality checks (issue #5) gate whether a patch is emitted — if the new
value is equivalent to the old, no patch.

Repeat until heap is empty.

**Phase 3 — Mark ancestor spines dirty.** For every node with patches, walk
its ancestor chain marking each as dirty. Stop when hitting an already-dirty
ancestor.

**Phase 4 — Persistent tree generation.** Walk top-down from root:

- Clean node → reuse existing `ResolvedNode` (same object reference).
- Dirty node with patches → apply patches, produce new `ResolvedNode`,
  reuse unchanged children.
- Dirty spine node (no patches, but has dirty descendants) → new
  `ResolvedNode` with updated children, same content.

Output: new `ResolvedNode` root with maximal structural sharing.

### GC

- Deleted nodes (via `delete` patches): remove from registry immediately.
- Stale observation callbacks: discarded at phase 1 when the ID isn't in
  the registry.
- `withObservationTracking` is one-shot, so stale callbacks self-clean.

---

## 7. Render runtime — flat cache + persistent resolved render tree

The render runtime is not a tree. It is a flat `[InternalID: CacheEntry]`
dictionary. Each entry holds:

- **Size LRU:** last ~4 `(ProposedSize, CGSize)` pairs.
- **Preparation cache:** user-created expensive state (e.g., `CTTypesetter`),
  tied to the `ResolvedNode`. Recreated when that node changes. Author can
  choose to incrementally update.
- **Commitment:** the resolved drawing artifact produced when a final size is
  committed. For shapes: the resolved `Path`. For text: `[CTLine]` + metrics.
  Value type, lives on the resolved render node.
- **Last resolved render node:** the previously produced immutable output node.

### Reconciliation

Takes the new `ResolvedNode` tree (from issue #6) and reconciles top-down
via recursion:

- Pointer-equal resolved node → skip entirely, reuse cache entry and
  resolved render node.
- Changed resolved node → invalidate size LRU and preparation cache for
  this node. Invalidate size LRU up the ancestor chain. Recurse into children.
  Primitives also clear their commitment.

### Layout

`sizeThatFits(proposal:)` warms up the size LRU throughout the tree
top-down. Cached entries are reused.

`layout(proposal:)` produces the final persistent **resolved render tree**
— an immutable tree carrying frames, commitments, and node values.

Partial update reuse: if only the last block of a markdown doc changed, all
other nodes' size caches and resolved render nodes are preserved. Only the
root and the changed subtree produce new nodes.

### Drop SwiftUI-style per-node layout cache

The current `makeCache()` on `Layout` conflates user-managed expensive state
with framework-managed layout memoization. Split these:

- **Preparation cache** — user-created, depends on `ResolvedNode` content.
  E.g., `CTTypesetter`. Managed by author, invalidated when node changes.
- **Size cache** — `(ProposedSize, CGSize)` LRU. Managed by the runtime.

---

## 8. Resolved render tree view — visible tree projection

Replace flat visible-leaf list with a tree-structured view into the visible
portion:

```swift
struct ResolvedRenderNodeView {
  let node: ResolvedRenderNode   // immutable, carries frame + commitment
  let viewport: CGRect           // in local coordinates

  var children: [ResolvedRenderNodeView]  // only visible children
}
```

This is a lazy projection — children are computed by intersecting child
frames with the viewport. Returning a tree (not just leaves) enables:

- Hit testing by walking from root and narrowing at each level.
- Event handler dispatch via `NodeValues` on the matched node.
- Accessibility tree generation.
- Debug overlays.

---

## 9. Observable root + SwiftUI integration

The resolved render tree root is the **only** observable thing for SwiftUI.
Options:

- A single `@Observable` sentinel class with a revision counter that
  `RenderTreeView` reads.
- Or make the render runtime itself `@Observable` with a single published
  property.

**Invariant:** nothing else in the tree is reactive to SwiftUI. Layout
operations do not trigger observable updates. The only update path is:
observation → dirty resolution → new resolved tree → reconcile render
runtime → produce new resolved render tree → bump revision → SwiftUI
redraws.

---

## 10. `NodeValues` consumers — layout values

Layout values (e.g., `StretchBehavior`, `FlexGrow`, alignment overrides)
are `NodeValueKey`s read by layout implementations from `NodeValues`.

This subsumes the existing `LayoutValues` type and `LayoutValueKey` protocol.

Concrete keys TBD, but the mechanism is: layout receives `LayoutSubview`,
`LayoutSubview` reads from the child's `NodeValues`.

---

## 11. `NodeValues` consumers — visual effects

Static visual effects as `NodeValueKey`s:

- **Opacity** — `CGFloat`, default 1.0.
- **Mask/clip** — `Path?`, default nil.

Applied at the resolved render node level during SwiftUI view construction.
Do not affect layout or hit testing.

---

## 12. `NodeValues` consumers — scroll-relative effects

Viewport-dependent transformations evaluated by the render runtime during
layout/visibility:

- **Sticky headers** — node stays pinned at viewport top edge.
- **Parallax** — node translates at a fraction of scroll velocity.
- **Scroll transitions** — opacity/scale/offset as function of viewport
  position.

These are pure functions of `(node frame, viewport rect) → adjusted frame
or visual transform`. No reactivity — evaluated each time the resolved
render tree is produced.

Nested scroll views introduce multiple viewports. The structural sharing
of the persistent tree means only the scroll container subtree rebuilds
on scroll offset changes.

---

## 13. `NodeValues` consumers — gestures

Gesture handlers attached via `NodeValues`. SwiftUI gesture combinators
composed at view construction time based on what's declared:

- Tap, double tap, long press → callbacks, no state.
- Hover → callback, no state.
- Drag → `onChanged`/`onEnded` callbacks. Gesture state (if needed) lives
  in user-land `@Observable` models, not in the render runtime.

Gesture-carrying nodes are always treated as dirty (gestures are not
equatable). Acceptable trade-off — interactive nodes are rare relative
to the full tree.

Convention: `.gesture()` modifier on `Node`, stores an `AnyGesture?` in
`NodeValues`, default nil. The SwiftUI view layer conditionally attaches
the gesture.

---

## Deferred

These were discussed and explicitly deferred:

- **Padding / frame as `NodeValues`** — clear tree-flattening win, but adds
  non-trivial evaluation-order complexity. If adopted, probably padding only.
- **`NodeValues` grouping** (attributed-string-style compound keys) — for
  cross-platform backends (PDF, Android, Wasm). Refactor when needed; API
  is unstable anyway.
- **`@State` / `@GestureState` equivalents in components** — component-scoped
  local storage. Bigger design question, future topic.
- **Nested scroll views** — multiple viewports, complex layout. Architecture
  supports it (structural sharing limits rebuild scope), but implementation
  is future work.
- **Geometry-effect-backed visual effects** — unresolved question of whether
  they affect hit testing.
