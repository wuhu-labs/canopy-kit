import CanopyKit
import IdentifiedCollections
import Observation
import SwiftUI

// MARK: - Tap Gesture Demo

@Observable
final class TapGestureDemoModel {
  struct Counter: Identifiable, Equatable {
    let id: Int
    let label: String
    var count: Int = 0
  }

  var counters: [Counter] = [
    Counter(id: 0, label: "Red"),
    Counter(id: 1, label: "Green"),
    Counter(id: 2, label: "Blue"),
  ]

  func increment(_ id: Int) {
    guard let index = counters.firstIndex(where: { $0.id == id }) else { return }
    counters[index].count += 1
  }
}

struct TapGestureDemoView: View {
  @State private var model = TapGestureDemoModel()

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("Tap the colored cards to increment their counters.")
        Spacer()
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      ComponentTreeView(
        root: AnyComponent(
          TapGestureDemoComponent(model: model),
          isEquivalent: { lhs, rhs in lhs.model === rhs.model }
        )
      )
    }
  }
}

struct TapGestureDemoComponent: Component {
  let model: TapGestureDemoModel

  private static let colors: [CGColor] = [
    CGColor(red: 0.9, green: 0.3, blue: 0.3, alpha: 1),
    CGColor(red: 0.3, green: 0.75, blue: 0.3, alpha: 1),
    CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1),
  ]

  func body() -> Node {
    .layout(
      AnyLayout(VStackLayout(spacing: 12)),
      children: IdentifiedArray(
        uniqueElements: model.counters.map { counter in
          let color = Self.colors[counter.id % Self.colors.count]
          return IdentifiedNode.layout(
            key: counter.id,
            AnyLayout(VStackLayout(spacing: 4)),
            children: [
              .drawing(
                key: "bg",
                AnyDrawing(RectDrawing(color: color, height: 40))
              ),
              .drawing(
                key: "label",
                AnyDrawing(TextDrawing("\(counter.label): tapped \(counter.count) time\(counter.count == 1 ? "" : "s")", fontSize: 16))
              ),
            ]
          )
          .onTapGesture { [weak model] in
            model?.increment(counter.id)
          }
        }
      )
    )
  }
}
