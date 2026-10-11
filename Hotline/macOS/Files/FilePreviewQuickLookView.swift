import SwiftUI
import UniformTypeIdentifiers
import ImageIO
import AVFoundation
import AVKit

struct FilePreviewQuickLookView: View {
  enum FilePreviewFocus: Hashable {
    case window
  }

  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.dismiss) private var dismiss

  @Binding var info: PreviewFileInfo?
  @State private var preview: FilePreviewState? = nil
  /// What the file shows and how big, when it's a picture or a video, which get the whole window,
  /// shaped like them, as a video player does.
  @State private var media: Media? = nil
  /// The file, once it's known whether it's a picture or video, so it isn't shown as a document
  /// first.
  @State private var checkedFile: URL? = nil
  /// For an archive, which can't be copied to Downloads, as it isn't here, or audio or video
  /// that's still on its way, that it's being downloaded, as any file is.
  @State private var downloadStarted = false
  /// Whether the title bar shows over a picture or video, which is darker under it while it does.
  @State private var showsTitleBar = true
  /// The picture or video the window's been fitted to, which it's no smaller than after.
  @State private var fittedMedia: Media? = nil

  @FocusState private var focusField: FilePreviewFocus?

  struct Media: Equatable {
    enum Kind {
      case picture
      case video
      case audio
    }

    let kind: Kind
    let size: CGSize
    /// A picture, as it's drawn: as the system reads it, or a PICT as our decoder drew it.
    var image: NSImage? = nil
    /// What plays audio or video that's playing as it comes.
    var player: AVPlayer? = nil
    /// Audio without a cover, which plays in the row it came in, in a window the same size.
    var compact = false
  }

  /// What the window shows, as the file comes and once it has.
  private enum Content {
    case downloading
    case failed
    /// A picture or video that's here, or audio or video playing as it comes, which carries on as
    /// it was once all of it has.
    case media(URL?, Media)
    case document(URL)
    case archive(ArchiveKind, [ArchiveEntry])
    case unpreviewable
  }

  var body: some View {
    Group {
      switch self.content {
      case .downloading:
        self.downloadingView
      case .failed:
        self.failedView
      case .media(let fileURL, let media):
        self.mediaView(fileURL, media: media)
      case .document(let fileURL):
        QuickLookPreviewView(fileURL: fileURL)
          .frame(minWidth: 400, maxWidth: .infinity, minHeight: 400, maxHeight: .infinity)
          .background { WindowGrowth(size: Self.documentSize) }
      case .archive(let kind, let entries):
        FilePreviewArchiveView(kind: kind, entries: entries)
          .background { WindowGrowth(size: Self.documentSize) }
      case .unpreviewable:
        self.unpreviewableView
          .background { WindowGrowth(size: Self.documentSize) }
      }
    }
    .focusable()
    .focusEffectDisabled()
    .background(Color(nsColor: .textBackgroundColor))
    .focused(self.$focusField, equals: .window)
    // As Quick Look's own window closes.
    .onKeyPress(.space) {
      self.dismiss()
      return .handled
    }
    .navigationTitle(self.info?.name ?? "File Preview")
    .applyNavigationDocumentIfPresent(self.preview?.fileURL)
    .toolbar {
      // There from the start, though they can't be used till the file's come, so the window's title
      // bar is the same height before and after.
      ToolbarItem(placement: .primaryAction) {
        Button {
          self.downloadFile()
        } label: {
          Label("Download File...", systemImage: "arrow.down")
        }
        .help("Download File")
        .disabled(!self.canDownload)
      }
      // An archive isn't here to share, only what's in it.
      if self.info?.isArchive != true {
        ToolbarItem(placement: .primaryAction) {
          self.shareButton
            .help("Share File")
        }
      }
    }
    // Only a document can have anything under the title bar that it needs a background over.
    .toolbarBackgroundVisibility(self.showsDocument ? .automatic : .hidden, for: .windowToolbar)
    .task {
      if let info = self.info {
        self.preview = FilePreviewState(info: info)
        self.preview?.download()
      }
    }
    .task(id: self.preview?.fileURL) {
      guard let fileURL = self.preview?.fileURL else {
        return
      }
      // Audio or video playing as it came carries on as it is.
      if self.preview?.playing != nil {
        self.checkedFile = fileURL
        return
      }
      if self.preview?.previewType == .pict {
        self.media = self.preview?.image.map { Media(kind: .picture, size: $0.size, image: $0) }
      }
      else {
        var media = await Self.media(at: fileURL)
        // Playing as soon as it's shown.
        if media?.kind == .video {
          media?.player = AVPlayer(url: fileURL)
          media?.player?.play()
        }
        self.media = media
      }
      self.checkedFile = fileURL
    }
    .onAppear {
      guard self.info != nil else {
        self.dismiss()
        return
      }

      self.focusField = .window
    }
    .onDisappear {
      self.preview?.cancel()
      self.preview?.cleanup()
      self.media?.player?.pause()
      self.dismiss()
    }
    // Pictures, videos and audio in dark, as photo, video and music apps show them, and anything
    // else as other windows are.
    .preferredColorScheme(self.isMedia ? .dark : nil)
  }

  /// Whether the window's for a picture, a video or audio: one its name says it is, from the start,
  /// or one it turned out to be.
  private var isMedia: Bool {
    if case .media = self.content {
      return true
    }
    return self.info?.isMedia == true
  }

  /// Whether there's a file to download: the one that's here, or one that isn't yet, or can't be,
  /// downloaded as any file is, once.
  private var canDownload: Bool {
    guard let info = self.info else {
      return false
    }
    if info.isArchive || (self.preview?.isStreaming == true && self.preview?.fileURL == nil) {
      return !self.downloadStarted
    }
    return self.preview?.fileURL != nil
  }

  /// The bottom of a video, where its controls are, which stay, with the title bar, while the
  /// pointer's on them.
  private static let videoControlsHeight: CGFloat = 90
  /// How big the window is for a picture, a video or audio as it comes, below its title bar: just
  /// big enough for its row, which audio without a cover stays in, and which anything else grows
  /// from, to its own size.
  static let compactSize = CGSize(width: 440, height: 104)
  static let compactMinimumWidth: CGFloat = 380
  /// How far in from the window's sides that row is.
  static let compactInset: CGFloat = 16
  /// How big the window is for anything else, below its title bar, at first.
  static let documentSize = CGSize(width: 450, height: 498)

  /// Shares the file, or a PICT as the picture our decoder made of it, which more can open.
  @ViewBuilder
  private var shareButton: some View {
    let label = Label("Share File...", systemImage: "square.and.arrow.up")
    if let image = self.media?.image, let name = self.info?.name {
      ShareLink(item: image, preview: SharePreview(name, image: image)) {
        label
      }
    }
    else if let fileURL = self.preview?.fileURL {
      ShareLink(item: fileURL) {
        label
      }
    }
    else {
      Button {} label: {
        label
      }
      .disabled(true)
    }
  }

  /// What to show, going by how far the file's come and what it turned out to be.
  private var content: Content {
    if let playing = self.preview?.playing {
      switch playing.kind {
      case .video:
        return .media(self.preview?.fileURL, Media(kind: .video, size: playing.size, player: playing.player))
      case .audio:
        let compact = playing.cover == nil
        return .media(self.preview?.fileURL, Media(kind: .audio, size: compact ? Self.compactSize : FilePreviewAudioView.coverSize, player: playing.player, compact: compact))
      }
    }
    switch self.preview?.state {
    case .failed:
      return .failed
    case .loaded:
      // Not shown as a document while it's still being found out whether it plays, should all of
      // it come first.
      if self.preview?.isStreaming == true, self.preview?.isUnplayable == false {
        return .downloading
      }
      if let archive = self.preview?.archive, let kind = self.info?.archiveKind {
        return .archive(kind, archive)
      }
      guard let fileURL = self.preview?.fileURL else {
        return .unpreviewable
      }
      // Only a moment, while it's found out whether it's a picture or video.
      guard fileURL == self.checkedFile else {
        return .downloading
      }
      if let media = self.media {
        return .media(fileURL, media)
      }
      // A PICT our decoder couldn't make out, which Quick Look can't either.
      if self.preview?.previewType == .pict {
        return .unpreviewable
      }
      return .document(fileURL)
    default:
      return .downloading
    }
  }

  private var showsDocument: Bool {
    switch self.content {
    case .document, .archive:
      return true
    default:
      return false
    }
  }

  /// Into Downloads: a copy of the file that's here, or an archive, which isn't, or audio or video
  /// that's still on its way, downloaded as any file is, from the server, with the rest of the
  /// transfers.
  private func downloadFile() {
    guard let info = self.info else {
      return
    }
    if !info.isArchive, let fileURL = self.preview?.fileURL {
      FileManager.default.copyToDownloads(from: fileURL, using: info.name, bounceDock: true)
    }
    else if let hotlineID = info.hotlineID, let hotline = AppState.shared.hotline(id: hotlineID), let path = info.path {
      hotline.downloadFile(info.name, path: path)
      self.downloadStarted = true
    }
  }

  /// Audio without a cover, in the row it came in, in a window the same size, or anything else, in
  /// the window shaped to it.
  @ViewBuilder
  private func mediaView(_ fileURL: URL?, media: Media) -> some View {
    if media.compact, let playing = self.preview?.playing, let preview = self.preview {
      FilePreviewAudioView(playing: playing, preview: preview)
        .frame(minWidth: Self.compactMinimumWidth, maxWidth: .infinity, minHeight: Self.compactSize.height, maxHeight: Self.compactSize.height)
        .background { CompactWindow() }
    }
    else {
      self.shapedMediaView(fileURL, media: media)
    }
  }

  /// A picture or video, or audio's cover, edge to edge, under a title bar that comes and goes with
  /// the pointer, in a window shaped like it that's moved by dragging it.
  private func shapedMediaView(_ fileURL: URL?, media: Media) -> some View {
    Group {
      if let image = media.image {
        PictureView(image: image)
      }
      else if media.kind == .audio, let playing = self.preview?.playing, let preview = self.preview {
        FilePreviewAudioView(playing: playing, preview: preview)
      }
      else if let player = media.player {
        VideoView(player: player)
      }
    }
    // No taller at first than the row it came in, so the window grows from that to its shape in
    // one go, and once it has, no smaller than a picture gets.
    .frame(minWidth: MediaWindow.minimumSize.width, maxWidth: .infinity, minHeight: self.fittedMedia == media ? MediaWindow.minimumSize.height : Self.compactSize.height, maxHeight: .infinity)
    .ignoresSafeArea()
    // A shade behind the title bar, so it can be read over any picture: dark under Dark Mode's light
    // text, and light under light mode's dark text.
    .overlay(alignment: .top) {
      let shade: Color = self.colorScheme == .dark ? .black : .white
      LinearGradient(colors: [shade.opacity(0.55), shade.opacity(0)], startPoint: .top, endPoint: .bottom)
        .frame(height: 90)
        .opacity(self.showsTitleBar ? 1 : 0)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    // Dragging it moves the window, as in QuickTime Player, from anywhere but a video's controls,
    // which are over it. Audio's player moves it itself, from anywhere but its controls.
    .overlay {
      if media.kind != .audio {
        Color.clear
          .contentShape(.rect)
          .gesture(WindowDragGesture())
          // From the first click, while the window's behind others.
          .allowsWindowActivationEvents(true)
          .ignoresSafeArea()
      }
    }
    .overlay {
      if media.kind == .video, let player = media.player {
        // What's come of it along its timeline, as it's playing as it comes, or all of it.
        VideoControls(player: player, downloaded: self.preview?.isStreaming == true ? self.preview?.downloadedParts ?? [] : [0..<1], shown: self.showsTitleBar)
          .ignoresSafeArea()
      }
    }
    .background {
      MediaWindow(media: media, controlsHeight: media.kind == .video ? Self.videoControlsHeight : 0) { shown in
        withAnimation(shown ? .easeOut(duration: MediaWindow.showDuration) : .easeIn(duration: MediaWindow.hideDuration)) {
          self.showsTitleBar = shown
        }
      } fitted: {
        self.fittedMedia = media
      }
      // Under the title bar too, so going onto it isn't leaving.
      .ignoresSafeArea()
    }
  }

  /// The file on its way, in a row like a copy in the Finder: its icon, and its name over how
  /// much of it has come. Closing the window stops it.
  private var downloadingView: some View {
    self.fileRow {
      Group {
        if let preview = self.preview, preview.transferred > 0, preview.total > 0 {
          ProgressView(value: max(0.0, min(1.0, preview.progress)))
        }
        else {
          ProgressView()
        }
      }
      .progressViewStyle(.linear)
      // The bar a copy in the Finder has, with less room around it than the regular one.
      .controlSize(.small)
      Text(self.progressDescription)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }

  /// The same row, when the file didn't come, with a way to try again.
  private var failedView: some View {
    self.fileRow(failed: true) {
      Text("Couldn't download this file.")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
      Button("Try Again") {
        self.preview?.download()
      }
      .controlSize(.small)
      .padding(.top, 4)
    }
  }

  /// The file's icon, with its name beside it over whatever's to say about it: in the middle of the
  /// window, or for a picture, a video or audio, along a window just big enough for it.
  @ViewBuilder
  private func fileRow(failed: Bool = false, @ViewBuilder details: () -> some View) -> some View {
    // A document icon's page only fills the middle 31 pt of its 48 pt square, so this leaves about
    // 12 pt between the page and the text.
    let row = HStack(alignment: .center, spacing: 4) {
      FileIconView(filename: self.info?.name ?? "", fileType: self.info?.type)
        .frame(width: 48, height: 48)
        .overlay(alignment: .bottomTrailing) {
          if failed {
            // On the page's bottom corner, hanging just past it to the right about as much as below.
            Image(systemName: "exclamationmark.triangle.fill")
              .symbolRenderingMode(.multicolor)
              .font(.system(size: 16))
              .offset(x: -4)
          }
        }
      VStack(alignment: .leading, spacing: 3) {
        Text(self.info?.name ?? "")
          .font(.system(size: 13, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.middle)
        details()
      }
    }
    if self.info?.isMedia == true {
      row
        .padding(.leading, Self.compactInset)
        .padding(.trailing, Self.compactInset + 4)
        .frame(minWidth: Self.compactMinimumWidth, idealWidth: Self.compactSize.width, maxWidth: .infinity, minHeight: Self.compactSize.height, idealHeight: Self.compactSize.height, maxHeight: Self.compactSize.height, alignment: .leading)
        .background { CompactWindow() }
    }
    else {
      row
        // From the same place whatever's beside the icon, so it doesn't move when a download fails.
        .frame(width: 320, alignment: .leading)
        .frame(minWidth: 380, idealWidth: Self.documentSize.width, maxWidth: .infinity, minHeight: 200, idealHeight: Self.documentSize.height, maxHeight: .infinity)
    }
  }

  private var unpreviewableView: some View {
    VStack(alignment: .center, spacing: 0) {
      Spacer()

      Image(systemName: "eye.trianglebadge.exclamationmark")
        .resizable()
        .scaledToFit()
        .frame(maxWidth: .infinity)
        .frame(height: 48)
        .padding(.bottom)
      Group {
        Text("This file type is not previewable")
          .bold()
        Text("Try downloading and opening this file in another application.")
          .foregroundStyle(Color.secondary)
      }
      .font(.system(size: 14.0))
      .frame(maxWidth: 300)
      .multilineTextAlignment(.center)

      Spacer()
      Spacer()
    }
    .frame(minWidth: 350, maxWidth: .infinity, minHeight: 150, maxHeight: .infinity)
    .padding()
  }

  /// How much has come of how much, and about how long the rest will take, or before any of it has
  /// come, that it's connecting.
  private var progressDescription: String {
    if self.info?.isArchive == true {
      return "Previewing archive contents…"
    }
    guard let preview = self.preview, preview.transferred > 0 else {
      return "Connecting…"
    }
    // A picture from the web can come without saying how big it is.
    guard preview.total > 0 else {
      return Self.byteCount(preview.transferred)
    }
    let sizes = "\(Self.byteCount(preview.transferred)) of \(Self.byteCount(preview.total))"
    guard let remaining = preview.timeRemaining, remaining.isFinite, remaining >= 1 else {
      return sizes
    }
    let duration = Duration.seconds(remaining.rounded()).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 1))
    return "\(sizes), about \(duration) left"
  }

  private static func byteCount(_ bytes: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
  }

  /// A picture or video, and its size as it's shown, or nil for anything else.
  private static func media(at url: URL) async -> Media? {
    if let picture = self.picture(at: url) {
      return Media(kind: .picture, size: picture.size, image: picture)
    }
    if let size = await self.videoSize(at: url) {
      return Media(kind: .video, size: size)
    }
    return nil
  }

  /// The file as a picture, turned upright if it's stored on its side, when the system can read it
  /// as one. Not a PDF, which NSImage would read too, but is a document.
  private static func picture(at url: URL) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          properties[kCGImagePropertyPixelWidth] != nil,
          let picture = NSImage(contentsOf: url), picture.size.width > 0, picture.size.height > 0 else {
      return nil
    }
    return picture
  }

  /// A video's size, turned the way it plays.
  private static func videoSize(at url: URL) async -> CGSize? {
    let asset = AVURLAsset(url: url)
    guard let track = try? await asset.loadTracks(withMediaType: .video).first,
          let (size, transform) = try? await track.load(.naturalSize, .preferredTransform) else {
      return nil
    }
    let turned = size.applying(transform)
    let shown = CGSize(width: abs(turned.width), height: abs(turned.height))
    return shown.width > 0 && shown.height > 0 ? shown : nil
  }
}

