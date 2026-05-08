import XCTest
@testable import ClipboardCore

final class SQLitePayloadStoreTests: XCTestCase {
  var tempDir: URL!

  override func setUp() async throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("clipboard-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDown() async throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  func testRoundTripText() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    try await store.save(.text("hello"), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .text("hello"))
  }

  func testRoundTripImage() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    let data = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG magic bytes
    try await store.save(.image(data: data, uti: "public.jpeg"), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .image(data: data, uti: "public.jpeg"))
  }

  func testRoundTripRichText() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    let rtf = Data("rtf-bytes".utf8)
    try await store.save(.richText(plainText: "plain", rtfData: rtf), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .richText(plainText: "plain", rtfData: rtf))
  }

  func testRoundTripFileURLs() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
    try await store.save(.fileURLs(urls), for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertEqual(loaded, .fileURLs(urls))
  }

  func testDeleteRemovesFile() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    let id = UUID()
    try await store.save(.text("x"), for: id)
    try await store.delete(for: id)
    let loaded = try await store.loadPayload(for: id)
    XCTAssertNil(loaded)
  }

  func testDeleteIsIdempotent() async throws {
    let store = try SQLitePayloadStore(payloadsDirectory: tempDir)
    try await store.delete(for: UUID())  // should not throw
  }
}
