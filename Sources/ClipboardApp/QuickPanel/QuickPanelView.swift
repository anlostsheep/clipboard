import ClipboardCore
import SwiftUI

struct QuickPanelView: View {
  @ObservedObject var state: QuickPanelState
  let onClose: () -> Void
  let onSubmit: () -> Void
  @FocusState private var isSearchFocused: Bool

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
          QuickPanelRow(record: record, isSelected: index == state.selectedIndex)
            .id(record.id)
            .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
        }
        .listStyle(.plain)
        .onChange(of: state.selectedIndex) { _, selectedIndex in
          guard state.items.indices.contains(selectedIndex) else {
            return
          }

          proxy.scrollTo(state.items[selectedIndex].id, anchor: .center)
        }
      }
    }
  }

  private var footer: some View {
    HStack {
      Text(state.footerStatus)
        .foregroundStyle(.secondary)
      Spacer()
      Text("Return Paste  Esc Close")
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

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: iconName)
        .frame(width: 22)
        .foregroundStyle(isSelected ? .white : .cyan)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(record.title)
            .font(.headline)
            .lineLimit(1)

          if record.isLargeContent {
            Text("Large")
              .font(.caption.weight(.semibold))
              .foregroundStyle(isSelected ? .white.opacity(0.85) : .orange)
          }
        }

        if let preview = record.plainTextPreview, !preview.isEmpty {
          Text(preview)
            .font(.caption)
            .foregroundStyle(isSelected ? .white.opacity(0.82) : .secondary)
            .lineLimit(2)
        }

        Text(record.sourceAppName ?? "Unknown App")
          .font(.caption2)
          .foregroundStyle(isSelected ? .white.opacity(0.7) : .secondary)
      }

      Spacer()
    }
    .padding(.vertical, 6)
    .padding(.horizontal, 8)
    .background(isSelected ? Color.accentColor : Color.clear)
    .clipShape(RoundedRectangle(cornerRadius: 8))
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