/// A picture, in the middle of whatever room it's given, smaller to fit it but never bigger than it
/// is. An image view draws it again at each size, so a PICT, which our decoder makes into a PDF,
/// stays sharp, and plays it, if it's animated.
private struct PictureView: NSViewRepresentable {
  let image: NSImage

  func makeNSView(context: Context) -> NSImageView {
    let view = NSImageView()
    view.imageScaling = .scaleProportionallyDown
    view.animates = true
    view.image = self.image
    return view
  }

  func updateNSView(_ view: NSImageView, context: Context) {
    view.image = self.image
  }

  // The window's shaped by the picture, so the view's whatever the window makes it.
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSImageView, context: Context) -> CGSize? {
    proposal.replacingUnspecifiedDimensions()
  }
}

/// A video, by the player playing it, which plays and stops with the preview, without the player's
/// own controls, as the window has its own over it.
private struct VideoView: NSViewRepresentable {
  let player: AVPlayer

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.controlsStyle = .none
    view.player = self.player
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
  }

  static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
    view.player = nil
  }

  // The window's shaped by the video, so the view's whatever the window makes it.
  func sizeThatFits(_ proposal: ProposedViewSize, nsView: AVPlayerView, context: Context) -> CGSize? {
    proposal.replacingUnspecifiedDimensions()
  }
}

