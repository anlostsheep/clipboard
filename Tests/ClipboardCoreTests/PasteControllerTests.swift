import XCTest
@testable import ClipboardCore

final class PasteControllerTests: XCTestCase {
  func testPasteFailsWhenAccessibilityIsMissing() async {
    let pasteboard = FakePasteboardWriter(writeResult: true)
    let poster = FakePasteEventPoster(accessibilityTrusted: false, postResult: true)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.accessibilityRevoked))
    XCTAssertEqual(pasteboard.writtenPayloads.count, 0)
  }

  func testCopyOnlyWritesPasteboardWithoutPostingPasteEvent() async {
    let pasteboard = FakePasteboardWriter(writeResult: true)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: true)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: false)

    XCTAssertEqual(transaction.state, .completed)
    XCTAssertEqual(pasteboard.writtenPayloads.count, 1)
    XCTAssertEqual(poster.postCount, 0)
  }

  func testPasteboardWriteFailureIsReported() async {
    let pasteboard = FakePasteboardWriter(writeResult: false)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: true)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.pasteboardWriteFailed))
    XCTAssertEqual(poster.postCount, 0)
  }

  func testPasteboardMarkerValidationFailureIsReported() async {
    let pasteboard = FakePasteboardWriter(writeResult: true, containsMarkerResult: false)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: true)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.pasteboardWriteFailed))
    XCTAssertEqual(poster.postCount, 0)
  }

  func testPasteEventFailureIsReported() async {
    let pasteboard = FakePasteboardWriter(writeResult: true)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: false)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.pasteEventFailed))
    XCTAssertEqual(poster.postCount, 1)
  }

  func testTargetFocusLostIsReported() async {
    let pasteboard = FakePasteboardWriter(writeResult: true)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: true, eventResult: .targetAppFocusLost)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.targetAppFocusLost))
  }

  func testTargetRejectedPasteIsReported() async {
    let pasteboard = FakePasteboardWriter(writeResult: true)
    let poster = FakePasteEventPoster(accessibilityTrusted: true, postResult: true, eventResult: .targetAppRejectedPaste)
    let controller = PasteController(pasteboard: pasteboard, eventPoster: poster)
    let record = Self.record(text: "hello")

    let transaction = await controller.paste(record: record, payload: .text("hello"), autoPaste: true)

    XCTAssertEqual(transaction.state, .failed(.targetAppRejectedPaste))
  }

  private static func record(text: String) -> ClipboardRecord {
    ClipboardRecord(
      id: UUID(uuidString: "00000000-0000-0000-0000-000000000010")!,
      contentHash: "hash",
      primaryType: .text,
      title: text,
      plainTextPreview: text,
      sourceAppBundleId: nil,
      sourceAppName: nil,
      sourceDeviceHint: .local,
      createdAt: Date(timeIntervalSince1970: 1),
      lastCopiedAt: Date(timeIntervalSince1970: 1),
      copyCount: 1,
      isPinned: false,
      isFavorite: false,
      groupIds: [],
      retentionExempt: false,
      metadata: nil,
      pasteboardTypes: ["public.utf8-plain-text"]
    )
  }
}

private final class FakePasteboardWriter: PasteboardWriting, @unchecked Sendable {
  let writeResult: Bool
  let containsMarkerResult: Bool
  private(set) var writtenPayloads: [ClipboardPayload] = []

  init(writeResult: Bool, containsMarkerResult: Bool? = nil) {
    self.writeResult = writeResult
    self.containsMarkerResult = containsMarkerResult ?? writeResult
  }

  func write(payload: ClipboardPayload, marker: String) async -> Bool {
    writtenPayloads.append(payload)
    return writeResult
  }

  func containsMarker(_ marker: String) async -> Bool {
    containsMarkerResult
  }
}

private final class FakePasteEventPoster: PasteEventPosting, @unchecked Sendable {
  let accessibilityTrusted: Bool
  let postResult: Bool
  let eventResult: PasteEventResult?
  private(set) var postCount = 0

  init(accessibilityTrusted: Bool, postResult: Bool, eventResult: PasteEventResult? = nil) {
    self.accessibilityTrusted = accessibilityTrusted
    self.postResult = postResult
    self.eventResult = eventResult
  }

  func isAccessibilityTrusted() -> Bool {
    accessibilityTrusted
  }

  func postCommandV() async -> Bool {
    postCount += 1
    return postResult
  }

  func postCommandV(marker: String, pasteboard: any PasteboardWriting) async -> PasteEventResult {
    postCount += 1
    return eventResult ?? (postResult ? .posted : .postFailed)
  }
}
