import AppKit
import ClipboardCore
import SwiftUI

struct QuickPanelView: View {
  @ObservedObject var state: QuickPanelState
  let onClose: () -> Void
  let onSubmit: () -> Void
  let onCopyOnly: () -> Void
  let onPasteNumber: (Int) -> Void
  let onPastePlainText: () -> Void
  let onRequestAccessibilityAuthorization: () -> Void
  let onQuit: () -> Void
  @FocusState private var isSearchFocused: Bool
  @State private var scrollCoordinator = QuickPanelScrollCoordinator()
  @State private var sourceAppIconProvider = SourceAppIconProvider()
  @State private var confirmsClearAll = false
  @State private var numberShortcutMode: QuickPanelNumberShortcutMode?
  @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
  private var quickPanelReturnCopiesOnly = false

  var body: some View {
    VStack(spacing: 0) {
      searchField

      Divider()

      results

      if let actionPrompt = state.actionPrompt {
        Divider()
        promptView(for: actionPrompt)
      }

      Divider()

      footer
    }
    .frame(
      width: QuickPanelLayoutMetrics.panelSize.width,
      height: QuickPanelLayoutMetrics.panelSize.height
    )
    .background(.regularMaterial)
    .overlay(keyCapture.frame(width: 0, height: 0))
    .onAppear {
      numberShortcutMode = nil
      isSearchFocused = true
    }
    .task {
      await state.refresh()
      isSearchFocused = true
    }
    .confirmationDialog(
      "Clear all clipboard items?",
      isPresented: $confirmsClearAll,
      titleVisibility: .visible
    ) {
      Button("Clear All", role: .destructive) {
        Task {
          await state.clearAll()
        }
      }

      Button("Cancel", role: .cancel) {}
    }
    .sheet(
      isPresented: Binding(
        get: { state.detailPreview != nil },
        set: { isPresented in
          if !isPresented {
            state.dismissDetailPreview()
          }
        }
      )
    ) {
      if let preview = state.detailPreview {
        QuickPanelDetailPreviewView(preview: preview)
      }
    }
  }

  private func focusSearch() {
    isSearchFocused = false
    DispatchQueue.main.async {
      isSearchFocused = true
    }
  }

