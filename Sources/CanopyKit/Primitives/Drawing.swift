import CoreGraphics

// MARK: - Custom Drawing

public protocol CustomDrawing {
  associatedtype Cache
  associatedtype Commitment

  func makeCache() -> Cache
  func updateCache(_ cache: inout Cache)
  func sizeThatFits(proposal: ProposedSize, cache: inout Cache) -> CGSize
  func makeCommitment(in bounds: CGRect, cache: Cache) -> Commitment
  func draw(in context: CGContext, commitment: Commitment)
}

public extension CustomDrawing {
  func updateCache(_ cache: inout Cache) {
    cache = makeCache()
  }
}

// MARK: - AnyDrawing

public struct AnyDrawing: @unchecked Sendable {
  private let value: any CustomDrawing

  public init(_ drawing: some CustomDrawing) {
    value = drawing
  }

  func makeCache() -> Any {
    value.makeCache()
  }

  func updateCache(cache: inout Any) {
    updateDrawingCache(drawing: value, cache: &cache)
  }

  func sizeThatFits(proposal: ProposedSize, cache: inout Any) -> CGSize {
    drawingSizeThatFits(drawing: value, proposal: proposal, cache: &cache)
  }

  func makeCommitment(in bounds: CGRect, cache: Any) -> Any {
    drawingMakeCommitment(drawing: value, in: bounds, cache: cache)
  }

  func draw(in context: CGContext, commitment: Any) {
    drawingDraw(drawing: value, in: context, commitment: commitment)
  }

  func isEquivalent(to other: AnyDrawing) -> Bool {
    compareDrawing(lhs: value, rhs: other.value)
  }
}

private func compareDrawing<D: CustomDrawing>(lhs: D, rhs: any CustomDrawing) -> Bool {
  guard let rhs = rhs as? D else { return false }
  return defaultValueIsEquivalent(lhs, rhs)
}

private func updateDrawingCache<D: CustomDrawing>(drawing: D, cache: inout Any) {
  guard var typedCache = cache as? D.Cache else {
    cache = drawing.makeCache()
    return
  }
  drawing.updateCache(&typedCache)
  cache = typedCache
}

private func drawingSizeThatFits<D: CustomDrawing>(drawing: D, proposal: ProposedSize, cache: inout Any) -> CGSize {
  var typedCache = cache as! D.Cache
  let size = drawing.sizeThatFits(proposal: proposal, cache: &typedCache)
  cache = typedCache
  return size
}

private func drawingMakeCommitment<D: CustomDrawing>(drawing: D, in bounds: CGRect, cache: Any) -> Any {
  let typedCache = cache as! D.Cache
  return drawing.makeCommitment(in: bounds, cache: typedCache)
}

private func drawingDraw<D: CustomDrawing>(drawing: D, in context: CGContext, commitment: Any) {
  let typedCommitment = commitment as! D.Commitment
  drawing.draw(in: context, commitment: typedCommitment)
}
