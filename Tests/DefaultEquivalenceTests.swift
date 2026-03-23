import CoreGraphics
import struct SwiftUI.Path
import Testing
@testable import CanopyKit

private struct SemanticComponent: Component, Equatable {
  nonisolated let semanticID: Int
  nonisolated let incidentalID: Int

  nonisolated static func == (lhs: SemanticComponent, rhs: SemanticComponent) -> Bool {
    lhs.semanticID == rhs.semanticID
  }

  func body() -> Node {
    .drawing(fixedDrawing(width: CGFloat(semanticID), height: 20))
  }
}

private struct SemanticLayout: Layout, Equatable {
  let semanticID: Int
  let incidentalID: Int

  static func == (lhs: SemanticLayout, rhs: SemanticLayout) -> Bool {
    lhs.semanticID == rhs.semanticID
  }

  func layout(
    subviews: [LayoutSubview],
    proposal: ProposedSize
  ) -> (size: CGSize, placements: [LayoutPlacement]) {
    (
      size: CGSize(width: proposal.width ?? 0, height: CGFloat(subviews.count * semanticID)),
      placements: subviews.enumerated().map { index, _ in
        LayoutPlacement(origin: CGPoint(x: 0, y: CGFloat(index * semanticID)))
      }
    )
  }
}

private struct SemanticDrawing: CustomDrawing, Equatable {
  let semanticID: Int
  let incidentalID: Int

  static func == (lhs: SemanticDrawing, rhs: SemanticDrawing) -> Bool {
    lhs.semanticID == rhs.semanticID
  }

  struct Cache {}

  func makeCache() -> Cache { Cache() }

  func sizeThatFits(proposal _: ProposedSize, cache _: inout Cache) -> CGSize {
    CGSize(width: semanticID, height: 20)
  }

  func draw(in _: CGContext, bounds _: CGRect, cache _: inout Cache) {}
}

private struct SemanticShape: ShapePrimitive, Equatable {
  let semanticID: Int
  let incidentalID: Int

  static func == (lhs: SemanticShape, rhs: SemanticShape) -> Bool {
    lhs.semanticID == rhs.semanticID
  }

  func path(in _: CGRect) -> Path {
    Path(CGRect(x: 0, y: 0, width: semanticID, height: 10))
  }
}

private struct SemanticNodeValue: Equatable {
  let semanticID: Int
  let incidentalID: Int

  static func == (lhs: SemanticNodeValue, rhs: SemanticNodeValue) -> Bool {
    lhs.semanticID == rhs.semanticID
  }
}

private struct SemanticNodeValueKey: NodeValueKey {
  static let defaultValue = SemanticNodeValue(semanticID: 0, incidentalID: 0)
}

@Suite struct DefaultEquivalenceTests {
  @Test func anyComponentUsesEquatableByDefault() {
    let lhs = AnyComponent(SemanticComponent(semanticID: 1, incidentalID: 10))
    let rhs = AnyComponent(SemanticComponent(semanticID: 1, incidentalID: 20))

    #expect(lhs.isEquivalent(to: rhs))
  }

  @Test func anyLayoutUsesEquatableByDefault() {
    let lhs = AnyLayout(SemanticLayout(semanticID: 1, incidentalID: 10))
    let rhs = AnyLayout(SemanticLayout(semanticID: 1, incidentalID: 20))

    #expect(lhs.isEquivalent(to: rhs))
  }

  @Test func anyDrawingUsesEquatableByDefault() {
    let lhs = AnyDrawing(SemanticDrawing(semanticID: 1, incidentalID: 10))
    let rhs = AnyDrawing(SemanticDrawing(semanticID: 1, incidentalID: 20))

    #expect(lhs.isEquivalent(to: rhs))
  }

  @Test func anyShapeUsesEquatableByDefault() {
    let lhs = AnyShape(SemanticShape(semanticID: 1, incidentalID: 10))
    let rhs = AnyShape(SemanticShape(semanticID: 1, incidentalID: 20))

    #expect(lhs.isEquivalent(to: rhs))
  }

  @Test func nodeValuesUseEquatableSemanticsWhenAvailable() {
    var lhs = NodeValues()
    lhs[SemanticNodeValueKey.self] = SemanticNodeValue(semanticID: 1, incidentalID: 10)

    var rhs = NodeValues()
    rhs[SemanticNodeValueKey.self] = SemanticNodeValue(semanticID: 1, incidentalID: 20)

    #expect(lhs.isEquivalent(to: rhs))
  }
}
