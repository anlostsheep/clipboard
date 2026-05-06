import AppKit
import XCTest
@testable import ClipboardCore
@testable import ClipboardPlatform

final class SystemPasteboardClientTests: XCTestCase {
  func testTextWriteAddsMarkerAndIsNotCapturedAsExternalClipboardChange() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)

    let wrote = await client.write(payload: .text("hello from test"), marker: "test-marker")
    let hasMarker = await client.containsMarker("test-marker")
    let capture = await client.readCurrentCapture()

    XCTAssertTrue(wrote)
    XCTAssertTrue(hasMarker)
    XCTAssertNil(capture)
  }

  func testExternalTextCanBeCaptured() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)

    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.setString("external text", forType: .string))

    let captured = await client.readCurrentCapture()
    let capture = try XCTUnwrap(captured)

    XCTAssertEqual(capture.payload, .text("external text"))
    XCTAssertTrue(capture.pasteboardTypes.contains(NSPasteboard.PasteboardType.string.rawValue))
  }

  func testUniversalClipboardTypeIsPreservedInCapture() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let item = NSPasteboardItem()

    XCTAssertTrue(item.setString("from phone", forType: .string))
    XCTAssertTrue(item.setString("1", forType: NSPasteboard.PasteboardType("com.apple.is-remote-clipboard")))
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([item]))

    let captured = await client.readCurrentCapture()
    let capture = try XCTUnwrap(captured)

    XCTAssertEqual(capture.payload, .text("from phone"))
    XCTAssertTrue(capture.isUniversalClipboard)
  }

  func testRichTextWritePreservesPlainTextAndRTF() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let rtf = Data("{\\rtf1\\ansi hello}".utf8)

    let wrote = await client.write(payload: .richText(plainText: "hello", rtfData: rtf), marker: "rtf-marker")
    let hasMarker = await client.containsMarker("rtf-marker")

    XCTAssertTrue(wrote)
    let item = try XCTUnwrap(pasteboard.pasteboardItems?.first)
    XCTAssertEqual(item.string(forType: .string), "hello")
    XCTAssertEqual(item.data(forType: .rtf), rtf)
    XCTAssertTrue(hasMarker)
  }

  func testFileURLWriteCreatesOnePasteboardItemPerURL() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let first = URL(fileURLWithPath: "/tmp/clipboard-test-a.txt")
    let second = URL(fileURLWithPath: "/tmp/clipboard-test-b.txt")

    let wrote = await client.write(payload: .fileURLs([first, second]), marker: "file-marker")
    let hasMarker = await client.containsMarker("file-marker")

    XCTAssertTrue(wrote)
    let items = try XCTUnwrap(pasteboard.pasteboardItems)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items.compactMap { $0.string(forType: .fileURL) }, [first.absoluteString, second.absoluteString])
    XCTAssertTrue(hasMarker)
  }

  func testExternalImageCanBeCapturedWithoutTextHydration() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let item = NSPasteboardItem()

    XCTAssertTrue(item.setData(pngData, forType: .png))
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([item]))

    let captured = await client.readCurrentCapture()
    let capture = try XCTUnwrap(captured)

    XCTAssertEqual(capture.payload, .image(data: pngData, uti: NSPasteboard.PasteboardType.png.rawValue))
    XCTAssertTrue(capture.pasteboardTypes.contains(NSPasteboard.PasteboardType.png.rawValue))
  }

  func testExternalTiffImageCanBeCaptured() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let tiffData = Data([0x4D, 0x4D, 0x00, 0x2A])
    let item = NSPasteboardItem()

    XCTAssertTrue(item.setData(tiffData, forType: .tiff))
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([item]))

    let captured = await client.readCurrentCapture()
    let capture = try XCTUnwrap(captured)

    XCTAssertEqual(capture.payload, .image(data: tiffData, uti: NSPasteboard.PasteboardType.tiff.rawValue))
    XCTAssertTrue(capture.pasteboardTypes.contains(NSPasteboard.PasteboardType.tiff.rawValue))
  }

  func testImageDataIsPreferredWhenClipboardItemAlsoHasTextMetadata() async throws {
    let pasteboard = makePasteboard()
    let client = SystemPasteboardClient(pasteboard: pasteboard)
    let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    let item = NSPasteboardItem()

    XCTAssertTrue(item.setString("https://example.com/image.png", forType: .string))
    XCTAssertTrue(item.setData(pngData, forType: .png))
    pasteboard.clearContents()
    XCTAssertTrue(pasteboard.writeObjects([item]))

    let captured = await client.readCurrentCapture()
    let capture = try XCTUnwrap(captured)

    XCTAssertEqual(capture.payload, .image(data: pngData, uti: NSPasteboard.PasteboardType.png.rawValue))
  }

  private func makePasteboard() -> NSPasteboard {
    let name = NSPasteboard.Name("com.local.clipboard-manager.tests.\(UUID().uuidString)")
    let pasteboard = NSPasteboard(name: name)
    pasteboard.clearContents()
    return pasteboard
  }
}