  private var searchField: some View {
    HStack(spacing: 10) {
      Image(systemName: "magnifyingglass")
        .foregroundStyle(.secondary)

      TextField(
        "Search clipboard",
        text: Binding(
          get: { state.query },
          set: { state.updateQuery($0) }
        )
      )
      .textFieldStyle(.plain)
      .focused($isSearchFocused)

      Text("类型")
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .frame(width: 36, alignment: .trailing)

      Picker(
        "Type",
        selection: Binding(
          get: { state.contentFilter },
          set: { state.updateContentFilter($0) }
        )
      ) {
        ForEach(QuickPanelContentFilter.allCases) { filter in
          Text(filter.title).tag(filter)
        }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 260)

      actionMenu

      Button {
        AppDelegate.shared.openSettings()
      } label: {
        Image(systemName: "gearshape")
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .help("打开设置")
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 12)
  }

  private var actionMenu: some View {
    Menu {
      Button(role: .destructive) {
        Task {
          await state.deleteSelected()
        }
      } label: {
        Label("Delete Selected", systemImage: "trash")
      }
      .disabled(selectedRecord == nil)

      Button {
        Task {
          await state.togglePinned()
        }
      } label: {
        Label(selectedRecord?.isPinned == true ? "Unpin Item" : "Pin Item", systemImage: "pin")
      }
      .disabled(selectedRecord == nil)

      Divider()

      Button(role: .destructive) {
        Task {
          await state.clearUnpinned()
        }
      } label: {
        Label("Clear Unpinned", systemImage: "pin.slash")
      }

      Button(role: .destructive) {
        confirmsClearAll = true
      } label: {
        Label("Clear All", systemImage: "trash.slash")
      }
    } label: {
      Image(systemName: "ellipsis.circle")
        .foregroundStyle(.secondary)
    }
    .menuStyle(.borderlessButton)
    .fixedSize()
    .help("管理剪贴板历史")
  }

  private var selectedRecord: ClipboardRecord? {
    state.items.indices.contains(state.selectedIndex) ? state.items[state.selectedIndex] : nil
  }

  private var mouseInteraction: QuickPanelMouseInteraction {
    QuickPanelMouseInteraction(
      selectItem: { index in state.selectItem(at: index) },
      submitSelection: onSubmit
    )
  }

  @ViewBuilder
  private var results: some View {
    if state.items.isEmpty {
      ContentUnavailableView(
        "No Clipboard Items",
        systemImage: "doc.on.clipboard",
        description: Text("Copy something while Clipboard is running.")
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    } else {
      let sections = state.itemSections
      let pinnedSection = sections.first { $0.kind == .pinned }
      let historySection = sections.first { $0.kind == .history }

      VStack(alignment: .leading, spacing: 0) {
        if let pinnedSection {
          quickPanelSection(
            pinnedSection,
            hasHistory: historySection != nil,
            isPinnedSection: true
          )
        }

        if let historySection {
          quickPanelSection(
            historySection,
            hasHistory: true,
            isPinnedSection: false
          )
          .frame(maxHeight: .infinity, alignment: sectionFrameAlignment)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
  }

  private var sectionFrameAlignment: Alignment {
    switch QuickPanelLayoutMetrics.sectionFrameAlignment {
    case .topLeading:
      .topLeading
    }
  }

  private func quickPanelSection(
    _ section: QuickPanelItemSection,
    hasHistory: Bool,
    isPinnedSection: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      QuickPanelSectionHeader(title: sectionTitle(for: section))

      sectionRows(section)
        .frame(
          maxHeight: sectionRowsMaxHeight(
            section,
            hasHistory: hasHistory,
            isPinnedSection: isPinnedSection
          ),
          alignment: sectionFrameAlignment
        )
    }
    .frame(maxWidth: .infinity, alignment: sectionFrameAlignment)
  }

  private func sectionRowsMaxHeight(
    _ section: QuickPanelItemSection,
    hasHistory: Bool,
    isPinnedSection: Bool
  ) -> CGFloat {
    isPinnedSection
      ? QuickPanelLayoutMetrics.pinnedSectionMaxHeight(
        pinnedRowCount: section.rows.count,
        hasHistory: hasHistory
      )
      : .infinity
  }

  private func sectionTitle(for section: QuickPanelItemSection) -> String {
    if section.kind == .pinned, section.rows.count > 1 {
      return "\(section.title) \(section.rows.count)"
    }

    return section.title
  }

  private func sectionRows(_ section: QuickPanelItemSection) -> some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(section.rows) { row in
            rowView(row)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .id(state.itemRenderIdentities)
      }
      .transaction { transaction in
        transaction.disablesAnimations = true
        transaction.animation = nil
      }
      .onChange(of: state.items.map(\.id)) { _, itemIDs in
        guard let target = scrollCoordinator.targetAfterItemsChanged(
          itemIDs: itemIDs,
          selectedIndex: state.selectedIndex
        ) else {
          return
        }

        scrollIfPresent(proxy, to: target, in: section)
      }
      .onChange(of: state.selectedIndex) { _, selectedIndex in
        let itemIDs = state.items.map(\.id)
        guard let target = QuickPanelScrollCoordinator.targetForSelectionChange(
          itemIDs: itemIDs,
          selectedIndex: selectedIndex
        ) else {
          return
        }

        scrollIfPresent(proxy, to: target, in: section)
      }
    }
  }

  private func rowView(_ row: QuickPanelItemRow) -> some View {
    QuickPanelRow(
      record: row.record,
      isSelected: row.index == state.selectedIndex,
      shortcut: shortcut(for: row),
      sourceIcon: sourceAppIconProvider.icon(for: row.record),
      imagePreviewLoader: { record in
        await state.imagePreview(for: record)
      }
    )
    .id(row.record.id)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, QuickPanelLayoutMetrics.rowOuterVerticalPadding)
    .overlay {
      QuickPanelRowMouseCaptureView(
        rowIndex: row.index,
        interaction: mouseInteraction
      )
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .overlay(alignment: .bottom) {
      Divider()
        .padding(.leading, 56)
    }
  }

  private func shortcut(for row: QuickPanelItemRow) -> QuickPanelRowShortcut? {
    guard numberShortcutMode != nil || row.record.isPinned else {
      return nil
    }

    return row.shortcut
  }

  private func scrollIfPresent(
    _ proxy: ScrollViewProxy,
    to target: QuickPanelScrollTarget,
    in section: QuickPanelItemSection
  ) {
    guard let localRowIndex = section.rows.firstIndex(where: { $0.record.id == target.recordID }) else {
      return
    }

    scroll(
      proxy,
      to: QuickPanelScrollTarget(
        recordID: target.recordID,
        anchor: QuickPanelLayoutMetrics.sectionScrollAnchor(
          requested: target.anchor,
          localRowIndex: localRowIndex
        ),
        animation: target.animation
      )
    )
  }

  private func scroll(_ proxy: ScrollViewProxy, to target: QuickPanelScrollTarget) {
    let anchor: UnitPoint = switch target.anchor {
    case .top:
      .top
    case .center:
      .center
    }

    DispatchQueue.main.async {
      let scrollAction = {
        proxy.scrollTo(target.recordID, anchor: anchor)
      }

      switch target.animation {
      case .animated:
        withAnimation(.easeOut(duration: 0.12), scrollAction)
      case .immediate:
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        withTransaction(transaction, scrollAction)
      }
    }
  }

  private var shortcutHint: String {
    QuickPanelMouseInteraction.shortcutHint(
      returnCopiesOnly: quickPanelReturnCopiesOnly,
      actionPrompt: state.actionPrompt
    )
  }

  @ViewBuilder
  private func promptView(for prompt: QuickPanelActionPrompt) -> some View {
    switch prompt {
    case .autoPasteRequiresAccessibilityPermission:
      VStack(alignment: .leading, spacing: 10) {
        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "hand.raised.fill")
            .font(.title3)
            .foregroundStyle(.orange)
            .frame(width: 28, height: 28)

          VStack(alignment: .leading, spacing: 4) {
            Text("需要辅助功能权限才能自动粘贴")
              .font(.callout.weight(.semibold))
            Text("Clipboard 需要 macOS 辅助功能权限，才能把选中的内容粘贴到当前 App。")
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Spacer(minLength: 0)
        }

        HStack(spacing: 8) {
          Button("去授权") {
            onRequestAccessibilityAuthorization()
          }
          .buttonStyle(.borderedProminent)

          Button("仅复制本次") {
            onCopyOnly()
          }
          .buttonStyle(.bordered)

          Button("默认仅复制") {
            quickPanelReturnCopiesOnly = true
            state.reportCopyOnlyModeEnabled()
          }
          .buttonStyle(.bordered)
        }
        .padding(.leading, 40)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
      .background(Color.orange.opacity(0.10))
    }
  }

  private var footer: some View {
    HStack {
      Text(state.footerStatus)
        .foregroundStyle(.secondary)
      Spacer()
      Text(shortcutHint)
        .foregroundStyle(.secondary)
    }
    .font(.caption)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
  }

  private var keyCapture: some View {
    QuickPanelKeyCaptureView(
      onMove: { delta in
        state.moveSelection(delta: delta)
        focusSearch()
      },
      onSubmit: onSubmit,
      onCancel: onClose,
      onFocusSearch: focusSearch,
      onOpenSettings: {
        AppDelegate.shared.openSettings()
      },
      onQuit: onQuit,
      onDeleteSelected: {
        Task {
          await state.deleteSelected()
        }
        focusSearch()
      },
      onTogglePinned: {
        state.suppressNextShortcutQueryMutation(insertedText: "π")
        Task {
          await state.togglePinned()
        }
        focusSearch()
      },
      onClearUnpinned: {
        Task {
          await state.clearUnpinned()
        }
        focusSearch()
      },
      onClearAll: {
        confirmsClearAll = true
        focusSearch()
      },
      onCycleContentFilter: { delta in
        state.cycleContentFilter(delta: delta)
        focusSearch()
      },
      onSelectNumber: { number in
        state.selectHistoryShortcut(number: number)
        focusSearch()
      },
      onSelectPinnedShortcut: { slot in
        state.selectPinnedShortcut(slot: slot)
        focusSearch()
      },
      onPasteNumber: { number in
        onPasteNumber(number)
      },
      onPastePlainText: {
        onPastePlainText()
      },
      onShowDetailPreview: {
        Task {
          await state.showDetailPreview()
        }
        focusSearch()
      },
      onNumberShortcutModeChanged: { mode in
        numberShortcutMode = mode
      },
      modifierTrackingResetToken: state.presentationGeneration
    )
  }
}

private struct QuickPanelSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .textCase(.uppercase)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .padding(.top, 10)
      .padding(.bottom, 6)
  }
}

