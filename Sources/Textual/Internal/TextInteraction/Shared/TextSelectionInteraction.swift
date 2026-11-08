import SwiftUI

// MARK: - Overview
//
// `TextSelectionInteraction` manages the text selection model lifecycle for multiple `Text` fragments.
//
// Selection is opt-in through the `textSelection` environment value. When enabled, the modifier
// observes text layout changes via `overlayTextLayoutCollection` and creates or updates a
// `TextSelectionModel`. The model is then passed to the platform-specific implementation
// (`PlatformTextSelectionInteraction`), which presents the appropriate selection UI for macOS
// or iOS. This separation keeps model management in shared code while platform interactions
// remain independent.

struct TextSelectionInteraction: ViewModifier {
  #if TEXTUAL_ENABLE_TEXT_SELECTION
    @Environment(\.textSelection) private var textSelection
    @Environment(TextSelectionCoordinator.self) private var coordinator: TextSelectionCoordinator?
    @Environment(\.mostlytextAttachmentDiagnosticLoadID) private var diagnosticLoadID

    @State private var model = TextSelectionModel()
  #endif

  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_TEXT_SELECTION
      if textSelection.allowsSelection {
        content
          .overlayTextLayoutCollection { layoutCollection in
            Color.clear
              .onChange(of: AnyTextLayoutCollection(layoutCollection), initial: true) {
                if let diagnosticLoadID {
                  print("TEXTUAL_SELECTION_LAYOUT loadID=\(diagnosticLoadID.uuidString) "
                    + "modelID=\(ObjectIdentifier(model)) phase=on-change-before "
                    + "offered=\(diagnosticTextLayoutSummary(layoutCollection)) "
                    + "stored=\(model.diagnosticLayoutSummary())")
                }
                model.setCoordinator(coordinator)
                model.setLayoutCollection(layoutCollection)
                if let diagnosticLoadID {
                  print("TEXTUAL_SELECTION_LAYOUT loadID=\(diagnosticLoadID.uuidString) "
                    + "modelID=\(ObjectIdentifier(model)) phase=on-change-after "
                    + "stored=\(model.diagnosticLayoutSummary())")
                }
              }
          }
          .modifier(PlatformTextSelectionInteraction(model: model))
      } else {
        content
      }
    #else
      content
    #endif
  }
}

#if TEXTUAL_ENABLE_TEXT_SELECTION
  func diagnosticTextLayoutSummary(_ collection: any TextLayoutCollection) -> String {
    let layouts = collection.layouts
    let attachmentRuns = layouts.reduce(0) { count, layout in
      let attributed = layout.attributedString
      var runCount = 0
      attributed.enumerateAttribute(
        .textual.attachment,
        in: NSRange(location: 0, length: attributed.length)
      ) { value, _, _ in
        if value != nil { runCount += 1 }
      }
      return count + runCount
    }
    return "layouts=\(layouts.count) attachmentRuns=\(attachmentRuns)"
  }
#endif

#if TEXTUAL_ENABLE_TEXT_SELECTION
  extension EnvironmentValues {
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    @usableFromInline
    @Entry var textSelection: any TextSelectability.Type = DisabledTextSelectability.self
  }
#endif
