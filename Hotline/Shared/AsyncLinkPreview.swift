import SwiftUI
import LinkPresentation

fileprivate class CustomLinkView: LPLinkView {
  override var intrinsicContentSize: CGSize { CGSize(width: 0, height: super.intrinsicContentSize.height) }
}

struct AsyncLinkPreview: View {
  @State private var metadata: LPLinkMetadata?
  @State private var isLoading = true
  let url: URL?
  
  func fetchMetadata() async {
    guard let url else {
      self.isLoading = false
      return
    }
    do {
      let provider = LPMetadataProvider()
      let metadata = try await provider.startFetchingMetadata(for: url)
      self.metadata = metadata
      self.isLoading = false
    } catch {
      self.isLoading = false
    }
  }
  
  var body: some View {
    if isLoading {
      ProgressView()
        .controlSize(.small)
        .task {
          await self.fetchMetadata()
        }
    } else if let metadata = metadata {
      LinkView(metadata: metadata)
        .frame(width: 200)
    } else {
      Text(LocalizedStringKey(url!.absoluteString.convertLinksToMarkdown()))
        .multilineTextAlignment(.leading)
        .tint(Color("Link Color"))
    }
  }
}

struct LinkView: NSViewRepresentable {
  var metadata: LPLinkMetadata
  
  func makeNSView(context: Context) -> LPLinkView {
    let linkView = CustomLinkView(metadata: metadata)
    return linkView
  }
  
  func updateNSView(_ nsView: LPLinkView, context: Context) {
    // Nothing required
  }
}
