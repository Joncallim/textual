import Foundation

extension Formatter {
  func html(
    maxImageBytes: Int = 16 * 1024 * 1024,
    maxTotalImageBytes: Int = 32 * 1024 * 1024
  ) -> String {
    htmlExport(maxImageBytes: maxImageBytes, maxTotalImageBytes: maxTotalImageBytes).string
  }

  func htmlExport(
    maxImageBytes: Int = 16 * 1024 * 1024,
    maxTotalImageBytes: Int = 32 * 1024 * 1024,
    memoryLedger: HTMLImageMemoryLedger = .shared
  ) -> HTMLExport {
    let budget = HTMLImageBudget(
      maxImageBytes: maxImageBytes, maxTotalImageBytes: maxTotalImageBytes,
      memoryLedger: memoryLedger
    )
    return HTMLExport(string: blockNodes.renderHTML(imageBudget: budget), budget: budget)
  }
}

/// Keep the image reservations with the HTML through pasteboard or item-provider handoff.
/// Recipient and framework retention after handoff are outside this ledger.
final class HTMLExport {
  let string: String
  private let budget: HTMLImageBudget

  fileprivate init(string: String, budget: HTMLImageBudget) {
    self.string = string
    self.budget = budget
  }
}

/// Conservative admission for concurrent app-owned image-derived PNG, base64, HTML and UTF-8
/// storage. Ordinary text, allocator capacity, legacy encoder temporaries and framework retention
/// are outside this ledger. The factor is an allowance, not a measured process-memory ceiling.
final class HTMLImageMemoryLedger: @unchecked Sendable {
  static let shared = HTMLImageMemoryLedger(limitBytes: 256 * 1024 * 1024)
  private static let bytesPerEncodedByte = 8

  final class Reservation {
    private let ledger: HTMLImageMemoryLedger
    private var chargedBytes: Int
    let byteLimit: Int

    fileprivate init(ledger: HTMLImageMemoryLedger, byteLimit: Int) {
      self.ledger = ledger
      self.byteLimit = byteLimit
      chargedBytes = byteLimit * HTMLImageMemoryLedger.bytesPerEncodedByte
    }

    func shrink(toEncodedBytes count: Int) {
      precondition(count >= 0 && count <= byteLimit)
      let newCharge = count * HTMLImageMemoryLedger.bytesPerEncodedByte
      ledger.lock.withLock {
        precondition(newCharge <= chargedBytes)
        ledger.heldBytes -= chargedBytes - newCharge
        chargedBytes = newCharge
      }
    }

    deinit { ledger.lock.withLock { ledger.heldBytes -= chargedBytes } }
  }

  private let lock = NSLock()
  private let limitBytes: Int
  private var heldBytes = 0

  init(limitBytes: Int) { self.limitBytes = max(0, limitBytes) }

  var reservedBytes: Int { lock.withLock { heldBytes } }

  func reserve(upToEncodedBytes requested: Int) -> Reservation? {
    lock.withLock {
      guard requested > 0 else { return nil }
      let available = (limitBytes - heldBytes) / Self.bytesPerEncodedByte
      let admitted = min(requested, available)
      guard admitted > 0 else { return nil }
      heldBytes += admitted * Self.bytesPerEncodedByte
      return Reservation(ledger: self, byteLimit: admitted)
    }
  }
}

/// One synchronous export's encoded image quota. This bounds retained PNG/base64 data even
/// when an attributed document repeats the same image many times.
private final class HTMLImageBudget {
  private let maxImageBytes: Int
  private let memoryLedger: HTMLImageMemoryLedger
  private var reservations: [HTMLImageMemoryLedger.Reservation] = []
  private(set) var remaining: Int

  init(maxImageBytes: Int, maxTotalImageBytes: Int, memoryLedger: HTMLImageMemoryLedger) {
    self.maxImageBytes = max(0, maxImageBytes)
    remaining = max(0, maxTotalImageBytes)
    self.memoryLedger = memoryLedger
  }

  func admit(_ attachment: AnyAttachment) -> Data? {
    let limit = min(maxImageBytes, remaining)
    guard let reservation = memoryLedger.reserve(upToEncodedBytes: limit),
      let data = attachment.boundedPNGData(maxBytes: reservation.byteLimit),
      !data.isEmpty, data.count <= reservation.byteLimit
    else { return nil }
    reservation.shrink(toEncodedBytes: data.count)
    reservations.append(reservation)
    remaining -= data.count
    return data
  }
}

