import CoreGraphics
import Testing
@testable import CanopyKit

@MainActor
@Suite struct ToolCallLayoutTests {
  @Test func toolCallBarShrinksOnCollapse() async {
    let model = ChatToolCallModel(
      id: "tc-1",
      name: "read",
      arguments: "{\"path\": \"test.swift\"}",
      result: String(repeating: "line\n", count: 20),
      isExpanded: true
    )

    let renderer = ComponentRenderer(root: AnyComponent(ToolCallComponent(model: model)))
    let runtime = RenderRuntime()
    let width: CGFloat = 400
    let proposal = ProposedSize(width: width, height: nil)

    // Measure expanded
    let expandedSize = runtime.sizeThatFits(root: renderer.resolvedRoot, proposal: proposal)
    print("Expanded size: \(expandedSize)")

    // Simulate what happens in the real app: toggle, wait for observation, refresh
    model.isExpanded = false
    // Let the observation onChange Task fire
    await Task.yield()
    await Task.yield()
    renderer.refresh()

    let collapsedSize = runtime.sizeThatFits(root: renderer.resolvedRoot, proposal: proposal)
    print("Collapsed size: \(collapsedSize)")

    #expect(
      collapsedSize.height < expandedSize.height,
      "Collapsed (\(collapsedSize.height)) should be less than expanded (\(expandedSize.height))"
    )

    // Now simulate expand again
    model.isExpanded = true
    await Task.yield()
    await Task.yield()
    renderer.refresh()

    let reExpandedSize = runtime.sizeThatFits(root: renderer.resolvedRoot, proposal: proposal)
    print("Re-expanded size: \(reExpandedSize)")

    #expect(
      reExpandedSize.height == expandedSize.height,
      "Re-expanded (\(reExpandedSize.height)) should equal original expanded (\(expandedSize.height))"
    )

    // And collapse once more
    model.isExpanded = false
    await Task.yield()
    await Task.yield()
    renderer.refresh()

    let reCollapsedSize = runtime.sizeThatFits(root: renderer.resolvedRoot, proposal: proposal)
    print("Re-collapsed size: \(reCollapsedSize)")

    #expect(
      reCollapsedSize.height == collapsedSize.height,
      "Re-collapsed (\(reCollapsedSize.height)) should equal original collapsed (\(collapsedSize.height))"
    )

    // Check all leaf frames in collapsed state
    let renderRoot = runtime.layout(
      root: renderer.resolvedRoot,
      proposal: proposal
    )

    func checkFrames(_ node: ResolvedRenderNode, depth: Int = 0) {
      let indent = String(repeating: "  ", count: depth)
      print("\(indent)\(node.id): \(node.frame)")
      #expect(
        node.frame.height <= reCollapsedSize.height + 0.001,
        "Node \(node.id) frame height \(node.frame.height) exceeds collapsed height \(reCollapsedSize.height)"
      )
      for child in node.children {
        checkFrames(child, depth: depth + 1)
      }
    }
    checkFrames(renderRoot)
  }

  // Test that the ComponentRenderer's automatic refresh (via observation)
  // correctly updates the resolved tree when isExpanded changes
  @Test func observationDrivenRefresh() async throws {
    let model = ChatToolCallModel(
      id: "tc-1",
      name: "bash",
      arguments: "{\"command\": \"echo hello\"}",
      result: "hello\n",
      isExpanded: false
    )

    let renderer = ComponentRenderer(root: AnyComponent(ToolCallComponent(model: model)))

    let initialRevision = renderer.revision

    // Toggle expand
    model.isExpanded = true

    // Wait for the scheduled refresh to fire
    // scheduleRefresh dispatches Task { yield; refresh() }
    // onChange dispatches Task { markDirty; scheduleRefresh }
    // So we need multiple yields
    for _ in 0..<10 {
      await Task.yield()
    }

    let newRevision = renderer.revision
    print("Initial revision: \(initialRevision), after toggle: \(newRevision)")
    #expect(newRevision > initialRevision, "Renderer should have incremented revision after observation-driven refresh")
  }
}
