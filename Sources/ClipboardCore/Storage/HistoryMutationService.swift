import Foundation

public enum HistoryMutationError: Error, Equatable {
  case mutationUnsupported
  case recordNotFound
}

public actor HistoryMutationService {
  private let store: any HistoryStore
  private let payloadStore: any ClipboardPayloadStore

  public init(store: any HistoryStore, payloadStore: any ClipboardPayloadStore) {
    self.store = store
    self.payloadStore = payloadStore
  }

  public func deleteRecord(id: UUID) async throws {
    let mutationStore = try requireMutationStore()
    guard let removed = try await mutationStore.deleteRecord(id: id) else {
      throw HistoryMutationError.recordNotFound
    }
    try await payloadStore.delete(for: removed.id)
  }

  public func togglePinned(id: UUID) async throws -> ClipboardRecord {
    let mutationStore = try requireMutationStore()
    let records = try await store.fetchAll()
    guard var record = records.first(where: { $0.id == id }) else {
      throw HistoryMutationError.recordNotFound
    }
    record.isPinned.toggle()
    record.retentionExempt = record.isPinned || record.isFavorite
    return try await mutationStore.replaceRecord(record)
  }

  public func clearUnpinned() async throws -> Int {
    let mutationStore = try requireMutationStore()
    let removed = try await mutationStore.clearUnpinned()
    for record in removed {
      try await payloadStore.delete(for: record.id)
    }
    return removed.count
  }

  public func clearAll() async throws -> Int {
    let records = try await store.fetchAll()
    try await store.removeAll()
    for record in records {
      try await payloadStore.delete(for: record.id)
    }
    return records.count
  }

  private func requireMutationStore() throws -> any HistoryMutationStore {
    guard let mutationStore = store as? any HistoryMutationStore else {
      throw HistoryMutationError.mutationUnsupported
    }
    return mutationStore
  }
}
