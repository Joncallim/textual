import SwiftUI
@_spi(Textual) import SwiftUIMath

struct MathAttachment: Attachment {
  enum DisplayStyle: Sendable {
    case inline
    case block
  }

  var description: String {
    switch displayStyle {
    case .inline:
      return "$\(latex)$"
    case .block:
      return "$$\(latex)$$"
    }
  }

  var selectionStyle: AttachmentSelectionStyle {
    .text
  }

  let latex: String
  let displayStyle: DisplayStyle
  let sourceID: UUID?
  let validatedBody: Math.ValidatedBody?

  init(latex: String, style: DisplayStyle, sourceID: UUID? = nil) {
    self.latex = latex
    self.displayStyle = style
    self.sourceID = sourceID
    self.validatedBody = nil
  }

  init(body: Math.ValidatedBody, style: DisplayStyle, sourceID: UUID? = nil) {
    self.latex = body.source
    self.displayStyle = style
    self.sourceID = sourceID
    self.validatedBody = body
  }

  var body: some View {
    MathView(latex: latex, validatedBody: validatedBody, style: displayStyle)
  }

  func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat {
    -typographicBounds(in: environment).descent
  }

  func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
    typographicBounds(fitting: proposal, in: environment).size
  }

  private func typographicBounds(
    fitting proposal: ProposedViewSize = .unspecified,
    in environment: TextEnvironmentValues
  ) -> Math.TypographicBounds {
    let font = Math.Font(
      name: .init(environment.mathProperties.fontName),
      size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
    )
    if let validatedBody {
      return Math.typographicBounds(
        for: validatedBody, fitting: proposal, font: font, style: .init(displayStyle)
      )
    }
    return Math.typographicBounds(
      for: latex, fitting: proposal, font: font, style: .init(displayStyle)
    )
  }
}

private struct MathView: View {
  @Environment(\.textEnvironment) private var environment

  let latex: String
  let validatedBody: Math.ValidatedBody?
  let style: MathAttachment.DisplayStyle

  var body: some View {
    math
      .mathFont(
        .init(
          name: .init(environment.mathProperties.fontName),
          size: FontScaled(environment.mathProperties.fontScale).resolve(in: environment)
        )
      )
      .mathTypesettingStyle(.init(style))
      .mathRenderingMode(.monochrome)
  }

  private var math: Math {
    if let validatedBody { Math(validatedBody) } else { Math(latex) }
  }

}

extension Math.Font.Name {
  fileprivate init(_ fontName: MathProperties.FontName) {
    self.init(rawValue: fontName.rawValue)
  }
}

extension Math.TypesettingStyle {
  fileprivate init(_ style: MathAttachment.DisplayStyle) {
    switch style {
    case .inline:
      self = .text
    case .block:
      self = .display
    }
  }
}