/// The window around a picture or video: sized to fit it when it comes and kept in its proportions
/// as it's resized, with the title bar over it shown while the pointer moves, and while it's on the
/// title bar.
private struct MediaWindow: NSViewRepresentable {
  let media: FilePreviewQuickLookView.Media
  /// How far up from its bottom its controls go, for a video, which stay while the pointer's on
  /// them.
  let controlsHeight: CGFloat
  /// Told when the title bar shows or hides.
  let titleBarShown: (Bool) -> Void
  /// Told once the window's fitted to it.
  let fitted: () -> Void

  static let showDuration = 0.2
  static let hideDuration = 0.4
  /// The smallest the picture or video gets: room across for the title bar's buttons, and under
  /// the title bar for something. The window's that, with the title bar.
  static let minimumSize = NSSize(width: 320, height: 200)

  func makeNSView(context: Context) -> WindowView {
    WindowView(media: self.media, controlsHeight: self.controlsHeight)
  }

  func updateNSView(_ view: WindowView, context: Context) {
    view.titleBarShown = self.titleBarShown
    view.fitted = self.fitted
  }

  final class WindowView: NSView {
    let media: FilePreviewQuickLookView.Media
    let controlsHeight: CGFloat
    var titleBarShown: ((Bool) -> Void)?
    var fitted: (() -> Void)?
    private var showsTitleBar = true
    /// Where the pointer was when it last moved, on the screen.
    private var pointer: NSPoint?

