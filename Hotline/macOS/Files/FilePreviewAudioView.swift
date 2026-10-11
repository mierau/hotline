import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

/// Audio playing as it comes, with what it's called and who it's by, and its controls, its
/// timeline showing what's come of it, which can be gone to anywhere along, come or not. With a
/// cover, the cover fills the window, with all that over the bottom of it. Without one, it's in a
/// row like the one it came in, its icon beside it, in a window the same size.
struct FilePreviewAudioView: View {
  let playing: PlayingMedia
  let preview: FilePreviewState

  /// How big the window is around a cover, at first.
  static let coverSize = CGSize(width: 400, height: 400)

  @State private var playback: MediaPlayback? = nil

  var body: some View {
    Group {
      if let cover = self.playing.cover {
        self.coverLayout(cover)
      }
      else {
        self.rowLayout
      }
    }
    .task {
      self.playback = MediaPlayback(player: self.playing.player)
    }
    .onDisappear {
      self.playback?.stop()
    }
  }

  /// The cover, edge to edge, under the title bar, with what it is and its controls over a shade
  /// at the bottom of it. Dragging it, anywhere but its controls, moves the window.
  private func coverLayout(_ cover: NSImage) -> some View {
    ZStack(alignment: .bottom) {
      Image(nsImage: cover)
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityLabel("Cover")
      Self.windowDrag
      LinearGradient(colors: [.black.opacity(0), .black.opacity(0.45), .black.opacity(0.75)], startPoint: .top, endPoint: .bottom)
        .frame(height: 170)
        .allowsHitTesting(false)
      VStack(alignment: .leading, spacing: 2) {
        Text(self.title)
          .font(.system(size: 17, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.tail)
          .allowsHitTesting(false)
        Text(self.subtitle)
          .font(.system(size: 13))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .allowsHitTesting(false)
        if let playback = self.playback {
          MediaControls(playback: playback, downloaded: self.preview.downloadedParts, large: true)
            .padding(.top, 10)
        }
      }
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 20)
      .padding(.bottom, 18)
    }
  }

  /// Its icon, as it was shown as it came, beside what it is and its controls, in the same place.
  private var rowLayout: some View {
    HStack(alignment: .center, spacing: 4) {
      FileIconView(filename: self.preview.info.name, fileType: self.preview.info.type)
        .frame(width: 48, height: 48)
        .allowsHitTesting(false)
      VStack(alignment: .leading, spacing: 1) {
        Text(self.title)
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.tail)
          .allowsHitTesting(false)
        Text(self.subtitle)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .allowsHitTesting(false)
        if let playback = self.playback {
          MediaControls(playback: playback, downloaded: self.preview.downloadedParts, large: false)
            .padding(.top, 3)
        }
      }
    }
    .padding(.leading, FilePreviewQuickLookView.compactInset)
    .padding(.trailing, FilePreviewQuickLookView.compactInset + 4)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background {
      Self.windowDrag
    }
  }

  /// Behind what's shown, which lets clicks through to it but on its controls, for moving the
  /// window by dragging it, from the first click.
  private static var windowDrag: some View {
    Color.clear
      .contentShape(.rect)
      .gesture(WindowDragGesture())
      .allowsWindowActivationEvents(true)
  }

  /// What it's called, or the file's name, when it doesn't say.
  private var title: String {
    if let title = self.playing.title, !title.isEmpty {
      return title
    }
    return (self.preview.info.name as NSString).deletingPathExtension
  }

  /// Who it's by and what it's from, or what kind of file it is, when it doesn't say.
  private var subtitle: String {
    let said = [self.playing.artist, self.playing.album].compactMap { $0 }.filter { !$0.isEmpty }
    if !said.isEmpty {
      return said.joined(separator: " — ")
    }
    let fileExtension = (self.preview.info.name as NSString).pathExtension
    return UTType(filenameExtension: fileExtension)?.localizedDescription ?? "Audio"
  }
}
