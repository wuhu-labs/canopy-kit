# CanopyKit

CanopyKit is a small component-and-layout engine for SwiftUI.

It helps you compose complex, dynamic layouts while getting viewport culling and incremental updates for free. You describe a tree of components, layouts, and primitives; CanopyKit reconciles it, measures it, lays it out, and only materializes the visible render tree back into SwiftUI.

## What We Do

- Build large, nested UI out of small `Component` values.
- Preserve identity and equivalence so unchanged subtrees are skipped cheaply.
- Compute layout in our own tree, then lazily project only the visible render nodes.
- Make long feeds, chat logs, markdown documents, and other scroll-heavy surfaces cheap by default.

## How We Do It

CanopyKit owns geometry. SwiftUI should own as much else as possible.

- If something affects measurement or placement, model it as Canopy layout or a Canopy primitive.
- If something only affects appearance or interaction, push it back to SwiftUI with `.viewModifier(...)` or a `CustomViewRepresentable`.
- Prefer SwiftUI-backed leaves over bespoke drawing unless drawing is actually the right tool.
- Keep `Any*` types as implementation details. Public authoring should stay generic and concrete.

The rough pipeline is:

1. `Component` values produce `Node`s.
2. `ComponentRenderer` observes models and incrementally rebuilds the resolved tree.
3. `RenderRuntime` measures, lays out, caches preparation state, and creates size-specific commitments.
4. `RenderTreeView` projects only the visible render subtree into SwiftUI.

## Basic Syntax

Start with a `Component`:

```swift
import CanopyKit

struct MessageList: Component {
  let messages: [Message]

  func body() -> Node {
    Canopy.VStack(spacing: 8) {
      for message in messages {
        MessageRow(message: message)
          .id(message.id)
      }
    }
  }
}
```

Host it in SwiftUI with `ComponentTreeView`:

```swift
struct Screen: View {
  let messages: [Message]

  var body: some View {
    ComponentTreeView(root: MessageList(messages: messages))
  }
}
```

### Authoring Rules

- Prefer `Canopy.VStack`, `Canopy.HStack`, `Canopy.ZStack`, `Canopy.Text`, `Canopy.Shape`, `Canopy.View`, and `Canopy.Drawing`.
- Use `.id(...)` on dynamic children. Static children can rely on builder auto-keying, but lists and reorderable content should be explicitly keyed.
- Use `.padding(...)`, `.frame(...)`, and `Node.layout(...)` for geometry.
- Use `.viewModifier(...)` for interaction and purely visual styling that should stay in SwiftUI.
- Reach for `CustomViewRepresentable` first. Use `CustomDrawing` when you truly want canvas-style drawing.

### Result Builder Notes

`NodeBuilder` accepts:

- `Node`
- `IdentifiedNode`
- bare `Component`
- `if`, `if/else`, and `for`

Bare nodes and components are auto-keyed by position. `.id(...)` is the explicit escape hatch when identity matters.

## Demos

- `Static Markdown`: parses markdown into a Canopy component tree.
- `Reactive Feed`: shows stable identity and cheap append/remove updates in a scrolling feed.
- `Markdown Stream`: streams many markdown documents over time.
- `Tap Gesture`: shows the preferred interaction story, where Canopy layout is combined with SwiftUI view modifiers.
- `Image Gallery`: demonstrates `CustomViewRepresentable` by wrapping SwiftUI `Image`.
- `Session View`: a chat-style surface with streaming text, markdown, tool calls, images, and auto-scroll.

## Working Style

If you are extending the project, prefer this order of operations:

1. Build structure with `Component` and the `Canopy` namespace.
2. Add explicit `.id(...)` anywhere collection identity matters.
3. Use Canopy layout only for geometry.
4. Push visual polish and gestures back into SwiftUI.
5. Only add lower-level runtime or primitive machinery when the public authoring surface cannot express what you need.

## Verification

Useful local checks:

```sh
swift test
xcodebuild -project CanopyKitDemo.xcodeproj -scheme CanopyKitDemo -configuration Debug -destination 'platform=macOS' build
```
