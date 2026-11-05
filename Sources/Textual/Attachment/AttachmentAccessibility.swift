import Foundation
import SwiftUI

/// Caller-localized semantics for an attachment's actual inline occurrence.
/// An action identifier is opaque: the host decides whether a source action is current.
public struct AttachmentAccessibility: Sendable, Hashable {
  public let label: String
  public let actionID: UUID?
  public let actionName: String?

  public init(label: String, actionID: UUID? = nil, actionName: String? = nil) {
    self.label = label
    self.actionID = actionID
    self.actionName = actionName
  }
}

extension AnyAttachment {
  /// Supplies semantics without replacing the attachment's drawing or measurement.
  public func withAccessibility(_ descriptor: AttachmentAccessibility) -> Self {
    // Replacing a descriptor retains a single semantic wrapper.
    let underlying = (base as? AccessibleAttachment)?.base ?? self
    return .init(AccessibleAttachment(base: underlying, descriptor: descriptor))
  }

  var isDisplayMath: Bool {
    if let wrapper = base as? AccessibleAttachment {
      return wrapper.base.isDisplayMath
    }
    guard let math = base as? MathAttachment, case .block = math.displayStyle else {
      return false
    }
    return true
  }
}

extension TextualNamespace where Base: View {
  /// Handles an explicitly described attachment action. The host must validate
  /// the opaque occurrence identifier against its current document before acting.
  @MainActor public func attachmentAccessibilityAction(
    _ action: @escaping @MainActor @Sendable (UUID) -> Void
  ) -> some View {
    base.environment(\.attachmentAccessibilityAction, action)
  }
}

extension EnvironmentValues {
  @Entry var attachmentAccessibilityAction: (@MainActor @Sendable (UUID) -> Void)?
}

private struct AccessibleAttachment: Attachment {
  let base: AnyAttachment
  let descriptor: AttachmentAccessibility
  var accessibility: AttachmentAccessibility? { descriptor }
  var description: String { base.description }
  var selectionStyle: AttachmentSelectionStyle { base.selectionStyle }
  var body: some View { base.body.modifier(AttachmentAccessibilityModifier(descriptor: descriptor)) }
  func baselineOffset(in environment: TextEnvironmentValues) -> CGFloat {
    base.baselineOffset(in: environment)
  }
  func sizeThatFits(_ proposal: ProposedViewSize, in environment: TextEnvironmentValues) -> CGSize {
    base.sizeThatFits(proposal, in: environment)
  }
  func pngData() -> Data? { base.pngData() }
  func boundedPNGData(maxBytes: Int) -> Data? { base.boundedPNGData(maxBytes: maxBytes) }
}

struct AttachmentAccessibilityModifier: ViewModifier {
  @Environment(\.attachmentAccessibilityAction) private var action
  let descriptor: AttachmentAccessibility

  func body(content: Content) -> some View {
    let element = content.accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: descriptor.label))
      .accessibilityAddTraits(.isImage)
    if let action, let id = descriptor.actionID, let name = descriptor.actionName, !name.isEmpty {
      element.accessibilityAction(named: Text(verbatim: name)) { action(id) }
    } else {
      element
    }
  }
}
