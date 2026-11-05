import SwiftUI

// MARK: - Overview
//
// `AttachmentView` draws attachment bodies at the positions reported by SwiftUI's `Text.Layout`.
//
// The `Text` pipeline reserves space for attachments using placeholders; the overlay draws the
// real SwiftUI views on top of those placeholders. Drawing uses a `Canvas` so attachment views can
// be resolved once as symbols and efficiently drawn into each run's `typographicBounds`.
//
// Selection integration:
// On macOS, when text selection is enabled, object-style attachments are dimmed when they fall
// inside the selected range. Inline-style attachments (for example, emoji) are not dimmed.

struct AttachmentView: View {
  #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
    @Environment(TextSelectionModel.self) private var textSelectionModel: TextSelectionModel?
  #endif
  private let attachments: Set<AnyAttachment>
  private let origin: CGPoint
  private let layout: Text.Layout

  init(
    attachments: Set<AnyAttachment>,
    origin: CGPoint,
    layout: Text.Layout
  ) {
    self.attachments = attachments
    self.origin = origin
    self.layout = layout
  }

  var body: some View {
    Canvas { context, _ in
      context.translateBy(x: origin.x, y: origin.y)
      for (lineIndex, line) in zip(layout.indices, layout) {
        for (runIndex, run) in zip(line.indices, line) {
          guard
            let attachment = run.attachment,
            let symbol = context.resolveSymbol(id: attachment)
          else {
            continue
          }

          context.opacity = opacity(
            for: attachment,
            lineIndex: lineIndex,
            runIndex: runIndex
          )

          context.draw(symbol, in: run.typographicBounds.rect)
        }
      }
    } symbols: {
      ForEach(Array(attachments), id: \.self) { attachment in
        attachment.body
          .tag(attachment)
      }
    }
    .overlay(alignment: .topLeading) { accessibilityElements }
  }

  /// Canvas draws symbols but does not publish the symbol views' semantics.
  /// Keep a separate, non-intercepting semantic element at each actual run rect.
  private var accessibilityElements: some View {
    ZStack(alignment: .topLeading) {
      ForEach(accessibleRuns) { run in
        Color.clear
          .frame(width: run.rect.width, height: run.rect.height)
          .modifier(AttachmentAccessibilityModifier(descriptor: run.descriptor))
          .position(x: run.rect.midX, y: run.rect.midY)
      }
    }
    .allowsHitTesting(false)
  }

  private struct AccessibleRun: Identifiable {
    let id: String
    let descriptor: AttachmentAccessibility
    let rect: CGRect
  }

  private var accessibleRuns: [AccessibleRun] {
    var result: [AccessibleRun] = []
    for (lineIndex, line) in zip(layout.indices, layout) {
      for (runIndex, run) in zip(line.indices, line) {
        guard let descriptor = run.attachment?.accessibility else { continue }
        let rect = run.typographicBounds.rect.offsetBy(dx: origin.x, dy: origin.y)
        guard rect.minX.isFinite, rect.minY.isFinite, rect.width.isFinite, rect.height.isFinite,
          rect.width > 0, rect.height > 0 else { continue }
        result.append(AccessibleRun(id: "\(lineIndex):\(runIndex)", descriptor: descriptor, rect: rect))
      }
    }
    return result
  }

  private func opacity(
    for attachment: AnyAttachment,
    lineIndex: Int,
    runIndex: Int
  ) -> CGFloat {
    #if TEXTUAL_ENABLE_TEXT_SELECTION && canImport(AppKit)
      guard
        attachment.selectionStyle == .object,
        let textSelectionModel,
        let selectedRange = textSelectionModel.selectedRange,
        let layoutIndex = textSelectionModel.layoutIndex(of: layout)
      else {
        return 1
      }

      let position = TextPosition(
        indexPath: .init(run: runIndex, line: lineIndex, layout: layoutIndex),
        affinity: .downstream
      )

      return selectedRange.contains(position) ? 0.5 : 1
    #else
      1
    #endif
  }
}