    /// How long the pointer's still before the title bar hides.
    private static let hideDelay: TimeInterval = 2.5
    /// How far the pointer goes before it's moved, rather than a mouse's jitter, or an event that
    /// says it moved when it didn't.
    private static let pointerSlop: CGFloat = 2

    init(media: FilePreviewQuickLookView.Media, controlsHeight: CGFloat) {
      self.media = media
      self.controlsHeight = controlsHeight
      super.init(frame: .zero)
      // All of the window, title bar too, as it's resized.
      self.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      NSObject.cancelPreviousPerformRequests(withTarget: self)
      guard let window = self.window else {
        return
      }
      // The picture under the title bar, which is see-through over it, in a window that stays as
      // it was till it's fitted to it, rather than losing the title bar's height.
      if !window.styleMask.contains(.fullSizeContentView) {
        let frame = window.frame
        window.styleMask.insert(.fullSizeContentView)
        window.setFrame(frame, display: false)
      }
      window.titlebarAppearsTransparent = true
      // Shown at first, so it's clear it's there, then out of the way.
      self.pointer = NSEvent.mouseLocation
      self.revealTitleBar()
      // Once the window's taken in the picture's smaller minimum size.
      DispatchQueue.main.async { [weak self] in
        self?.fit()
      }
    }

