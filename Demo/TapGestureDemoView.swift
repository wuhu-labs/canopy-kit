import CanopyKit
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

// MARK: - Tap Gesture ViewModifier

/// Example of attaching a tap gesture via an explicit SwiftUI ViewModifier,
/// using CanopyKit's `.viewModifier(...)` API.
struct CardModifier: ViewModifier {
  let model: TapGestureDemoModel
  let id: Int

  var fill: Color {
    switch id {
    case 0: .red
    case 1: .green
    case 2: .blue
    default: fatalError()
    }
  }

  func body(content: Content) -> some View {
    content
      .foregroundStyle(fill)
      .contentShape(Rectangle())
      .onTapGesture {
        model.increment(id)
      }
  }
}

// MARK: - Demo View

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

      ComponentTreeView(root: TapGestureDemoComponent(model: model))
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

  private static let cardHeight: CGFloat = 40

  func body() -> Node {
    Canopy.VStack(spacing: 12) {
      for counter in model.counters {
        Node.layout(VStackLayout(spacing: 4)) {
          Canopy.Shape(Capsule())
            .frame(height: Self.cardHeight)
            .id("bg")
          Canopy.Drawing(
            TextDrawing(
              "\(counter.label): tapped \(counter.count) time\(counter.count == 1 ? "" : "s")",
              fontSize: 16
            )
          )
          .id("label")
        }
        .id(counter.id)
        .viewModifier(CardModifier(model: model, id: counter.id))
      }
    }
  }
}
