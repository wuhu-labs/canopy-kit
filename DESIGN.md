# WuhuUI Design

Status: March 19, 2026

This file describes the current architecture and the intended near-term direction for WuhuUI.

The repository now has:

- A minimal layout/render engine based on an explicit render tree
- A SwiftUI-backed vertical-scroll renderer
- A small component-side proof of concept
- A reactive demo driven by Swift Observation

This document is intentionally narrower and more rigorous than the earlier design note. It focuses on the vertical-scroll case we are actively building.

## Goals

WuhuUI exists to render large, structured documents without paying the normal cost of a large tree of platform views or hosted SwiftUI subviews.

The desired properties are:

- Explicit tree structure
- Synchronous, predictable layout
- Cheap enough "virtualization" via full layout plus visible-leaf filtering
- Clear separation between app state, component expansion, resolved output, and runtime caches
- A path toward richer layouts such as tables, boards, timelines, and nested scroll regions

The design does not currently optimize for:

- General-purpose SwiftUI compatibility
- Arbitrary animation semantics
- Horizontal scrolling or nested scrolling
- A fully incremental subtree rebuild pipeline

## Core Position

The project is deliberately choosing:

- explicit layout tree
- explicit drawing leaves
- synchronous layout
- minimal SwiftUI involvement

instead of:

- `LazyVStack`
- view-per-cell hosting
- async layout
- hidden framework heuristics

The working assumption is that CoreText and simple geometry are cheap enough that a full layout pass over the current document is acceptable for the primary vertical-scroll use case, especially when we avoid per-item `NSView`/`UIView`/`CALayer` overhead.

For larger documents, product logic is expected to participate explicitly using patterns such as:

- load more sentinels
- collapsed sections
- partial history retention

The framework should not hide those decisions behind opaque virtualization rules.

## Layer Model

There are three important layers.

### 1. Component Layer

The component layer is where application logic lives.

It is:

- reactive
- driven by Swift Observation
- allowed to read app/model state
- responsible for producing a tree of components, layouts, and drawables

It is not:

- the render tree
- the cache owner
- the platform rendering backend

### 2. Resolved Tree

The resolved tree is the concrete output of component expansion.

It is intended to be:

- immutable
- persistent
- keyed
- free of component nodes

Only layout containers and drawable leaves remain after resolution.

This layer is the boundary between:

- declarative component logic
- imperative runtime rendering

### 3. Render Tree

The render tree is the mutable runtime object graph used by the current renderer.

It stores:

- runtime layout caches
- drawing caches
- parent links
- frame geometry

It is not observable node-by-node. SwiftUI only needs a root-level invalidation signal.

## Current Runtime Data Types

The current package has these major concepts:

- `Layout`
  - pure geometry for container measurement and child placement
- `CustomDrawing`
  - leaf measurement and drawing
- `RenderNode`
  - mutable runtime tree
- `Component`
  - proof-of-concept declarative component protocol
- `ComponentBody`
  - tree returned by components
- `ResolvedNode`
  - immutable expanded output node
- `ComponentRenderer`
  - bridge from component root to render tree
- `RenderTreeView`
  - SwiftUI view that performs layout and visible-leaf projection

## Vertical Scroll Scope

Tonight's POC is intentionally scoped to a single vertical scroll view.

That means:

- one main width proposal
- no horizontal scroll regions
- no sticky headers yet
- no nested viewport negotiation
- no animation system

This keeps the first component-side experiment honest and small.

## Layout Model

The current layout model is width-driven:

- parent proposes width
- child measures itself for that width
- parent places child origins

It is intentionally simpler than SwiftUI's full `ProposedViewSize` model.

Current layout protocol traits:

- width-only proposal
- single combined measure/place function
- child final size comes from child measurement
- placement currently means origin, not frame override

That is why `LayoutPlacement` now carries origin only. The engine today behaves like:

- parent decides proposal and position
- child decides size

This is the correct description of the current implementation.

## Drawing Model

Leaves implement `CustomDrawing`.

They currently support:

- `makeCache()`
- `sizeThatFits(width:cache:)`
- `draw(in:bounds:cache:)`

This API works, but it is not yet the final shape. The main unresolved question is whether draw-time cache mutation should remain legal.

Today:

- the important cache work happens during measurement for text leaves
- draw-time mutation is still allowed by the protocol

This is acceptable for the current prototype, but the API needs further cleanup so the phase boundary between layout and paint is clearer.

## Component Model

The current proof of concept uses:

- `Component`
  - returns `ComponentBody`
- `ComponentBody`
  - `.component(key:component)`
  - `.layout(key:layout,children:)`
  - `.drawing(key:drawing)`

Important rule:

