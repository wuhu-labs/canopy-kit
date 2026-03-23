@testable import CanopyKit
import Testing

private struct TestIntKey: NodeValueKey {
  static let defaultValue = 0
}

private struct TestStringKey: NodeValueKey {
  static let defaultValue = "default"
}

@Suite struct NodeValuesTests {
  @Test func returnsDefaultValueWhenMissing() {
    let values = NodeValues()

    #expect(values[TestIntKey.self] == 0)
    #expect(values[TestStringKey.self] == "default")
  }

  @Test func returnsStoredValueForMatchingKey() {
    var values = NodeValues()
    values[TestIntKey.self] = 42
    values[TestStringKey.self] = "hello"

    #expect(values[TestIntKey.self] == 42)
    #expect(values[TestStringKey.self] == "hello")
  }
}