    override func mouseMoved(with event: NSEvent) {
      self.pointerMoved()
    }

    override func mouseEntered(with event: NSEvent) {
      self.pointerMoved()
    }

    override func mouseExited(with event: NSEvent) {
      NSObject.cancelPreviousPerformRequests(withTarget: self)
      self.showTitleBar(false)
    }

    /// Shows the title bar again, if the pointer's really gone somewhere.
    private func pointerMoved() {
      let location = NSEvent.mouseLocation
      if let pointer = self.pointer, hypot(location.x - pointer.x, location.y - pointer.y) < Self.pointerSlop {
        return
      }
      self.pointer = location
      self.revealTitleBar()
    }

    /// Shows the title bar, to hide again once the pointer's been still a moment.
    private func revealTitleBar() {
      self.showTitleBar(true)
      NSObject.cancelPreviousPerformRequests(withTarget: self)
      self.perform(#selector(self.hideTitleBarUnlessUsed), with: nil, afterDelay: Self.hideDelay)
    }

    /// Hides the title bar, unless the pointer's on it, to use its buttons.
    @objc private func hideTitleBarUnlessUsed() {
      guard let window = self.window, let titleBar = self.titleBar else {
        return
      }
      // Unless the pointer's on it, to use its buttons, or on a video's controls.
      let pointer = window.convertPoint(fromScreen: NSEvent.mouseLocation)
      let controls = NSRect(x: 0, y: 0, width: window.frame.width, height: self.controlsHeight)
      guard !titleBar.convert(titleBar.bounds, to: nil).contains(pointer), !controls.contains(pointer) else {
        return
      }
      self.showTitleBar(false)
    }

    /// Fades the title bar, buttons and all, in or out.
    private func showTitleBar(_ shown: Bool) {
      guard shown != self.showsTitleBar, let titleBar = self.titleBar else {
        return
      }
      self.showsTitleBar = shown
      NSAnimationContext.runAnimationGroup { context in
        context.duration = shown ? MediaWindow.showDuration : MediaWindow.hideDuration
        titleBar.animator().alphaValue = shown ? 1 : 0
      }
      self.titleBarShown?(shown)
    }

    /// What holds the window's buttons, title and toolbar.
    private var titleBar: NSView? {
      self.window?.standardWindowButton(.closeButton)?.superview?.superview
    }

    /// As big as the picture, but no more than two thirds of the screen each way, so it doesn't take
    /// it over, and no smaller than the minimum, around where the window was. It's the picture's
    /// shape, and keeps it as it's resized, when the picture fits it that way. A picture too small or
    /// too thin for that sits in the middle, and the window can be any shape.
    private func fit() {
      guard let window = self.window, let screen = window.screen ?? NSScreen.main else {
        return
      }
      let size = self.media.size
      // Any size, now, rather than only as tall as the row it came in.
      window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
      let room = NSSize(width: screen.visibleFrame.width * 2 / 3, height: screen.visibleFrame.height * 2 / 3)
      let scale = min(1, room.width / size.width, room.height / size.height)
      let fitted = NSSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
      // The smallest the picture gets, with the title bar, which it's kept to once it's fitted.
      let titleBar = window.frame.height - window.contentLayoutRect.height
      let minimum = NSSize(width: max(window.contentMinSize.width, MediaWindow.minimumSize.width), height: max(window.contentMinSize.height, MediaWindow.minimumSize.height + titleBar))
      if fitted.width >= minimum.width && fitted.height >= minimum.height {
        window.contentAspectRatio = size
      }
      else {
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
      }
      let frameSize = NSSize(width: max(fitted.width, minimum.width), height: max(fitted.height, minimum.height))
      var frame = NSRect(x: window.frame.midX - frameSize.width / 2, y: window.frame.midY - frameSize.height / 2, width: frameSize.width, height: frameSize.height)
      frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
      frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
      // Which is done once it returns.
      window.setFrame(frame, display: true, animate: true)
      self.fitted?()
    }
  }
}

/// The window around the row a picture, a video or audio comes in, and audio without a cover plays
/// in: as tall as the row, and as wide as it's made, from a little wider than the row at first.
private struct CompactWindow: NSViewRepresentable {
  func makeNSView(context: Context) -> WindowView {
    WindowView()
  }

