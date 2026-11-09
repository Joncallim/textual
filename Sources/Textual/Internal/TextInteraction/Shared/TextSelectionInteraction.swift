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

    @State private var model = TextSelectionModel()
    @State private var layoutHandoff = LatestMainActorHandoff<SelectionLayoutOffer> { offer in
      offer.apply()
    }
  #endif

  func body(content: Content) -> some View {
    #if TEXTUAL_ENABLE_TEXT_SELECTION
      if textSelection.allowsSelection {
        content
          .overlayTextLayoutCollection { layoutCollection in
            let offer = SelectionLayoutOffer(
              layoutCollection: layoutCollection,
              model: model,
              coordinator: coordinator
            )
            let _ = layoutHandoff.offer(offer)
            Color.clear
              .onAppear {
                layoutHandoff.appear()
              }
              .onDisappear {
                layoutHandoff.disappear()
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
  private struct SelectionLayoutOffer {
    let layoutCollection: any TextLayoutCollection
    let model: TextSelectionModel
    let coordinator: TextSelectionCoordinator?

    @MainActor
    func apply() {
      model.setCoordinator(coordinator)
      model.setLayoutCollection(layoutCollection)
    }
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
