import CanopyKit
import IdentifiedCollections
import Observation
import SwiftUI

@Observable
final class PrimitiveShrinkBugModel {
  var isExpanded = false
}

struct PrimitiveShrinkBugDemoView: View {
  @State private var model = PrimitiveShrinkBugModel()

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Text(model.isExpanded ? "Expanded" : "Collapsed")
          .font(.headline)
        Spacer()
        Button("Toggle") {
          model.isExpanded.toggle()
        }
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
      .background(.bar)

      Divider()

      ComponentTreeView(
        root: AnyComponent(
          PrimitiveShrinkBugRootComponent(model: model),
          isEquivalent: { lhs, rhs in lhs.model === rhs.model }
        )
      )
    }
    .frame(maxWidth: 700)
  }
}

private struct PrimitiveShrinkBugRootComponent: Component {
  let model: PrimitiveShrinkBugModel

  func body() -> Node {
    .layout(
      AnyLayout(InsetLayout(left: 16, top: 16, right: 16, bottom: 16)),
      children: [
        .layout(
          key: "stack",
          AnyLayout(VStackLayout(spacing: 12)),
          children: [
            .drawing(
              key: "intro",
              AnyDrawing(TextDrawing(
                "This demo isolates the tool-call accent bar. Toggle the block below: the left rule should grow and shrink with the content.",
                fontSize: 14
              ))
            ),
            .component(
              key: "repro",
              AnyComponent(
                PrimitiveShrinkBugComponent(model: model),
                isEquivalent: { lhs, rhs in lhs.model === rhs.model }
              )
            ),
            .drawing(
              key: "footer",
              AnyDrawing(TextDrawing(
                "If the bug reproduces, the result block collapses but the left rule stays at the old expanded height.",
                fontSize: 13
              ))
            ),
          ]
        ),
      ]
    )
  }
}

private struct PrimitiveShrinkBugComponent: Component {
  let model: PrimitiveShrinkBugModel

  func body() -> Node {
    var children: [IdentifiedNode] = [
      .drawing(
        key: "label",
        AnyDrawing(TextDrawing(
          model.isExpanded
            ? "▾ demo_tool {\"path\": \"Sources/CanopyKit/RenderTreeView.swift\"}"
            : "▸ demo_tool {\"path\": \"Sources/CanopyKit/RenderTreeView.swift\"}",
          fontSize: 13
        ))
      ),
    ]

    if model.isExpanded {
      children.append(
        .layout(
          key: "result-bg",
          AnyLayout(ZStackLayout()),
          children: [
            .drawing(
              key: "bg",
              AnyDrawing(RectDrawing(
                color: CGColor(gray: 0.96, alpha: 1),
                height: 0
              ))
            ),
            .layout(
              key: "result-inset",
              AnyLayout(InsetLayout(left: 8, top: 6, right: 8, bottom: 6)),
              children: [
                .drawing(
                  key: "result-text",
                  AnyDrawing(TextDrawing(expandedResultText, fontSize: 12))
                ),
              ]
            ),
          ]
        )
      )
    }

    return .layout(
      AnyLayout(ZStackLayout()),
      children: [
        .layout(
          key: "bar",
          AnyLayout(FrameLayout(width: 2)),
          children: [
            .drawing(
              key: "bar-rect",
              AnyDrawing(RectDrawing(
                color: CGColor(gray: 0.82, alpha: 1),
                height: 0
              ))
            ),
          ]
        ),
        .layout(
          key: "content",
          AnyLayout(InsetLayout(left: 10, top: 4, right: 0, bottom: 4)),
          children: [
            .layout(
              key: "stack",
              AnyLayout(VStackLayout(spacing: 4)),
              children: IdentifiedArray(uniqueElements: children)
            ),
          ]
        ),
      ]
    )
    .onTapGesture { [weak model] in
      model?.isExpanded.toggle()
    }
  }
}

private let expandedResultText = """
// A flexible custom drawing fills whatever size the runtime proposes.
// The content below should cause the left rule to expand while visible.
// When this block collapses, the rule should shrink back to match.
public struct PrimitiveCanvas: View {
  let node: ResolvedRenderNode
  let commitment: PrimitiveCommitment?
}

// Repeated lines make the delta obvious.
line 1
line 2
line 3
line 4
line 5
line 6
line 7
line 8
"""