  func updateNSView(_ view: WindowView, context: Context) {
  }

  static func dismantleNSView(_ view: WindowView, coordinator: ()) {
    view.release()
  }

  final class WindowView: NSView {
    private weak var sizedWindow: NSWindow?

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window = self.window else {
        return
      }
      self.sizedWindow = window
      let size = FilePreviewQuickLookView.compactSize
      window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: size.height)
      // The row and its title bar as one.
      window.titlebarAppearsTransparent = true
      window.titlebarSeparatorStyle = .none
      let content = window.contentRect(forFrameRect: window.frame)
      guard content.height != size.height else {
        return
      }
      var frame = window.frameRect(forContentRect: NSRect(x: content.midX - size.width / 2, y: content.maxY - size.height, width: size.width, height: size.height))
      if let screen = window.screen ?? NSScreen.main {
        frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
      }
      window.setFrame(frame, display: true, animate: window.isVisible)
    }

    /// Lets the window be any height again, for what's shown in place of the row, unless it's
    /// audio without a cover, whose row takes its place.
    func release() {
      guard let window = self.sizedWindow else {
        return
      }
      DispatchQueue.main.async {
        guard let content = window.contentView, !Self.isShown(in: content) else {
          return
        }
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.titlebarSeparatorStyle = .automatic
      }
    }

