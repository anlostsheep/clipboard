import AppKit
import ClipboardCore
import SwiftUI

struct QuickPanelView: View {
  @ObservedObject var state: QuickPanelState
  let onClose: () -> Void
  let onSubmit: () -> Void
  let onCopyOnly: () -> Void
  let onRequestAccessibilityAuthorization: () -> Void
  @FocusState private var isSearchFocused: Bool
  @State private var scrollCoordinator = QuickPanelScrollCoordinator()
  @State private var sourceAppIconProvider = SourceAppIconProvider()
  @State private var confirmsClearAll = false
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
    .frame(width: 620, height: 420)
    .background(.regularMaterial)
    .overlay(keyCapture.frame(width: 0, height: 0))
    .onAppear {
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
      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(state.itemSections) { section in
              QuickPanelSectionHeader(title: section.title)
              ForEach(section.rows) { row in
                QuickPanelRow(
                  record: row.record,
                  isSelected: row.index == state.selectedIndex,
                  sourceIcon: sourceAppIconProvider.icon(for: row.record),
                  imagePreviewLoader: { record in
                    await state.imagePreview(for: record)
                  }
                )
                .id(row.record.id)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
                .onTapGesture {
                  state.selectItem(at: row.index)
                  onSubmit()
                }

                Divider()
                  .padding(.leading, 50)
              }
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
        }
        .onChange(of: state.items.map(\.id)) { _, itemIDs in
          guard let target = scrollCoordinator.targetAfterItemsChanged(
            itemIDs: itemIDs,
            selectedIndex: state.selectedIndex
          ) else {
            return
          }

          scroll(proxy, to: target)
        }
        .onChange(of: state.selectedIndex) { _, selectedIndex in
          let itemIDs = state.items.map(\.id)
          guard let target = QuickPanelScrollCoordinator.targetForSelectionChange(
            itemIDs: itemIDs,
            selectedIndex: selectedIndex
          ) else {
            return
          }

          scroll(proxy, to: target)
        }
      }
    }
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
    if quickPanelReturnCopiesOnly {
      return "Return/Click 复制  Cmd+V 粘贴  Esc 关闭"
    }

    if state.actionPrompt == .autoPasteRequiresAccessibilityPermission {
      return "Return/Click 需要授权  Cmd+V 手动粘贴"
    }

    return "Return/Click 自动粘贴  Esc 关闭"
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
      }
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
  let sourceIcon: NSImage?
  let imagePreviewLoader: (ClipboardRecord) async -> NSImage?
  @State private var imagePreview: NSImage?

  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      SourceAppColumnView(
        sourceIcon: sourceIcon,
        sourceAppName: record.sourceAppName ?? "Unknown",
        showsSourceName: QuickPanelRowPresentation.showsSourceName(for: record),
        fallbackSymbolName: iconName,
        visual: QuickPanelRowPresentation.sourceVisual(for: record),
        isSelected: isSelected
      )

      ContentPreviewView(
        record: record,
        imagePreview: imagePreview,
        contentVisual: QuickPanelRowPresentation.contentVisual(for: record),
        isSelected: isSelected
      )
      .frame(maxWidth: .infinity, alignment: .leading)

      if record.isPinned {
        Image(systemName: "pin.fill")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
          .accessibilityLabel("Pinned")
      }

      Spacer()
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
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

  private var iconName: String {
    switch record.primaryType {
    case .text, .richText:
      return "doc.text"
    case .link:
      return "link"
    case .image:
      return "photo"
    case .file:
      return "doc"
    }
  }
}

private struct SourceAppColumnView: View {
  let sourceIcon: NSImage?
  let sourceAppName: String
  let showsSourceName: Bool
  let fallbackSymbolName: String
  let visual: QuickPanelSourceVisual
  let isSelected: Bool

  var body: some View {
    VStack(spacing: 5) {
      ZStack {
        RoundedRectangle(cornerRadius: 6)
          .fill(isSelected ? Color.white.opacity(0.18) : Color.secondary.opacity(0.12))

        if let sourceIcon, visual == .sourceAppIcon {
          Image(nsImage: sourceIcon)
            .resizable()
            .scaledToFit()
            .frame(width: 30, height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
          Image(systemName: fallbackSymbolName)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(isSelected ? .white : .cyan)
        }
      }
      .frame(width: 42, height: 42)
      .accessibilityHidden(true)

      if showsSourceName {
        Text(sourceAppName)
          .font(.caption2.weight(.semibold))
          .foregroundStyle(isSelected ? .white.opacity(0.78) : .secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity)
      }
    }
    .frame(width: 92)
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
          .frame(width: 126, height: 72, alignment: .leading)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .strokeBorder(Color.white.opacity(isSelected ? 0.36 : 0.16), lineWidth: 1)
          )
      } else {
        HStack(spacing: 8) {
          Image(systemName: "photo")
            .font(.system(size: 18, weight: .medium))

          Text(record.title)
            .font(.headline)
            .lineLimit(1)
        }
        .foregroundStyle(isSelected ? .white.opacity(0.9) : .secondary)
        .frame(height: 72, alignment: .center)
      }
    case .text:
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(QuickPanelRowPresentation.primaryContentText(for: record))
          .font(.headline)
          .lineLimit(2)
          .foregroundStyle(isSelected ? .white : .primary)

        if record.isLargeContent {
          Text("Large")
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? .white.opacity(0.85) : .orange)
        }
      }
    }
  }
}
