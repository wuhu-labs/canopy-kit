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

  struct Cache {}

  func makeCache() -> Cache {
    Cache()
  }

  func sizeThatFits(proposal: ProposedSize, cache _: inout Cache) -> CGSize {
    let w = proposal.width.map { min(width, $0) } ?? width
    let h = proposal.height.map { min(height, $0) } ?? height
    return CGSize(width: w, height: h)
  }

  func makeView(cache _: inout Cache) -> some View {
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

  func makeView(cache _: inout Cache) -> some View {
    Text("token")
  }
}

// MARK: - Tests

@MainActor
@Suite struct ViewRepresentableTests {
  @Test func customViewPrimitiveProducesViewCommitment() throws {
    let runtime = RenderRuntime()
    let representable = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 120, height: 30, label: "Hello")
    )
    let root = ResolvedNode(
      id: .root,
      content: .primitive(.customView(representable))
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
    guard case .customView = commitment else {
      Issue.record("Expected custom view commitment, got \(String(describing: commitment))")
      return
    }

    #expect(leaf.frame.size.width == 120)
    #expect(leaf.frame.size.height == 30)
  }

  @Test func customViewSizeRespectsProposal() {
    let runtime = RenderRuntime()
    let representable = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 120, height: 30, label: "Hello")
    )
    let root = ResolvedNode(
      id: .root,
      content: .primitive(.customView(representable))
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
      content: .primitive(.customView(
        AnyViewRepresentable(TrackingViewRepresentable(token: 1, recorder: recorder))
      ))
    )
    _ = runtime.sizeThatFits(root: initialRoot, proposal: ProposedSize(width: 100, height: nil))

    let updatedRoot = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .primitive(.customView(
        AnyViewRepresentable(TrackingViewRepresentable(token: 2, recorder: recorder))
      ))
    )
    _ = runtime.sizeThatFits(root: updatedRoot, proposal: ProposedSize(width: 100, height: nil))

    #expect(recorder.makeCount == 1)
    #expect(recorder.updateCount == 1)
  }

  @Test func customViewInLayoutReceivesCorrectFrames() throws {
    let runtime = RenderRuntime()
    let view1 = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 100, height: 20, label: "A")
    )
    let view2 = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 100, height: 30, label: "B")
    )
    let root = ResolvedNode(
      id: NodeID(rawValue: 1),
      content: .layout(
        AnyLayout(VStackLayout(spacing: 0)),
        [
          ResolvedNode(
            id: NodeID(rawValue: 2),
            content: .primitive(.customView(view1))
          ),
          ResolvedNode(
            id: NodeID(rawValue: 3),
            content: .primitive(.customView(view2))
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
    let a = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 100, height: 20, label: "A")
    )
    let b = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 100, height: 20, label: "A")
    )
    let c = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 100, height: 20, label: "B")
    )

    #expect(a.isEquivalent(to: b))
    #expect(!a.isEquivalent(to: c))
  }

  @Test func primitiveIsEquivalentForCustomView() {
    let a = Primitive.customView(AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 100, height: 20, label: "A")
    ))
    let b = Primitive.customView(AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 100, height: 20, label: "A")
    ))
    let c = Primitive.customDrawing(fixedDrawing(width: 100, height: 20))

    #expect(a.isEquivalent(to: b))
    #expect(!a.isEquivalent(to: c))
  }

  @Test func nodeConvenienceFactoryCreatesCustomViewPrimitive() {
    let representable = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 50, height: 50, label: "Test")
    )
    let node = Node.view(representable)

    guard case let .primitive(primitive) = node.content else {
      Issue.record("Expected primitive content")
      return
    }
    guard case .customView = primitive else {
      Issue.record("Expected customView primitive")
      return
    }
  }

  @Test func identifiedNodeConvenienceFactoryCreatesCustomViewPrimitive() {
    let representable = AnyViewRepresentable(
      FixedSizeViewRepresentable(width: 50, height: 50, label: "Test")
    )
    let identified = IdentifiedNode.view(key: "test", representable)

    guard case let .primitive(primitive) = identified.node.content else {
      Issue.record("Expected primitive content")
      return
    }
    guard case .customView = primitive else {
      Issue.record("Expected customView primitive")
      return
    }
    #expect(identified.id == AnyHashable("test"))
  }
}
