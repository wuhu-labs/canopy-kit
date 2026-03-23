@testable import CanopyKit
import CoreGraphics
import protocol SwiftUI.Shape
import struct SwiftUI.Path
import Testing

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

  typealias Commitment = CGRect

  func sizeThatFits(proposal _: ProposedSize, cache _: inout Void) -> CGSize {
    CGSize(width: semanticID, height: 20)
  }

  func makeCommitment(in bounds: CGRect, cache _: Void) -> CGRect {
    bounds
  }

  func draw(in _: CGContext, commitment _: CGRect) {}
}

private struct SemanticShape: Shape, Equatable {
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

  @Test func primitiveDrawingUsesEquatableByDefault() {
    let lhs = Primitive(SemanticDrawing(semanticID: 1, incidentalID: 10))
    let rhs = Primitive(SemanticDrawing(semanticID: 1, incidentalID: 20))

    #expect(lhs.isEquivalent(to: rhs))
  }

  @Test func primitiveShapeUsesEquatableByDefault() {
    let lhs = Primitive(SemanticShape(semanticID: 1, incidentalID: 10))
    let rhs = Primitive(SemanticShape(semanticID: 1, incidentalID: 20))

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
