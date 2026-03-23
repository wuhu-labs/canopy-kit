@testable import CanopyKit
import CoreGraphics
import IdentifiedCollections
import SwiftUI
import Testing

// MARK: - Test ViewRepresentable

private struct FixedSizeViewRepresentable: CustomViewRepresentable {
  var width: CGFloat
  var height: CGFloat
  var label: String

  typealias Commitment = CGRect

  func sizeThatFits(proposal: ProposedSize, cache _: inout Void) -> CGSize {
    let w = proposal.width.map { min(width, $0) } ?? width
    let h = proposal.height.map { min(height, $0) } ?? height
    return CGSize(width: w, height: h)
  }

  func makeCommitment(in bounds: CGRect, cache _: Void) -> CGRect {
    bounds
  }

  func makeView(commitment _: CGRect) -> some View {
    Text(label)
  }
}

private final class ViewCacheRecorder {
  var makeCount = 0
  var updateCount = 0
}

private struct TrackingViewRepresentable: CustomViewRepresentable {
  let token: Int
  let recorder: ViewCacheRecorder

  struct Cache {
    var token: Int
  }
  typealias Commitment = CGRect

  func makeCache() -> Cache {
    recorder.makeCount += 1
    return Cache(token: token)
  }

  func updateCache(_ cache: inout Cache) {
    recorder.updateCount += 1
    cache.token = token
  }

  func sizeThatFits(proposal _: ProposedSize, cache _: inout Cache) -> CGSize {
    CGSize(width: 100, height: 20)
  }

  func makeCommitment(in bounds: CGRect, cache _: Cache) -> CGRect {
    bounds
  }

  func makeView(commitment _: CGRect) -> some View {
    Text("token")
  }
}

// MARK: - Tests

@MainActor
@Suite struct ViewRepresentableTests {
  @Test func customViewPrimitiveProducesViewCommitment() throws {
    let runtime = RenderRuntime()
    let representable = FixedSizeViewRepresentable(width: 120, height: 30, label: "Hello")
    let root = ResolvedNode(
      id: .root,
      content: .primitive(.init(representable))
    )

    let renderRoot = runtime.layout(
      root: root,
      proposal: ProposedSize(width: 200, height: nil)
    )

    let leaf = try #require(renderRoot.leaves().first)
    guard case let .primitive(_, commitment) = leaf.content else {
      Issue.record("Expected primitive render node")
      return
    }
    guard let commitment else {
      Issue.record("Expected custom view commitment, got \(String(describing: commitment))")
      return
    }

    #expect(commitment.primitive.isEquivalent(to: .init(representable)))
    #expect(commitment.value as? CGRect == CGRect(x: 0, y: 0, width: 120, height: 30))
    #expect(leaf.frame.size.width == 120)
    #expect(leaf.frame.size.height == 30)
  }

  @Test func customViewSizeRespectsProposal() {
    let runtime = RenderRuntime()
    let representable = FixedSizeViewRepresentable(width: 120, height: 30, label: "Hello")
    let root = ResolvedNode(
      id: .root,
      content: .primitive(.init(representable))
    )

    let size = runtime.sizeThatFits(
      root: root,
      proposal: ProposedSize(width: 80, height: nil)
    )

    #expect(size.width == 80)
    #expect(size.height == 30)
  }

  @Test func customViewCacheUpdatesAcrossResolvedNodeRebuilds() {
    let runtime = RenderRuntime()
    let recorder = ViewCacheRecorder()

    let initialRoot = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .primitive(.init(TrackingViewRepresentable(token: 1, recorder: recorder)))
    )
    _ = runtime.sizeThatFits(root: initialRoot, proposal: ProposedSize(width: 100, height: nil))

    let updatedRoot = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .primitive(.init(TrackingViewRepresentable(token: 2, recorder: recorder)))
    )
    _ = runtime.sizeThatFits(root: updatedRoot, proposal: ProposedSize(width: 100, height: nil))

    #expect(recorder.makeCount == 1)
    #expect(recorder.updateCount == 1)
  }

  @Test func customViewInLayoutReceivesCorrectFrames() throws {
    let runtime = RenderRuntime()
    let view1 = FixedSizeViewRepresentable(width: 100, height: 20, label: "A")
    let view2 = FixedSizeViewRepresentable(width: 100, height: 30, label: "B")
    let root = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .layout(
        AnyLayout(VStackLayout(spacing: 0)),
        [
          ResolvedNode(
            id: NodeID(rawValue: 2),
            content: .primitive(.init(view1))
          ),
          ResolvedNode(
            id: NodeID(rawValue: 3),
            content: .primitive(.init(view2))
          ),
        ]
      )
    )

    let renderRoot = runtime.layout(
      root: root,
      proposal: ProposedSize(width: 200, height: nil)
    )

    let leaves = renderRoot.leaves()
    #expect(leaves.count == 2)
    #expect(leaves[0].frame == CGRect(x: 0, y: 0, width: 100, height: 20))
    #expect(leaves[1].frame == CGRect(x: 0, y: 20, width: 100, height: 30))
  }

  @Test func customViewEquivalenceDetectsSameType() {
    let a = Primitive(FixedSizeViewRepresentable(width: 100, height: 20, label: "A"))
    let b = Primitive(FixedSizeViewRepresentable(width: 100, height: 20, label: "A"))
    let c = Primitive(FixedSizeViewRepresentable(width: 100, height: 20, label: "B"))

    #expect(a.isEquivalent(to: b))
    #expect(!a.isEquivalent(to: c))
  }

  @Test func primitiveIsEquivalentForCustomView() {
    let a = Primitive(FixedSizeViewRepresentable(width: 100, height: 20, label: "A"))
    let b = Primitive(FixedSizeViewRepresentable(width: 100, height: 20, label: "A"))
    let c = Primitive(fixedDrawing(width: 100, height: 20))

    #expect(a.isEquivalent(to: b))
    #expect(!a.isEquivalent(to: c))
  }

  @Test func nodeConvenienceFactoryCreatesCustomViewPrimitive() {
    let representable = FixedSizeViewRepresentable(width: 50, height: 50, label: "Test")
    let node = Node.view(representable)

    guard case let .primitive(primitive) = node.content else {
      Issue.record("Expected primitive content")
      return
    }
    #expect(primitive.isEquivalent(to: .init(representable)))
  }

  @Test func identifiedNodeConvenienceFactoryCreatesCustomViewPrimitive() {
    let representable = FixedSizeViewRepresentable(width: 50, height: 50, label: "Test")
    let identified = IdentifiedNode.view(key: "test", representable)

    guard case let .primitive(primitive) = identified.node.content else {
      Issue.record("Expected primitive content")
      return
    }
    #expect(primitive.isEquivalent(to: .init(representable)))
    #expect(identified.id == AnyHashable("test"))
  }
}
