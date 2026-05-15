import AppKit
import ClipboardCore
import SwiftUI

struct QuickPanelView: View {
  @ObservedObject var state: QuickPanelState
  let onClose: () -> Void
  let onSubmit: () -> Void
  @FocusState private var isSearchFocused: Bool
  @State private var scrollCoordinator = QuickPanelScrollCoordinator()
  @State private var sourceAppIconProvider = SourceAppIconProvider()
  @AppStorage(ClipboardAppSettings.quickPanelReturnCopiesOnlyKey)
  private var quickPanelReturnCopiesOnly = false

  var body: some View {
    VStack(spacing: 0) {
      searchField

      Divider()

      results

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
      .frame(width: 260)

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
        List(Array(state.items.enumerated()), id: \.element.id) { index, record in
          QuickPanelRow(
            record: record,
            isSelected: index == state.selectedIndex,
            sourceIcon: sourceAppIconProvider.icon(for: record),
            imagePreviewLoader: { record in
              await state.imagePreview(for: record)
            }
          )
          .id(record.id)
          .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
        .listStyle(.plain)
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
      withAnimation(.easeOut(duration: 0.12)) {
        proxy.scrollTo(target.recordID, anchor: anchor)
      }
    }
  }

  private var shortcutHint: String {
    quickPanelReturnCopiesOnly ? "Return Copy  Cmd+V Paste  Esc Close" : "Return Paste  Esc Close"
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
      },
      onSubmit: onSubmit,
      onCancel: onClose
    )
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
