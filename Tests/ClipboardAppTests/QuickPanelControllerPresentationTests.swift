import XCTest
@testable import ClipboardApp
@testable import ClipboardCore

@MainActor
final class QuickPanelControllerPresentationTests: XCTestCase {
    func testSubmitKeepsPanelVisibleAndShowsAuthorizationMessageWhenAutoPasteIsUnauthorized() async throws {
        let state = makePresentationState()
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
        let state = makePresentationState(store: store)
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
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            pasteboard: pasteboard,
            eventPoster: eventPoster
        )
        let controller = QuickPanelController(state: state)

        await state.refresh()
        controller.copySelectionOnly()
        try await waitUntil("copy-only selection to write the pasteboard") {
            pasteboard.lastText != nil
        }

        XCTAssertEqual(pasteboard.lastText, "copy-only payload")
        XCTAssertFalse(eventPoster.didPostCommandV)
    }

    func testSubmitSelectionRespectsCopyOnlySetting() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let eventPoster = PresentationTestPasteEventPoster()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("copy-only submit payload"), for: record.id)
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            pasteboard: pasteboard,
            eventPoster: eventPoster
        )
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { false },
            isAutoPasteAuthorized: { true }
        )

        await state.refresh()
        controller.submitSelection()
        try await waitUntil("submit selection to write the pasteboard") {
            pasteboard.lastText != nil
        }

        XCTAssertEqual(pasteboard.lastText, "copy-only submit payload")
        XCTAssertFalse(eventPoster.didPostCommandV)
    }

    func testPasteHistoryShortcutHidesPanelRestoresPreviousApplicationAndAutoPastesHistoryItem() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let eventPoster = PresentationTestPasteEventPoster()
        let pinned = makePresentationRecord(title: "Pinned", isPinned: true)
        let history = makePresentationRecord(title: "History")
        _ = try await store.upsert(pinned)
        _ = try await store.upsert(history)
        try await payloadStore.save(.text("pinned payload"), for: pinned.id)
        try await payloadStore.save(.text("history payload"), for: history.id)
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            pasteboard: pasteboard,
            eventPoster: eventPoster
        )
        var didRequestRestore = false
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { false },
            isAutoPasteAuthorized: { true },
            activatePreviousApplication: { _ in
                didRequestRestore = true
            }
        )

        controller.show()
        await state.refresh()
        controller.pasteHistoryShortcut(number: 1)
        try await waitUntil("history shortcut paste to post Command+V") {
            pasteboard.lastText != nil && eventPoster.didPostCommandV && didRequestRestore
        }

        XCTAssertEqual(pasteboard.lastText, "history payload")
        XCTAssertTrue(eventPoster.didPostCommandV)
        XCTAssertTrue(didRequestRestore)
        XCTAssertFalse(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "History shortcut paste should close the QuickPanel before posting Command+V to the previous app."
        )
    }

    func testPasteHistoryShortcutKeepsPanelVisibleWhenAutoPasteIsUnauthorized() async throws {
        let state = makePresentationState()
        let controller = QuickPanelController(
            state: state,
            isAutoPasteAuthorized: { false }
        )

        controller.show()
        defer { controller.hide() }
        controller.pasteHistoryShortcut(number: 1)

        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Unauthorized History shortcut paste should keep the QuickPanel visible for the authorization message."
        )
        XCTAssertEqual(state.footerStatus, "自动粘贴需要辅助功能权限，请在设置中授权")
    }

    func testPasteHistoryShortcutByOutOfRangeNumberKeepsPanelVisibleAndDoesNotPaste() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let eventPoster = PresentationTestPasteEventPoster()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("number paste payload"), for: record.id)
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            pasteboard: pasteboard,
            eventPoster: eventPoster
        )
        var didRequestRestore = false
        let controller = QuickPanelController(
            state: state,
            isAutoPasteAuthorized: { true },
            activatePreviousApplication: { _ in
                didRequestRestore = true
            }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        controller.pasteHistoryShortcut(number: 9)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNil(pasteboard.lastText)
        XCTAssertFalse(eventPoster.didPostCommandV)
        XCTAssertFalse(didRequestRestore)
        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Out-of-range History shortcut paste should not close the QuickPanel."
        )
    }

    func testPastePlainTextSelectionHidesPanelRestoresPreviousApplicationAndAutoPastesPlainText() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let eventPoster = PresentationTestPasteEventPoster()
        let record = makePresentationRecord(type: .richText)
        _ = try await store.upsert(record)
        try await payloadStore.save(
            .richText(plainText: "plain text payload", rtfData: Data("{\\rtf1 styled}".utf8)),
            for: record.id
        )
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            pasteboard: pasteboard,
            eventPoster: eventPoster
        )
        var didRequestRestore = false
        let controller = QuickPanelController(
            state: state,
            isAutoPasteAuthorized: { true },
            activatePreviousApplication: { _ in
                didRequestRestore = true
            }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        let pasteTask = controller.pastePlainTextSelection()
        await pasteTask.value

        XCTAssertEqual(pasteboard.lastText, "plain text payload")
        XCTAssertTrue(eventPoster.didPostCommandV)
        XCTAssertTrue(didRequestRestore)
        XCTAssertFalse(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Plain-text paste should close the QuickPanel before posting Command+V to the previous app."
        )
    }

    func testPastePlainTextSelectionFromFreshPanelHidesPanelAndAutoPastesPlainText() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let eventPoster = PresentationTestPasteEventPoster()
        let record = makePresentationRecord(type: .richText)
        _ = try await store.upsert(record)
        try await payloadStore.save(
            .richText(plainText: "fresh panel plain text", rtfData: Data("{\\rtf1 styled}".utf8)),
            for: record.id
        )
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            pasteboard: pasteboard,
            eventPoster: eventPoster
        )
        var didRequestRestore = false
        let controller = QuickPanelController(
            state: state,
            isAutoPasteAuthorized: { true },
            activatePreviousApplication: { _ in
                didRequestRestore = true
            }
        )

        controller.show()
        defer { controller.hide() }
        let pasteTask = controller.pastePlainTextSelection()
        await pasteTask.value

        XCTAssertEqual(pasteboard.lastText, "fresh panel plain text")
        XCTAssertTrue(eventPoster.didPostCommandV)
        XCTAssertTrue(didRequestRestore)
        XCTAssertFalse(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Plain-text paste should close the QuickPanel even when invoked immediately after presentation."
        )
    }

    func testPastePlainTextSelectionKeepsPanelVisibleForUnsupportedPayload() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let eventPoster = PresentationTestPasteEventPoster()
        let record = makePresentationRecord(type: .image)
        _ = try await store.upsert(record)
        try await payloadStore.save(.image(data: Data([1, 2, 3]), uti: "public.png"), for: record.id)
        let state = makePresentationState(
            store: store,
            payloadStore: payloadStore,
            eventPoster: eventPoster
        )
        let controller = QuickPanelController(
            state: state,
            isAutoPasteAuthorized: { true }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        let pasteTask = controller.pastePlainTextSelection()
        await pasteTask.value

        XCTAssertFalse(eventPoster.didPostCommandV)
        XCTAssertEqual(state.footerStatus, "Plain text paste is not supported for image")
        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Unsupported plain-text paste should keep the QuickPanel visible for the status message."
        )
    }

    func testAuthorizationPromptButtonCanBeInjected() async throws {
        let state = makePresentationState()
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
        let state = makePresentationState()
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
        let state = makePresentationState()
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

    func testSubmitSelectionHidesPanelByDefault() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("keep-open default payload"), for: record.id)
        let state = makePresentationState(store: store, payloadStore: payloadStore)
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { false },
            keepOpenAfterPaste: { false }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        controller.submitSelection()

        XCTAssertFalse(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Default behavior must hide the panel on submit.")
    }

    func testSubmitSelectionKeepsPanelVisibleWhenKeepOpenEnabled() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("keep-open submit payload"), for: record.id)
        let state = makePresentationState(store: store, payloadStore: payloadStore, pasteboard: pasteboard)
        let controller = QuickPanelController(
            state: state,
            autoPasteEnabled: { false },
            keepOpenAfterPaste: { true }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        controller.submitSelection()
        try await waitUntil("submit selection to write the pasteboard") {
            pasteboard.lastText != nil
        }

        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Keep-open must leave the panel visible after submit completes.")
    }

    // MARK: - Frontmost application tracking (keep-open)

    func testShouldAdoptActivatedApplicationIgnoresSelfActivation() {
        XCTAssertFalse(
            QuickPanelFrontmostAppTracking.shouldAdoptActivatedApplication(
                activatedBundleIdentifier: "com.example.ClipboardApp",
                ownBundleIdentifier: "com.example.ClipboardApp"
            ),
            "Activating this app itself (e.g. the panel gaining focus) must not change the paste target."
        )
    }

    func testShouldAdoptActivatedApplicationAcceptsForeignApplication() {
        XCTAssertTrue(
            QuickPanelFrontmostAppTracking.shouldAdoptActivatedApplication(
                activatedBundleIdentifier: "com.apple.TextEdit",
                ownBundleIdentifier: "com.example.ClipboardApp"
            ),
            "Activating a different app while the keep-open panel is visible should retarget the paste."
        )
    }

    func testShouldAdoptActivatedApplicationFollowsRememberPreviousApplicationSemanticsForNilBundleIdentifier() {
        // Same guard as `rememberPreviousApplication`: `nil != ownBundleIdentifier`
        // evaluates true, so an activated app with no bundle identifier is
        // still adopted as the new paste target.
        XCTAssertTrue(
            QuickPanelFrontmostAppTracking.shouldAdoptActivatedApplication(
                activatedBundleIdentifier: nil,
                ownBundleIdentifier: "com.example.ClipboardApp"
            )
        )
    }

    func testCopySelectionOnlyKeepsPanelVisibleWhenKeepOpenEnabled() async throws {
        let store = InMemoryHistoryStore()
        let payloadStore = InMemoryPayloadStore()
        let pasteboard = PresentationTestPasteboardWriter()
        let record = makePresentationRecord()
        _ = try await store.upsert(record)
        try await payloadStore.save(.text("keep-open copy payload"), for: record.id)
        let state = makePresentationState(store: store, payloadStore: payloadStore, pasteboard: pasteboard)
        let controller = QuickPanelController(
            state: state,
            keepOpenAfterPaste: { true }
        )

        controller.show()
        defer { controller.hide() }
        await state.refresh()
        controller.copySelectionOnly()
        try await waitUntil("copy-only selection to write the pasteboard") {
            pasteboard.lastText != nil
        }

        XCTAssertTrue(
            NSApp.windows.contains { $0.title == "Clipboard QuickPanel" && $0.isVisible },
            "Keep-open must leave the panel visible after copy-only completes.")
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` elapses.
/// Replaces fixed sleeps that race the controller's async paste pipeline
/// (which itself sleeps ~120ms before writing the pasteboard), so the wait is
/// "at least until the asserted side effect happens" instead of a guessed
/// duration that breaks under machine load.
@MainActor
private func waitUntil(
    _ description: String,
    timeout: TimeInterval = 2.0,
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: () -> Bool
) async throws {
    let start = Date()
    while !condition() {
        if Date().timeIntervalSince(start) > timeout {
            XCTFail("Timed out after \(timeout)s waiting for \(description)", file: file, line: line)
            return
        }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@MainActor
private func makePresentationState(
    store: InMemoryHistoryStore = InMemoryHistoryStore(),
    payloadStore: InMemoryPayloadStore = InMemoryPayloadStore(),
    pasteboard: PresentationTestPasteboardWriter = PresentationTestPasteboardWriter(),
    eventPoster: PresentationTestPasteEventPoster = PresentationTestPasteEventPoster()
) -> QuickPanelState {
    QuickPanelState(
        viewModel: QuickPanelViewModel(store: store, pageLimit: 20),
        payloadStore: payloadStore,
        pasteController: PasteController(
            pasteboard: pasteboard,
            eventPoster: eventPoster
        ),
        mutationService: HistoryMutationService(store: store, payloadStore: payloadStore)
    )
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

    func postCommandV(marker: String, pasteboard: any PasteboardWriting) async -> PasteEventResult {
        didPostCommandV = true
        return .posted
    }
}

private func makePresentationRecord(
    title: String = "Presentation",
    type: ClipboardContentType = .text,
    isPinned: Bool = false
) -> ClipboardRecord {
    ClipboardRecord(
        id: UUID(),
        contentHash: title,
        primaryType: type,
        title: title,
        plainTextPreview: title,
        sourceAppBundleId: nil,
        sourceAppName: "App",
        sourceDeviceHint: .local,
        createdAt: Date(timeIntervalSince1970: 1),
        lastCopiedAt: Date(timeIntervalSince1970: isPinned ? 1 : 2),
        copyCount: 1,
        isPinned: isPinned,
        isFavorite: false,
        groupIds: [],
        retentionExempt: isPinned,
        metadata: nil,
        pasteboardTypes: []
    )
}
