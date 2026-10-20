import Foundation
import UniformTypeIdentifiers

final class TransferableText: NSObject {
  let attributedString: NSAttributedString

  init(attributedString: NSAttributedString) {
    // Preserve the item provider's source snapshot if its caller supplied a mutable subclass.
    self.attributedString = NSAttributedString(attributedString: attributedString)
    super.init()
  }
}

extension TransferableText: NSItemProviderWriting {
  static var writableTypeIdentifiersForItemProvider: [String] {
    [UTType.plainText.identifier, UTType.html.identifier]
  }

  func loadData(
    withTypeIdentifier typeIdentifier: String,
    forItemProviderCompletionHandler completionHandler: @escaping (Data?, (any Error)?) -> Void
  ) -> Progress? {
    // Item providers may request representations concurrently; Formatter's lazy nodes are local
    // to this request rather than shared between callbacks.
    let formatter = Formatter(attributedString)
    switch typeIdentifier {
    case UTType.plainText.identifier:
      completionHandler(formatter.plainText().data(using: .utf8), nil)
    case UTType.html.identifier:
      let export = formatter.htmlExport()
      withExtendedLifetime(export) {
        completionHandler(export.string.data(using: .utf8), nil)
      }
    default:
      completionHandler(nil, nil)
    }
    return nil
  }
}