    private static func isShown(in view: NSView) -> Bool {
      view is WindowView || view.subviews.contains { self.isShown(in: $0) }
    }
  }
}

/// Makes the window at least so big, for a document shown in a window that was just big enough for
/// the row it came in, as a file named like a picture, a video or audio that isn't one is.
private struct WindowGrowth: NSViewRepresentable {
  let size: CGSize

  func makeNSView(context: Context) -> GrowthView {
    GrowthView(size: self.size)
  }

  func updateNSView(_ view: GrowthView, context: Context) {
  }

  final class GrowthView: NSView {
    let size: CGSize

    init(size: CGSize) {
      self.size = size
      super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      guard let window = self.window else {
        return
      }
      // A title bar of its own again, over a document.
      window.titlebarAppearsTransparent = false
      let content = window.contentRect(forFrameRect: window.frame)
      guard content.width < self.size.width || content.height < self.size.height else {
        return
      }
      let grown = NSSize(width: max(content.width, self.size.width), height: max(content.height, self.size.height))
      var frame = window.frameRect(forContentRect: NSRect(x: content.midX - grown.width / 2, y: content.maxY - grown.height, width: grown.width, height: grown.height))
      if let screen = window.screen ?? NSScreen.main {
        frame.origin.x = min(max(frame.minX, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
      }
      window.setFrame(frame, display: true, animate: window.isVisible)
    }
  }
}

/// A video's controls, over a shade along its bottom, shown with the title bar, and while it's
/// paused.
private struct VideoControls: View {
  let player: AVPlayer
  let downloaded: [Range<Double>]
  /// Whether the title bar's shown.
  let shown: Bool

  @State private var playback: MediaPlayback? = nil

  var body: some View {
    let visible = self.shown || self.playback?.isPlaying == false
    ZStack(alignment: .bottom) {
      LinearGradient(colors: [.black.opacity(0), .black.opacity(0.35), .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
        .frame(height: 110)
        .allowsHitTesting(false)
      if let playback = self.playback {
        MediaControls(playback: playback, downloaded: self.downloaded, large: true)
          .foregroundStyle(.white)
          .padding(.horizontal, 20)
          .padding(.bottom, 14)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .opacity(visible ? 1 : 0)
    // Out of the way when they're hidden, so the video can be dragged by its bottom too.
    .allowsHitTesting(visible)
    .animation(.easeOut(duration: MediaWindow.showDuration), value: self.playback?.isPlaying)
    .task {
      self.playback = MediaPlayback(player: self.player)
    }
    .onDisappear {
      self.playback?.stop()
    }
  }
}