private struct QuickPanelRow: View {
  let record: ClipboardRecord
  let isSelected: Bool
  let shortcut: QuickPanelRowShortcut?
  let sourceIcon: NSImage?
  let imagePreviewLoader: (ClipboardRecord) async -> NSImage?
  @State private var imagePreview: NSImage?

  var body: some View {
    let sourceName = QuickPanelRowPresentation.sourceName(for: record)
    let showsSourceName = QuickPanelRowPresentation.showsSourceName(for: record)

    HStack(alignment: .center, spacing: 10) {
      SourceAppIconView(
        sourceIcon: sourceIcon,
        fallbackSymbolName: QuickPanelRowPresentation.sourceFallbackSymbolName(for: record),
        visual: QuickPanelRowPresentation.sourceVisual(for: record),
        isSelected: isSelected
      )

      VStack(alignment: .leading, spacing: 3) {
        ContentPreviewView(
          record: record,
          imagePreview: imagePreview,
          contentVisual: QuickPanelRowPresentation.contentVisual(for: record),
          isSelected: isSelected
        )

        if showsSourceName {
          Text(sourceName)
            .font(.caption2.weight(.medium))
            .foregroundStyle(isSelected ? .white.opacity(0.76) : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if let shortcut {
        QuickPanelShortcutBadge(shortcut: shortcut, isSelected: isSelected)
      } else if record.isPinned {
        Image(systemName: "pin.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
          .accessibilityLabel("Pinned")
      }

      Spacer()
    }
    .frame(minHeight: QuickPanelLayoutMetrics.compactRowMinHeight)
    .padding(.vertical, QuickPanelLayoutMetrics.rowInnerVerticalPadding)
    .padding(.horizontal, 10)
    .background(isSelected ? Color.accentColor : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .task(id: record.id) {
      guard QuickPanelRowPresentation.contentVisual(for: record) == .imagePreview else {
        imagePreview = nil
        return
      }

      imagePreview = await imagePreviewLoader(record)
    }
  }
}

private struct QuickPanelShortcutBadge: View {
  let shortcut: QuickPanelRowShortcut
  let isSelected: Bool

  var body: some View {
    Text(shortcut.label)
      .font(.caption.weight(.bold))
      .monospacedDigit()
      .foregroundStyle(isSelected ? Color.accentColor : .secondary)
      .frame(minWidth: 22, minHeight: 22)
      .padding(.horizontal, shortcut.label.count > 1 ? 5 : 0)
      .background(
        Capsule()
          .fill(isSelected ? Color.white.opacity(0.92) : Color.secondary.opacity(0.16))
      )
      .accessibilityLabel(shortcut.accessibilityLabel)
  }
}

private struct QuickPanelRowMouseCaptureView: NSViewRepresentable {
  let rowIndex: Int
  let interaction: QuickPanelMouseInteraction

  func makeNSView(context: Context) -> MouseCaptureNSView {
    let view = MouseCaptureNSView()
    updateNSView(view, context: context)
    return view
  }

  func updateNSView(_ nsView: MouseCaptureNSView, context: Context) {
    nsView.onMouseDown = { clickCount in
      interaction.handleMouseDown(rowIndex: rowIndex, clickCount: clickCount)
    }
  }

  final class MouseCaptureNSView: NSView {
    var onMouseDown: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
      onMouseDown?(event.clickCount)
    }
  }
}

private struct SourceAppIconView: View {
  let sourceIcon: NSImage?
  let fallbackSymbolName: String
  let visual: QuickPanelSourceVisual
  let isSelected: Bool

  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 6)
        .fill(isSelected ? Color.white.opacity(0.18) : Color.secondary.opacity(0.12))

      if let sourceIcon, visual == .sourceAppIcon {
        Image(nsImage: sourceIcon)
          .resizable()
          .scaledToFit()
          .frame(width: 24, height: 24)
          .clipShape(RoundedRectangle(cornerRadius: 6))
      } else {
        Image(systemName: fallbackSymbolName)
          .font(.system(size: 17, weight: .medium))
          .foregroundStyle(isSelected ? .white : .cyan)
      }
    }
    .frame(width: 34, height: 34)
    .accessibilityHidden(true)
  }
}

private struct ContentPreviewView: View {
  let record: ClipboardRecord
  let imagePreview: NSImage?
  let contentVisual: QuickPanelContentVisual
  let isSelected: Bool

  @ViewBuilder
  var body: some View {
    switch contentVisual {
    case .imagePreview:
      if let imagePreview {
        Image(nsImage: imagePreview)
          .resizable()
          .scaledToFill()
          .frame(width: 84, height: 48, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .strokeBorder(Color.white.opacity(isSelected ? 0.36 : 0.16), lineWidth: 1)
          )
      } else {
        HStack(spacing: 8) {
          Image(systemName: "photo")
            .font(.system(size: 16, weight: .medium))

          Text(record.title)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
        }
        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        .frame(height: 48, alignment: .center)
      }
    case .text:
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(QuickPanelRowPresentation.primaryContentText(for: record))
          .font(.callout.weight(.semibold))
          .lineLimit(1)
          .foregroundStyle(isSelected ? .white : .primary)

        if record.isLargeContent {
          Text("Large")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isSelected ? .white.opacity(0.85) : .orange)
        }
      }
    }
  }
}
