import Foundation
import SwiftUI

// Private diagnostic fork only: the mounted app test supplies its resource load ID so
// attachment-task events can be matched to the native interaction it inspects.
private struct AttachmentDiagnosticLoadIDKey: EnvironmentKey {
  static let defaultValue: UUID? = nil
}

public extension EnvironmentValues {
  var mostlytextAttachmentDiagnosticLoadID: UUID? {
    get { self[AttachmentDiagnosticLoadIDKey.self] }
    set { self[AttachmentDiagnosticLoadIDKey.self] = newValue }
  }
}

private func traceAttachment(
  _ phase: String, loadID: UUID?, modelID: UUID, requestID: UUID? = nil,
  detail: String = ""
) {
  guard let loadID else { return }
  print("TEXTUAL_ATTACHMENT_INSTANCE loadID=\(loadID.uuidString) modelID=\(modelID.uuidString) "
    + "requestID=\(requestID?.uuidString ?? "none") phase=\(phase) \(detail)")
}

// MARK: - Overview
//
// `WithAttachments` resolves attachment references in an `AttributedString`.
//
// Markup parsing keeps some items as URL attributes:
// - `run.imageURL` for images
// - `run.textual.emojiURL` for custom emoji references emitted by pattern expansion
//
// This view asynchronously loads those URLs using the environment-provided attachment loaders and
// writes the resolved attachments back into the attributed string as `Textual.Attachment`
// attributes. The rest of the rendering pipeline treats attachment runs like any other span.

struct WithAttachments<Content: View>: View {
  @Environment(\.imageAttachmentLoader) private var imageAttachmentLoader
  @Environment(\.emojiAttachmentLoader) private var emojiAttachmentLoader
  @Environment(\.colorEnvironment) private var colorEnvironment
  @Environment(\.mostlytextAttachmentDiagnosticLoadID) private var diagnosticLoadID

  @State private var model = Model()

  private let attributedString: AttributedString
  private let content: (AttributedString) -> Content

  init(
    _ attributedString: AttributedString,
    @ViewBuilder content: @escaping (AttributedString) -> Content
  ) {
    self.attributedString = attributedString
    self.content = content
  }

  var body: some View {
    content(model.resolvedAttributedString ?? attributedString)
      .task(id: attributedString) {
        await model.resolveAttachments(
          in: attributedString,
          imageAttachmentLoader: imageAttachmentLoader,
          emojiAttachmentLoader: emojiAttachmentLoader,
          environment: colorEnvironment,
          diagnosticLoadID: diagnosticLoadID
        )
      }
  }
}

extension WithAttachments {
  @MainActor @Observable final class Model {
    var resolvedAttributedString: AttributedString?
    @ObservationIgnored private let diagnosticModelID = UUID()
    @ObservationIgnored private var requestIdentity: UUID?

    func resolveAttachments(
      in attributedString: AttributedString,
      imageAttachmentLoader: any AttachmentLoader,
      emojiAttachmentLoader: any AttachmentLoader,
      environment: ColorEnvironmentValues,
      diagnosticLoadID: UUID?
    ) async {
      let imageURLs = attributedString.runs.compactMap { $0.imageURL }
      let imageReferences = imageURLs.map { "\($0.scheme ?? "relative"):\($0.lastPathComponent)" }
      traceAttachment("task-enter", loadID: diagnosticLoadID, modelID: diagnosticModelID,
        detail: "imageURLCount=\(imageURLs.count) imageReferences=\(imageReferences)")
      // A task cancelled before entry must not clear a newer request's result.
      guard !Task.isCancelled else {
        traceAttachment("cancelled-before-clear", loadID: diagnosticLoadID,
          modelID: diagnosticModelID)
        return
      }
      requestIdentity = nil
      resolvedAttributedString = nil
      traceAttachment("state-cleared", loadID: diagnosticLoadID, modelID: diagnosticModelID)
      guard attributedString.containsValues(for: [\.imageURL, \.textual.emojiURL]) else {
        traceAttachment("no-attachment-reference", loadID: diagnosticLoadID,
          modelID: diagnosticModelID)
        return
      }
      let requestID = UUID()
      requestIdentity = requestID
      let modelID = diagnosticModelID
      traceAttachment("request-started", loadID: diagnosticLoadID,
        modelID: diagnosticModelID, requestID: requestID)

      var attachments: [AnyAttachment] = []
      var ranges: [Range<AttributedString.Index>] = []

      await withTaskGroup(
        of: (AnyAttachment?, Range<AttributedString.Index>).self
      ) { group in
        for run in attributedString.runs {
          if let imageURL = run.imageURL {
            group.addTask {
              let attachment = try? await imageAttachmentLoader.attachment(
                for: imageURL,
                text: String(attributedString[run.range].characters[...]),
                environment: environment
              )
              traceAttachment("image-loader-returned", loadID: diagnosticLoadID,
                modelID: modelID, requestID: requestID,
                detail: "reference=\(imageURL.scheme ?? "relative"):\(imageURL.lastPathComponent) "
                  + "hasAttachment=\(attachment != nil) cancelled=\(Task.isCancelled)")
              return (attachment.map(AnyAttachment.init), run.range)
            }
          } else if let emojiURL = run.textual.emojiURL {
            group.addTask {
              let attachment = try? await emojiAttachmentLoader.attachment(
                for: emojiURL,
                text: String(attributedString[run.range].characters[...]),
                environment: environment
              )
              return (attachment.map(AnyAttachment.init), run.range)
            }
          }
        }

        for await (attachment, range) in group {
          guard let attachment else { continue }

          attachments.append(attachment)
          ranges.append(range)
        }
      }

      traceAttachment("children-finished", loadID: diagnosticLoadID,
        modelID: diagnosticModelID, requestID: requestID,
        detail: "resolvedCount=\(attachments.count) cancelled=\(Task.isCancelled)")

      // Loaders may finish after cancellation or a newer request. Publication stays with this source.
      let identityMatches = requestIdentity == requestID
      guard identityMatches, !Task.isCancelled else {
        traceAttachment("publication-refused", loadID: diagnosticLoadID,
          modelID: diagnosticModelID, requestID: requestID,
          detail: "identityMatches=\(identityMatches) cancelled=\(Task.isCancelled)")
        return
      }
      resolveAttachmentsFinished(
        attributedString: attributedString,
        attachments: Array(zip(ranges, attachments))
      )
      let publishedCount = resolvedAttributedString?.runs.filter {
        $0.textual.attachment != nil
      }.count ?? 0
      traceAttachment("published", loadID: diagnosticLoadID,
        modelID: diagnosticModelID, requestID: requestID,
        detail: "resolvedCount=\(attachments.count) publishedAttachmentRuns=\(publishedCount)")
    }

    private func resolveAttachmentsFinished(
      attributedString: AttributedString,
      attachments: [(Range<AttributedString.Index>, AnyAttachment)]
    ) {
      var attributedString = attributedString

      for (range, attachment) in attachments {
        attributedString[range].textual.attachment = attachment
      }

      self.resolvedAttributedString = attributedString
    }
  }
}
