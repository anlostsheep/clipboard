import CryptoKit
import Foundation

enum ClipboardContentHasher {
  static func hashText(_ text: String) -> String {
    var hasher = SHA256()
    let didHashContiguousStorage = text.utf8.withContiguousStorageIfAvailable { buffer in
      hasher.update(bufferPointer: UnsafeRawBufferPointer(buffer))
      return true
    } ?? false

    if !didHashContiguousStorage {
      var chunk: [UInt8] = []
      chunk.reserveCapacity(16 * 1024)

      for byte in text.utf8 {
        chunk.append(byte)
        if chunk.count == 16 * 1024 {
          hasher.update(data: chunk)
          chunk.removeAll(keepingCapacity: true)
        }
      }

      if !chunk.isEmpty {
        hasher.update(data: chunk)
      }
    }

    return digestHex(hasher.finalize())
  }

  static func hashData(_ data: Data) -> String {
    digestHex(SHA256.hash(data: data))
  }

  static func hashRichText(plainText: String, rtfData: Data?, htmlData: Data?) -> String {
    var hasher = SHA256()
    updateString("ClipboardPayload.richText.v1", into: &hasher)
    updateLengthPrefixedData(Data(plainText.utf8), into: &hasher)
    updateOptionalData(rtfData, into: &hasher)
    updateOptionalData(htmlData, into: &hasher)
    return digestHex(hasher.finalize())
  }

  private static func updateString(_ string: String, into hasher: inout SHA256) {
    hasher.update(data: Data(string.utf8))
  }

  private static func updateOptionalData(_ data: Data?, into hasher: inout SHA256) {
    switch data {
    case let .some(data):
      updateString("1", into: &hasher)
      updateLengthPrefixedData(data, into: &hasher)
    case .none:
      updateString("0", into: &hasher)
    }
  }

  private static func updateLengthPrefixedData(_ data: Data, into hasher: inout SHA256) {
    var length = UInt64(data.count).bigEndian
    withUnsafeBytes(of: &length) { buffer in
      hasher.update(bufferPointer: buffer)
    }
    hasher.update(data: data)
  }

  private static func digestHex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 {
    digest.map { String(format: "%02x", $0) }.joined()
  }
}
