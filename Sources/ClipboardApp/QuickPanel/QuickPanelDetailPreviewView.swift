import SwiftUI

struct QuickPanelDetailPreviewView: View {
  let preview: QuickPanelDetailPreview

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text(preview.title)
          .font(.headline)
          .lineLimit(2)
        Text(preview.source)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let image = preview.image {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .accessibilityLabel(preview.title)
      } else {
        ScrollView {
          Text(preview.body)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if preview.isTruncated {
          Text("Preview truncated to keep QuickPanel responsive.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(16)
    .frame(minWidth: 560, minHeight: 360)
  }
}
