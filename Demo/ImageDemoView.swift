import CanopyKit
import IdentifiedCollections
import Observation
import SwiftUI

// MARK: - Image View Representable

/// A `CustomViewRepresentable` that renders a system image via SwiftUI's `Image`.
struct ImageViewRepresentable: CustomViewRepresentable, Equatable {
  var systemName: String
  var width: CGFloat
  var height: CGFloat
  var color: Color

  struct Cache {}

  func makeCache() -> Cache {
    Cache()
  }

  func sizeThatFits(proposal: ProposedSize, cache _: inout Cache) -> CGSize {
    let w = proposal.width.map { min(width, $0) } ?? width
    let h = proposal.height.map { min(height, $0) } ?? height
    return CGSize(width: w, height: h)
  }

  func makeView(cache _: Cache) -> some View {
    Image(systemName: systemName)
      .resizable()
      .scaledToFit()
      .foregroundStyle(color)
  }
}

// MARK: - Demo Model

@Observable
final class ImageDemoModel {
  struct Item: Identifiable, Equatable {
    let id: Int
    let systemName: String
    let label: String
    let color: Color
  }

  var items: [Item] = [
    Item(id: 0, systemName: "star.fill", label: "Star", color: .yellow),
    Item(id: 1, systemName: "heart.fill", label: "Heart", color: .red),
    Item(id: 2, systemName: "bolt.fill", label: "Bolt", color: .orange),
    Item(id: 3, systemName: "leaf.fill", label: "Leaf", color: .green),
    Item(id: 4, systemName: "drop.fill", label: "Drop", color: .blue),
    Item(id: 5, systemName: "flame.fill", label: "Flame", color: .red),
    Item(id: 6, systemName: "moon.fill", label: "Moon", color: .purple),
    Item(id: 7, systemName: "sun.max.fill", label: "Sun", color: .orange),
  ]

  func shuffle() {
    items.shuffle()
  }
}

// MARK: - Components

struct ImageGalleryComponent: Component {
  let model: ImageDemoModel

  func body() -> Node {
    .layout(
      AnyLayout(VStackLayout(spacing: 12)),
      children: IdentifiedArray(
        uniqueElements: model.items.map { item in
          IdentifiedNode.component(
            key: item.id,
            AnyComponent(ImageCardComponent(item: item))
          )
        }
      )
    )
  }
}

struct ImageCardComponent: Component, Equatable {
  let item: ImageDemoModel.Item

  func body() -> Node {
    .hstack(spacing: 12) {
      Node.view(
        AnyViewRepresentable(
          ImageViewRepresentable(
            systemName: item.systemName,
            width: 32,
            height: 32,
            color: item.color
          )
        )
      )
      .frame(width: 32, height: 32)
      .keyed("icon")

      Node.text(item.label, fontSize: 16)
        .keyed("label")
    }
    .padding(left: 12, top: 8, right: 12, bottom: 8)
  }
}

// MARK: - Demo View

struct ImageDemoView: View {
  @State private var model = ImageDemoModel()

  var body: some View {
    VStack(spacing: 12) {
      HStack {
        Text("\(model.items.count) items")
        Spacer()
        Button("Shuffle") { model.shuffle() }
      }
      .padding(.horizontal, 16)
      .padding(.top, 12)

      ComponentTreeView(
        root: AnyComponent(ImageGalleryComponent(model: model))
      )
    }
  }
}