// MARK: - Inline rendering

extension Formatter.InlineNode {
  fileprivate func renderHTML(imageBudget: HTMLImageBudget) -> String {
    switch self {
    case .text(let text):
      return text.htmlEscaped()
    case .code(let code):
      return "<code>\(code.htmlEscaped())</code>"
    case .strong(let children):
      return "<strong>\(children.renderHTML(imageBudget: imageBudget))</strong>"
    case .emphasized(let children):
      return "<em>\(children.renderHTML(imageBudget: imageBudget))</em>"
    case .strikethrough(let children):
      return "<del>\(children.renderHTML(imageBudget: imageBudget))</del>"
    case .link(let url, let children):
      let href = url.absoluteString.htmlAttributeEscaped()
      return #"<a href="\#(href)">\#(children.renderHTML(imageBudget: imageBudget))</a>"#
    case .lineBreak:
      return "<br />"
    case .attachment(let attachment):
      guard let imageData = imageBudget.admit(attachment) else {
        return attachment.description.htmlEscaped()
      }
      let base64 = imageData.base64EncodedString()
      return #"<img src="data:image/png;base64,\#(base64)" />"#
    }
  }
}

extension Array where Element == Formatter.InlineNode {
  fileprivate func renderHTML(imageBudget: HTMLImageBudget) -> String {
    self.map {
      $0.renderHTML(imageBudget: imageBudget)
    }.joined()
  }
}

// MARK: - Block rendering

extension Formatter.BlockNode {
  fileprivate func renderHTML(imageBudget: HTMLImageBudget) -> String {
    switch self {
    case .paragraph(let children):
      return "<p>\(children.renderHTML(imageBudget: imageBudget))</p>"
    case .header(let level, let children):
      let l = max(1, min(6, level))
      return "<h\(l)>\(children.renderHTML(imageBudget: imageBudget))</h\(l)>"
    case .orderedList(let children):
      let start = children.map(\.ordinal).min() ?? 1
      let startAttribute = start > 1 ? #" start="\#(start)""# : ""
      return "<ol\(startAttribute)>\n\(children.renderHTML(imageBudget: imageBudget))\n</ol>"
    case .unorderedList(let children):
      return "<ul>\n\(children.renderHTML(imageBudget: imageBudget))\n</ul>"
    case .codeBlock(let languageHint, let code):
      let classAttribute =
        languageHint.flatMap {
          $0.isEmpty ? nil : $0
        }.map {
          #" class="language-\#($0.htmlAttributeEscaped())""#
        } ?? ""
      return "<pre><code\(classAttribute)>\(code.htmlCodeEscaped())</code></pre>"
    case .blockQuote(let children):
      return "<blockquote>\n\(children.renderHTML(imageBudget: imageBudget))\n</blockquote>"
    case .table(let columns, let children):
      guard
        let headerHTML = children.first?.renderHeaderHTML(
          columns: columns, imageBudget: imageBudget)
      else {
        return "<table></table>"
      }
      let bodyHTML = Array(children.dropFirst()).renderHTML(
        columns: columns, imageBudget: imageBudget)

      if bodyHTML.isEmpty {
        return "<table>\n<thead>\n\(headerHTML)\n</thead>\n</table>"
      } else {
        return "<table>\n<thead>\n\(headerHTML)\n</thead>\n\(bodyHTML)\n</table>"
      }
    case .thematicBreak:
      return "<hr />"
    }
  }
}

extension Array where Element == Formatter.BlockNode {
  fileprivate func renderHTML(imageBudget: HTMLImageBudget) -> String {
    self.map {
      $0.renderHTML(imageBudget: imageBudget)
    }.joined(separator: "\n")
  }
}

// MARK: - Table rendering

extension Formatter.TableRow {
  fileprivate func renderHeaderHTML(
    columns: [PresentationIntent.TableColumn], imageBudget: HTMLImageBudget
  ) -> String {
    renderHTML("th", columns: columns, imageBudget: imageBudget)
  }

  fileprivate func renderDataHTML(
    columns: [PresentationIntent.TableColumn], imageBudget: HTMLImageBudget
  ) -> String {
    renderHTML("td", columns: columns, imageBudget: imageBudget)
  }

