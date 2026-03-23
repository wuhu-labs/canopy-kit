import SwiftUI

// MARK: - Custom Drawing

public protocol CustomDrawing: CustomViewRepresentable {
  @MainActor
  func draw(in context: CGContext, commitment: Commitment)
}

extension CustomDrawing {
  @MainActor
  public func makeView(commitment: Commitment) -> some View {
    CustomDrawingView(customDrawing: self, commitment: commitment)
  }
}

private struct CustomDrawingView<CD: CustomDrawing>: View {
  let customDrawing: CD
  let commitment: CD.Commitment

  var body: some View {
    Canvas { context, size in
      context.withCGContext { cgContext in
        customDrawing.draw(
          in: cgContext,
          commitment: commitment
        )
      }
    }
  }
}
