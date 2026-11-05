import Foundation
public import SwiftUIMath

extension AnyAttachment {
  /// The placement of an equation in its surrounding text.
  public enum MathStyle: Hashable, Sendable {
    case inline
    case display
  }

  /// Creates the existing native math attachment from an unchanged TeX body.
  ///
  /// Use this after admitting math from original source, before Markdown can
  /// reinterpret its punctuation or escapes. No dollar tokenization occurs.
  /// An optional caller-owned identity distinguishes separate source occurrences;
  /// it is not parsed from authored text or a transient transport marker.
  public static func math(
    latex: String,
    style: MathStyle,
    sourceID: UUID? = nil
  ) -> Self {
    let displayStyle: MathAttachment.DisplayStyle
    switch style {
    case .inline: displayStyle = .inline
    case .display: displayStyle = .block
    }
    return .init(MathAttachment(latex: latex, style: displayStyle, sourceID: sourceID))
  }

  /// Creates the same native attachment with raw-body parsing and the admitted engine limits.
  /// No delimiter detection occurs during metrics, layout or drawing. Source identity is
  /// caller-owned and remains separate from the expression's render-cache identity.
  public static func math(
    body: SwiftUIMath.Math.ValidatedBody,
    style: MathStyle,
    sourceID: UUID? = nil
  ) -> Self {
    let displayStyle: MathAttachment.DisplayStyle
    switch style {
    case .inline: displayStyle = .inline
    case .display: displayStyle = .block
    }
    return .init(MathAttachment(body: body, style: displayStyle, sourceID: sourceID))
  }

}
