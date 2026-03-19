# CanopyKit TODO

## Layout System

- **Two-dimensional proposals.** `measure(proposal:)` takes only width today. Needs `ProposedSize(width:height:)` with optional dimensions so layouts can propose cross-axis sizes.
- **Layout values.** Per-child key-value metadata on `LayoutSubview` (à la SwiftUI `LayoutValueKey`). Unlocks cross-axis alignment, table cell coordinates, flex grow/shrink, divider/background semantics.
- **Cross-axis stretch.** HStack/VStack stretch children along the cross axis by default (flexbox `align-items: stretch`). Requires both of the above.

## Rendering Performance

- **Drawing equivalence.** Add `isEquivalent` to `CustomDrawing` / `AnyDrawing` (same pattern as `AnyComponent`). Gate `content` assignment in reconcile on equivalence — skip when unchanged. This preserves layout cache and avoids unnecessary redraws.
- **Cache `CTFont` instances.** `CTFontCreateWithName` is called per-node per-frame. Static `[CGFloat: CTFont]` dictionary.
- **Cheaper `NodeID`.** Replace `[AnyHashable]` with a pre-hashed or string-based key. `AnyHashable` equality/hashing through existential unboxing dominates reconcile cost (~19% of main thread).

## Profiling

- **`os_signpost` instrumentation.** Add signpost intervals for: component body eval, resolved tree build, reconcile, layout pass, assign frames, visible leaf query, draw. Always compiled in, zero-cost when not recording.

## Naming

- Rename to CanopyKit. Targets, module, package name. Separate PR.

## Actor Isolation

- Engine types (`RenderNode`, `ResolvedNode`, `AnyDrawing`, layouts) stay unisolated.
- Entry points (`ComponentRenderer`, `ComponentRuntimeNode`) stay `@MainActor` for now.
- Revisit when Swift gains actor-generic types or the use case demands off-main rendering.