- components may appear in `ComponentBody`
- components must not appear in `ResolvedNode`

Expansion removes component nodes entirely.

### Keys

For now, children are expected to be keyed.

That keeps the identity model simple:

- semantic keys such as `"header"` or `"footer"` are preferred
- index keys are acceptable when positional identity is intended

Tuple identity is intentionally deferred. It may be added later as sugar, but it is not a requirement for the vertical-scroll POC.

## Observation Model

Swift Observation is the intended state dependency mechanism.

The current POC uses:

- `@Observable` models
- `withObservationTracking` during component resolution

The current update story is:

1. evaluate component tree under observation tracking
2. render to resolved tree
3. reconcile into render tree
4. bump a single root revision
5. SwiftUI redraws the render view

When an observed value changes:

- the renderer schedules a coalesced refresh on the main actor
- the component tree is re-expanded
- the render tree is reconciled

This is intentionally root-driven for now.

### Near-Term Target

The intended next step is not a large global diff. The target is:

1. observation marks component paths dirty
2. a precursor/expansion structure records previous bodies and previous resolved subtrees
3. dirty component bodies are re-evaluated
4. changed descendants are discovered top-down
5. only dirty precursor paths generate new persistent resolved nodes

That means:

- observation dirtiness is authoritative
- body equality is a pruning optimization
- persistent tree reuse should avoid rebuilding unchanged subtrees

## Equality and Identity

This is still an active design area.

The long-term direction is:

- cheap equality before boxing when possible
- strong use of stable keys and object identity in persistent nodes
- subtree skipping based on persistent-node identity

The current code does not yet implement the full precursor-plus-persistent-subtree strategy described above.

The current proof of concept instead focuses on:

- keyed expansion
- path-backed resolved node IDs
- observation-driven refresh
- render tree reconciliation by resolved node ID

This is enough to validate the basic layering without prematurely hard-coding the final equality strategy.

## Render Tree Reconciliation

`ComponentRenderer` currently resolves a root component and reconciles it into a mutable `RenderNode` tree.

The current reconciliation keeps:

- stable runtime nodes where resolved IDs match
- parent links and upward invalidation behavior

The current reconciliation does not yet do a fully selective payload-level cache preservation strategy. That will improve as the resolved tree becomes more persistent and equality becomes more principled.

## SwiftUI Integration

SwiftUI is currently used as:

- app shell
- controls
- scroll container
- `Canvas` drawing bridge
- root invalidation mechanism

SwiftUI is not used as the layout engine for document content.

This is deliberate.

### `RenderTreeView`

`RenderTreeView` is synchronous.

It:

- measures the render tree for the current width
- assigns frames
- filters visible leaves using the viewport rect
- draws only visible leaf nodes via `Canvas`

The view intentionally does not own reactive per-node state.

## Current Demos

The demo target currently includes:

- direct render-tree markdown-like document
- static component-composed document
- reactive component feed driven by an `@Observable` model

The reactive demo is important because it validates:

- Observation-based invalidation
- component expansion
- render tree refresh
- vertical-scroll rendering through the same backend

## Testing

The package should lean into debuggability.

This architecture is much easier to inspect than SwiftUI because the core trees are explicit.

Current test coverage includes:

- basic layout behavior
- nested layout behavior
- repeatability across multiple layout passes
- upward invalidation to the root
- component expansion pathing
- observation-driven renderer refresh

Near-term testing improvements should include:

- resolved tree snapshot-style dumps
- reconciliation behavior tests
- more adversarial keyed-child replacement tests
- text-heavy integration tests

## Immediate Future Work

These are the most relevant next areas, but not all are critical for the next session:

- layout values
  - especially for table/header/divider roles and richer container negotiation
- hit testing and event handling
- accessibility
- text selection
- environment propagation
- additional primitive leaves
  - shapes
  - platform views/layers
- better component builder ergonomics
- more rigorous precursor-based incremental expansion

## Deferred Topics

The following are intentionally deferred to keep the current design discussion clean:

- horizontal scrolling
- nested scroll views
- animation model
- alternate backends
  - AppKit/UIKit native backend
  - PDF/image backend
  - Android/Skia-style backend

These remain important, but they should not dictate the first vertical-scroll component runtime.

## Summary

The architecture now has a clear working direction:

- explicit component tree
- immutable resolved output
- mutable runtime render tree
- root-level SwiftUI invalidation
- synchronous vertical layout and rendering

The implemented code is still only a proof of concept, but it is now aligned with the intended mental model much more closely than the original design note.

The next real milestone is not animation or horizontal scrolling. It is a more principled incremental component expansion pipeline built on observation-driven dirty paths and persistent resolved subtree reuse.
