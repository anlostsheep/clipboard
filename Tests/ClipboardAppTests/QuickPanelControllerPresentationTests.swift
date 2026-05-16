import XCTest
@testable import ClipboardApp
@testable import ClipboardCore

@MainActor
final class QuickPanelControllerPresentationTests: XCTestCase {
    func testSubmitKeepsPanelVisibleAndShowsAuthorizationMessageWhenAutoPasteIsUnauthorized() async throws {
        let state = QuickPanelState(
            viewModel: QuickPanelViewModel(store: InMemoryHistoryStore(), pageLimit: 20),
            payloadStore: InMemoryPayloadStore(),
            pasteController: PasteController(
                pasteboard: PresentationTestPasteboardWriter(),
                eventPoster: PresentationTestPasteEventPoster()
            )
        )
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { true },
            isAutoPasteAuthorized: { false }
        )

        controller.show()
        defer { controller.hide() }
        controller.submitSelection()

        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "QuickPanel should stay visible so the footer can show the authorization error."
        )
        XCTAssertEqual(state.footerStatus, "自动粘贴需要辅助功能权限，请在设置中授权")
    }

    func testUnauthorizedSubmitMessageSurvivesShowRefreshCompletion() async throws {
        let store = InMemoryHistoryStore()
        _ = try await store.upsert(makePresentationRecord())
        let state = QuickPanelState(
            viewModel: QuickPanelViewModel(store: store, pageLimit: 20),
            payloadStore: InMemoryPayloadStore(),
            pasteController: PasteController(
                pasteboard: PresentationTestPasteboardWriter(),
                eventPoster: PresentationTestPasteEventPoster()
            )
        )
        let controller = QuickPanelController(
            state: state,
            prepareForShow: {
                try? await Task.sleep(nanoseconds: 50_000_000)
            },
            autoPasteEnabled: { true },
            isAutoPasteAuthorized: { false }
        )

        controller.show()
        defer { controller.hide() }
        controller.submitSelection()
        try await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(state.footerStatus, "自动粘贴需要辅助功能权限，请在设置中授权")
    }

    func testCopySelectionOnlyWritesSelectedPayloadWithoutPostingPasteEvent() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("copy-only payload"), for: record.id)
        let eventPoster = PresentationTestPasteEventPoster()
        let state = QuickPanelState(
            viewModel: QuickPanelViewModel(store: store, pageLimit: 20),
            payloadStore: payloadStore,
            pasteController: PasteController(
                pasteboard: pasteboard,
                eventPoster: eventPoster
            )
        )
        let controller = QuickPanelController(state: state)

        await state.refresh()
        controller.copySelectionOnly()
        try await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(pasteboard.lastText, "copy-only payload")
        XCTAssertFalse(eventPoster.didPostCommandV)
    }

    func testAuthorizationPromptButtonCanBeInjected() async throws {
        let state = QuickPanelState(
            viewModel: QuickPanelViewModel(store: InMemoryHistoryStore(), pageLimit: 20),
            payloadStore: InMemoryPayloadStore(),
            pasteController: PasteController(
                pasteboard: PresentationTestPasteboardWriter(),
                eventPoster: PresentationTestPasteEventPoster()
            )
        )
        var didRequestAuthorization = false
        let controller = QuickPanelController(
            state: state,
            requestAccessibilityAuthorization: {
                didRequestAuthorization = true
            }
        )

        controller.requestAccessibilityAuthorization()

        XCTAssertTrue(didRequestAuthorization)
    }

    func testCancelHidesPanelAndRestoresPreviousApplication() async throws {
        let state = QuickPanelState(
            viewModel: QuickPanelViewModel(store: InMemoryHistoryStore(), pageLimit: 20),
            payloadStore: InMemoryPayloadStore(),
            pasteController: PasteController(
                pasteboard: PresentationTestPasteboardWriter(),
                eventPoster: PresentationTestPasteEventPoster()
            )
        )
        var didRequestRestore = false
        let controller = QuickPanelController(
            state: state,
            activatePreviousApplication: { _ in
                didRequestRestore = true
            }
        )

        controller.show()
        controller.cancel()

        XCTAssertTrue(didRequestRestore)
        XCTAssertFalse(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Esc-style cancellation should hide the QuickPanel."
        )
    }

    func testShowOrdersPanelBeforeSlowRefreshCompletes() async throws {
        let state = QuickPanelState(
            viewModel: QuickPanelViewModel(store: InMemoryHistoryStore(), pageLimit: 20),
            payloadStore: InMemoryPayloadStore(),
            pasteController: PasteController(
                pasteboard: PresentationTestPasteboardWriter(),
                eventPoster: PresentationTestPasteEventPoster()
            )
        )
        let controller = QuickPanelController(state: state) {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        controller.show()
        defer { controller.hide() }

        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "QuickPanel should become visible immediately, before capture/refresh work finishes."
        )
    }
}

private final class PresentationTestPasteboardWriter: PasteboardWriting, @unchecked Sendable {
    private(set) var lastText: String?

    func write(payload: ClipboardPayload, marker: String) async -> Bool {
        if case let .text(text) = payload {
            lastText = text
        }
        return true
    }

    func containsMarker(_ marker: String) async -> Bool { true }
}

private final class PresentationTestPasteEventPoster: PasteEventPosting, @unchecked Sendable {
    private(set) var didPostCommandV = false

    func isAccessibilityTrusted() -> Bool { true }
    func postCommandV() async -> Bool {
        didPostCommandV = true
        return true
    }
}

private func makePresentationRecord() -> ClipboardRecord {
    ClipboardRecord(
        id: UUID(),
        contentHash: "presentation",
        primaryType: .text,
        title: "Presentation",
        plainTextPreview: "Presentation",
        sourceAppBundleId: nil,
        sourceAppName: "App",
        sourceDeviceHint: .local,
        createdAt: Date(timeIntervalSince1970: 1),
        lastCopiedAt: Date(timeIntervalSince1970: 1),
        copyCount: 1,
        isPinned: false,
        isFavorite: false,
        groupIds: [],
        retentionExempt: false,
        metadata: nil,
        pasteboardTypes: []
    )
}
