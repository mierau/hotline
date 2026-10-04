import SwiftUI
import Quartz

/// Embeddable QuickLook preview view for macOS
///
/// This view uses QLPreviewView to display file previews inline, without showing a modal.
/// Supports all file types that QuickLook supports (images, PDFs, videos, documents, etc.)
struct QuickLookPreviewView: NSViewRepresentable {
  let fileURL: URL

  func makeNSView(context: Context) -> QLPreviewView {
    let preview = QLPreviewView(frame: .zero, style: .normal)!
    preview.autostarts = true
    // Closed in dismantleNSView instead. SwiftUI can update the preview after its window closes,
    // and Quick Look crashes when a preview that closed with its window is given an item.
    preview.shouldCloseWithWindow = false
    preview.previewItem = fileURL as QLPreviewItem
    return preview
  }

  func updateNSView(_ nsView: QLPreviewView, context: Context) {
    guard (nsView.previewItem as? URL) != self.fileURL else { return }
    nsView.previewItem = self.fileURL as QLPreviewItem
  }

  static func dismantleNSView(_ nsView: QLPreviewView, coordinator: ()) {
    nsView.close()
  }
}
