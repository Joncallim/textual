import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import Textual

struct BoundedHTMLImageTests {
  @Test func pngEncoderStopsBeforeExceedingOutputLimit() throws {
    let context = try #require(
      CGContext(
        data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
    let image = try #require(context.makeImage())

    #expect(BoundedPNGEncoder.encode(image, maxBytes: 1) == nil)
    #expect(BoundedPNGEncoder.encode(image, maxBytes: 0) == nil)
    #expect(BoundedPNGEncoder.encode(image, maxBytes: -1) == nil)
    let encoded = try #require(BoundedPNGEncoder.encode(image, maxBytes: 1024 * 1024))
    #expect(encoded.count <= 1024 * 1024)
    #expect(encoded.prefix(8) == Data([137, 80, 78, 71, 13, 10, 26, 10]))
    #expect(BoundedPNGEncoder.encode(image, maxBytes: encoded.count) == encoded)
    for _ in 0..<8 {
      #expect(BoundedPNGEncoder.encode(image, maxBytes: encoded.count - 1) == nil)
    }
    #expect(BoundedPNGEncoder.encode(image, maxBytes: encoded.count) == encoded)
  }

  @Test func htmlFallsBackToDescriptionWhenCumulativeImageBudgetRunsOut() {
    let formatter = Formatter(AttributedString())
    let base: any Textual.Attachment = FixtureAttachment()
    let attachment = AnyAttachment(base)
    formatter.blockNodes = [
      .paragraph(children: [.attachment(attachment), .attachment(attachment)])
    ]

    let html = formatter.html(maxImageBytes: 5, maxTotalImageBytes: 7)
    #expect(html == #"<p><img src="data:image/png;base64,ZmFrZQ==" />alt</p>"#)
    #expect(formatter.html(maxImageBytes: 3, maxTotalImageBytes: 7) == "<p>altalt</p>")
  }

  @Test func tightListAdmitsImagesInRenderedOrder() {
    let formatter = Formatter(AttributedString())
    let base: any Textual.Attachment = FixtureAttachment()
    let image = Formatter.InlineNode.attachment(AnyAttachment(base))
    formatter.blockNodes = [
      .unorderedList(children: [
        .init(
          ordinal: 1,
          blocks: [
            .paragraph(children: [image]),
            .unorderedList(children: [.init(ordinal: 1, blocks: [.paragraph(children: [image])])]),
          ])
      ])
    ]

    let html = formatter.html(maxImageBytes: 5, maxTotalImageBytes: 7)
    #expect(html.contains(#"<li><img src="data:image/png;base64,ZmFrZQ==" /><ul>"#))
    #expect(html.contains("<li>alt</li>"))
  }

  @Test func legacyAttachmentsRetainSmallImageExport() {
    let formatter = Formatter(AttributedString())
    let base: any Textual.Attachment = LegacyFixtureAttachment()
    formatter.blockNodes = [.paragraph(children: [.attachment(AnyAttachment(base))])]
    #expect(formatter.html(maxImageBytes: 5, maxTotalImageBytes: 7).contains("ZmFrZQ=="))
    #expect(formatter.html(maxImageBytes: 3, maxTotalImageBytes: 7) == "<p>legacy</p>")
  }

  @Test func tableAndNestedInlineImagesShareOneBudget() throws {
    let formatter = try Formatter(NSAttributedString(markdown: "| Column |\n| --- |\n| Value |"))
    guard case .table(let columns, _) = formatter.blockNodes.first else {
      Issue.record("Markdown table fixture did not produce a table")
      return
    }
    let base: any Textual.Attachment = FixtureAttachment()
    let image = Formatter.InlineNode.attachment(AnyAttachment(base))
    let link = try #require(URL(string: "https://example.invalid"))
    formatter.blockNodes = [
      .paragraph(children: [
        .strong(children: [
          .link(
            url: link, children: [image]
          )
        ])
      ]),
      .table(
        columns: columns,
        children: [
          .init(cells: [[image]]),
          .init(cells: [[image]]),
        ]),
    ]

    let html = formatter.html(maxImageBytes: 5, maxTotalImageBytes: 7)
    #expect(html.components(separatedBy: "data:image/png;base64,").count == 2)
    #expect(html.components(separatedBy: "alt").count == 3)
  }
}

private struct FixtureAttachment: Textual.Attachment {
  var description: String { "alt" }
  var body: some View { EmptyView() }

  func sizeThatFits(_: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize { .zero }

  func boundedPNGData(maxBytes: Int) -> Data? {
    let data = Data("fake".utf8)
    return data.count <= maxBytes ? data : nil
  }
}

private struct LegacyFixtureAttachment: Textual.Attachment {
  var description: String { "legacy" }
  var body: some View { EmptyView() }

  func sizeThatFits(_: ProposedViewSize, in _: TextEnvironmentValues) -> CGSize { .zero }

  func pngData() -> Data? { Data("fake".utf8) }
}