  private func renderHTML(
    _ element: String,
    columns: [PresentationIntent.TableColumn],
    imageBudget: HTMLImageBudget
  ) -> String {
    let alignments = columns.map(\.alignment)
    let cells = zip(alignments, self.cells).map { alignment, inlines in
      #"<\#(element) align="\#(alignment)">\#(inlines.renderHTML(imageBudget: imageBudget))</\#(element)>"#
    }
    return "<tr>\n\(cells.joined(separator: "\n"))\n</tr>"
  }
}

extension Array where Element == Formatter.TableRow {
  fileprivate func renderHTML(
    columns: [PresentationIntent.TableColumn], imageBudget: HTMLImageBudget
  ) -> String {
    self.map {
      $0.renderDataHTML(columns: columns, imageBudget: imageBudget)
    }.joined(separator: "\n")
  }
}

// MARK: - List rendering

extension Formatter.ListItem {
  fileprivate func renderHTML(imageBudget: HTMLImageBudget) -> String {
    // NB: Tight vs. loose list detection. When Markdown has blank lines between list items,
    //     the parser creates multiple paragraph blocks. Single paragraph = tight (no <p> tags),
    //     multiple paragraphs = loose (wrap content in <p> tags).
    let paragraphCount = blocks.filter {
      if case .paragraph = $0 { return true }
      return false
    }.count

    // Tight list - single paragraph
    if paragraphCount == 1,
      blocks.count == 1,
      case .paragraph(let children) = blocks[0]
    {
      return "<li>\(children.renderHTML(imageBudget: imageBudget))</li>"
    }

    // Tight list with single paragraph + other blocks (nested lists, etc.)
    if paragraphCount == 1,
      let firstParagraphIndex = blocks.firstIndex(where: {
        if case .paragraph = $0 { return true }
        return false
      }),
      case .paragraph(let children) = blocks[firstParagraphIndex]
    {
      let otherBlocks = blocks.enumerated().filter { $0.offset != firstParagraphIndex }.map {
        $0.element
      }
      let paragraphHTML = children.renderHTML(imageBudget: imageBudget)
      let otherHTML = otherBlocks.renderHTML(imageBudget: imageBudget)
      return "<li>\(paragraphHTML)\(otherHTML)</li>"
    }

    // Loose list - multiple paragraphs mean blank lines existed
    return "<li>\(blocks.renderHTML(imageBudget: imageBudget))</li>"
  }
}

extension Array where Element == Formatter.ListItem {
  fileprivate func renderHTML(imageBudget: HTMLImageBudget) -> String {
    self.map {
      $0.renderHTML(imageBudget: imageBudget)
    }.joined(separator: "\n")
  }
}

// MARK: - String escaping

extension String {
  // For text content. Escapes &, <, >, and non-ASCII characters.
  fileprivate func htmlEscaped() -> String {
    var result = ""
    result.reserveCapacity(utf8.count)

    for scalar in self.unicodeScalars {
      switch scalar.value {
      case 0x26:  // &
        result.append("&amp;")
      case 0x3C:  // <
        result.append("&lt;")
      case 0x3E:  // >
        result.append("&gt;")
      case 0x20...0x7E:
        result.append(Character(scalar))
      default:
        result.append("&#\(scalar.value);")
      }
    }

    return result
  }

  // For code blocks. Only escapes &, <, > to preserve whitespace.
  fileprivate func htmlCodeEscaped() -> String {
    var result = ""
    result.reserveCapacity(utf8.count)

    for scalar in self.unicodeScalars {
      switch scalar.value {
      case 0x26:  // &
        result.append("&amp;")
      case 0x3C:  // <
        result.append("&lt;")
      case 0x3E:  // >
        result.append("&gt;")
      default:
        result.append(Character(scalar))
      }
    }

    return result
  }

  // For attribute values. Escapes &, <, >, ", and non-ASCII characters.
  fileprivate func htmlAttributeEscaped() -> String {
    var result = ""
    result.reserveCapacity(utf8.count)

    for scalar in self.unicodeScalars {
      switch scalar.value {
      case 0x26:  // &
        result.append("&amp;")
      case 0x3C:  // <
        result.append("&lt;")
      case 0x3E:  // >
        result.append("&gt;")
      case 0x22:  // "
        result.append("&quot;")
      case 0x20...0x7E:
        result.append(Character(scalar))
      default:
        result.append("&#\(scalar.value);")
      }
    }

    return result
  }
}
