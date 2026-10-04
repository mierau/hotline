import AppKit
import Kingfisher

/// Small previews of images linked in chat, shown under the message.
///
/// Each preview is a text attachment backed by a view, which TextKit 2 only creates while the
/// message is on screen, so a long chat full of image links costs nothing until you scroll to them.
///
/// Previews are kept on disk once they've loaded, and so is each image's size, so when the chat
/// opens again they show straight away, at their real size, without downloading again.
enum ChatImagePreview {
  /// Previews fit within this. Smaller images show at their own size.
  static let maximumSize = CGSize(width: 240, height: 120)
  /// The size of an image we haven't seen before, until it loads.
  static let placeholderSize = CGSize(width: 160, height: 90)

  private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

  /// Whether a link looks like an image worth previewing. Only https, since the app doesn't allow
  /// insecure loads anyway.
  static func canPreview(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && self.imageExtensions.contains(url.pathExtension.lowercased())
  }

  /// How big a preview of an image this many pixels in size is: a point per pixel, the way web
  /// pages show images, scaled down to fit if it's bigger than the maximum.
  static func previewSize(forImageSize size: CGSize?) -> CGSize {
    guard let size, size.width > 0, size.height > 0 else {
      return self.placeholderSize
    }
    let scale = min(1, self.maximumSize.width / size.width, self.maximumSize.height / size.height)
    return CGSize(width: max(16, (size.width * scale).rounded()), height: max(16, (size.height * scale).rounded()))
  }

  /// In the app's Caches folder, which macOS can clear when space runs low. A preview that's gone
  /// downloads again.
  private static let directory = URL.cachesDirectory
    .appending(path: Bundle.main.bundleIdentifier ?? "Hotline", directoryHint: .isDirectory)
    .appending(path: "Chat Image Previews", directoryHint: .isDirectory)

  /// Previews that have loaded. Only the preview is kept, not the full image, since clicking a
  /// preview opens its link rather than showing the image here.
  static let cache: ImageCache = {
    // Kingfisher's own folder, since it clears out files it doesn't know.
    let images = directory.appending(path: "Images", directoryHint: .isDirectory)
    let cache = (try? ImageCache(name: "Chat Image Previews", cacheDirectoryURL: images, diskCachePathClosure: { directory, _ in directory }))
      ?? ImageCache(name: "Chat Image Previews")
    cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024
    cache.diskStorage.config.expiration = .days(30)
    cache.memoryStorage.config.totalCostLimit = 64 * 1024 * 1024
    return cache
  }()

  /// The sizes of images previewed before.
  static let sizes = ChatImagePreviewSizes(fileURL: directory.appending(path: "Sizes.plist", directoryHint: .notDirectory))

  /// Downloads previews, turning away anything that isn't an image or is too big to be worth it.
  static let downloader: ImageDownloader = {
    let downloader = ImageDownloader(name: "Chat Image Previews")
    downloader.downloadTimeout = 20
    downloader.delegate = ChatImageDownloadCheck.shared
    return downloader
  }()
}

/// Checks each preview's response before its data downloads.
private final class ChatImageDownloadCheck: ImageDownloaderDelegate {
  static let shared = ChatImageDownloadCheck()

  /// Bigger images don't download at all.
  private let sizeLimit: Int64 = 10 * 1024 * 1024

  func imageDownloader(_ downloader: ImageDownloader, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
    guard response.mimeType?.lowercased().hasPrefix("image/") == true,
          response.expectedContentLength <= self.sizeLimit else {
      return .cancel
    }
    return .allow
  }
}

// MARK: - Sizes

/// The sizes of images previewed before, by link, so a preview is its real size from the start
/// instead of growing into it when its image loads.
final class ChatImagePreviewSizes: @unchecked Sendable {
  private struct Entry {
    var size: CGSize
    var added: TimeInterval
  }

  private let fileURL: URL
  /// Past this many images, the ones added longest ago are forgotten.
  private let limit: Int
  private let lock = NSLock()
  /// Nil until read from disk, the first time a size is asked for.
  private var entries: [String: Entry]?
  private var saveScheduled = false

  init(fileURL: URL, limit: Int = 5000) {
    self.fileURL = fileURL
    self.limit = limit
  }

  /// The size in pixels of the image at a link, if it's been previewed before.
  func size(for url: URL) -> CGSize? {
    self.lock.withLock {
      self.loadIfNeeded()
      return self.entries?[url.absoluteString]?.size
    }
  }

  /// Keeps an image's size for next time. Saved a moment later, along with any others that come in.
  func remember(_ size: CGSize, for url: URL) {
    let scheduleSave: Bool = self.lock.withLock {
      self.loadIfNeeded()
      let key = url.absoluteString
      guard self.entries?[key]?.size != size else {
        return false
      }
      self.entries?[key] = Entry(size: size, added: Date().timeIntervalSince1970)
      if let entries = self.entries, entries.count > self.limit {
        let oldest = entries.sorted { $0.value.added < $1.value.added }.prefix(entries.count - self.limit * 4 / 5)
        for (key, _) in oldest {
          self.entries?[key] = nil
        }
      }
      defer { self.saveScheduled = true }
      return !self.saveScheduled
    }
    if scheduleSave {
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
        self.save()
      }
    }
  }

  func save() {
    let plist: [String: [Double]] = self.lock.withLock {
      self.saveScheduled = false
      return (self.entries ?? [:]).mapValues { [$0.size.width, $0.size.height, $0.added] }
    }
    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else {
      return
    }
    try? FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: self.fileURL, options: .atomic)
  }

  private func loadIfNeeded() {
    guard self.entries == nil else {
      return
    }
    var entries: [String: Entry] = [:]
    if let data = try? Data(contentsOf: self.fileURL),
       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [Double]] {
      for (key, value) in plist where value.count == 3 && value[0] > 0 && value[1] > 0 {
        entries[key] = Entry(size: CGSize(width: value[0], height: value[1]), added: value[2])
      }
    }
    self.entries = entries
  }
}

// MARK: - Attachment

/// A link to an image, shown as a preview.
final class ChatImageAttachment: NSTextAttachment {
  let url: URL
  /// The image's size in pixels, once it's known, from loading it now or before.
  var imageSize: CGSize?

  init(url: URL) {
    self.url = url
    self.imageSize = ChatImagePreview.sizes.size(for: url)
    super.init(data: nil, ofType: nil)
    self.allowsTextAttachmentView = true
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  // The preview is a view, so the attachment draws nothing itself. Otherwise it draws a generic
  // document icon, since it has no file contents, behind the preview.
  override func image(for bounds: CGRect, attributes: [NSAttributedString.Key: Any], location: any NSTextLocation, textContainer: NSTextContainer?) -> NSImage? {
    nil
  }

  override func viewProvider(for parentView: NSView?, location: any NSTextLocation, textContainer: NSTextContainer?) -> NSTextAttachmentViewProvider? {
    let provider = ChatImagePreviewProvider(
      textAttachment: self,
      parentView: parentView,
      textLayoutManager: textContainer?.textLayoutManager,
      location: location
    )
    provider.tracksTextAttachmentViewBounds = true
    return provider
  }

  var previewSize: CGSize {
    ChatImagePreview.previewSize(forImageSize: self.imageSize)
  }
}

final class ChatImagePreviewProvider: NSTextAttachmentViewProvider {
  override func loadView() {
    guard let attachment = self.textAttachment as? ChatImageAttachment else {
      return
    }
    let view = ChatImagePreviewView(url: attachment.url)
    view.onLoad = { [weak self] imageSize in
      self?.imageDidLoad(imageSize: imageSize)
    }
    self.view = view
  }

  override func attachmentBounds(
    for attributes: [NSAttributedString.Key: Any],
    location: any NSTextLocation,
    textContainer: NSTextContainer?,
    proposedLineFragment: CGRect,
    position: CGPoint
  ) -> CGRect {
    let size = (self.textAttachment as? ChatImageAttachment)?.previewSize ?? ChatImagePreview.placeholderSize
    // Sit on the line a little above the baseline, with some room below.
    return CGRect(x: 0, y: -4, width: size.width, height: size.height)
  }

  /// Once the image loads, remembers its size for next time and, unless the preview was already
  /// the right size, lays the line out again at it. Scrolled to the bottom of the chat, it stays
  /// there.
  private func imageDidLoad(imageSize: CGSize) {
    guard let attachment = self.textAttachment as? ChatImageAttachment, imageSize.width > 0, imageSize.height > 0 else {
      return
    }
    ChatImagePreview.sizes.remember(imageSize, for: attachment.url)
    let previousSize = attachment.previewSize
    attachment.imageSize = imageSize
    guard attachment.previewSize != previousSize else {
      return
    }

    guard let textLayoutManager = self.textLayoutManager,
          let end = textLayoutManager.location(self.location, offsetBy: 1),
          let range = NSTextRange(location: self.location, end: end) else {
      return
    }
    textLayoutManager.invalidateLayout(for: range)
    textLayoutManager.textViewportLayoutController.layoutViewport()
  }
}

// MARK: - View

/// The preview itself: the image, rounded, filling its box. Clicking it opens the link.
final class ChatImagePreviewView: NSView {
  let url: URL
  /// Called with the image's size in pixels once it loads.
  var onLoad: ((CGSize) -> Void)?

  private let imageView = NSImageView()
  private var started = false

  init(url: URL) {
    self.url = url
    super.init(frame: .zero)

    self.wantsLayer = true
    self.layer?.cornerRadius = 6
    self.layer?.masksToBounds = true
    self.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    self.toolTip = ChatTranscriptTextView.openLinkText(for: url, shownAs: "")
    self.setAccessibilityLabel("Image preview")

    self.imageView.imageScaling = .scaleProportionallyUpOrDown
    self.imageView.animates = true
    self.imageView.wantsLayer = true
    self.imageView.layer?.cornerRadius = 6
    self.imageView.layer?.masksToBounds = true
    self.imageView.frame = self.bounds
    self.addSubview(self.imageView)
  }

  // A preview of an image we haven't seen before takes the image's size once it loads, but until
  // its size catches up, keep the image from stretching: fit it from the top left.
  override func layout() {
    super.layout()
    guard let size = self.imageView.image?.size, size.width > 0, size.height > 0 else {
      self.imageView.frame = self.bounds
      return
    }
    let scale = min(self.bounds.width / size.width, self.bounds.height / size.height)
    self.imageView.frame = CGRect(x: 0, y: 0, width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
  }

  override var isFlipped: Bool { true }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if self.window != nil {
      self.load()
    }
  }

  // The layer's color doesn't follow the appearance on its own.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    self.effectiveAppearance.performAsCurrentDrawingAppearance {
      self.layer?.backgroundColor = NSColor.quaternarySystemFill.cgColor
    }
  }

  private func load() {
    guard !self.started else {
      return
    }
    self.started = true

    // From the cache if it's been shown before, which fades in only after a download.
    var options: KingfisherOptionsInfo = [
      .targetCache(ChatImagePreview.cache),
      .downloader(ChatImagePreview.downloader),
      .backgroundDecode,
      .transition(.fade(0.2)),
    ]
    // Big images are decoded at preview size, with pixels enough for a Retina screen whatever
    // screen it's on, so it's cached the same way everywhere. Not GIFs, which would lose their
    // animation.
    if self.url.pathExtension.lowercased() != "gif" {
      options.append(.processor(DownsamplingImageProcessor(size: ChatImagePreview.maximumSize)))
      options.append(.scaleFactor(2))
    }

    self.imageView.kf.setImage(with: self.url, options: options) { [weak self] result in
      guard let self, case .success(let value) = result else {
        return
      }
      self.layer?.backgroundColor = nil
      self.needsLayout = true
      self.onLoad?(Self.pixelSize(of: value.image))
    }
  }

  /// An image's size in pixels, from the bitmap itself. The sizes NSImage reports depend on how it
  /// was made, and asking it for a bitmap at its size can scale one down. A preview decoded down
  /// is the smaller size, which comes to the same preview, since it was too big to show at its own
  /// size anyway.
  private static func pixelSize(of image: NSImage) -> CGSize {
    guard let representation = image.representations.first else {
      return image.size
    }
    if let cgImage = representation.cgImage(forProposedRect: nil, context: nil, hints: nil) {
      return CGSize(width: cgImage.width, height: cgImage.height)
    }
    if representation.pixelsWide > 0, representation.pixelsHigh > 0 {
      return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
    }
    return image.size
  }

  // MARK: Clicking

  // Clicks go to the preview, not the image view inside it.
  override func hitTest(_ point: NSPoint) -> NSView? {
    self.frame.contains(point) ? self : nil
  }

  override func resetCursorRects() {
    self.addCursorRect(self.bounds, cursor: .pointingHand)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {}

  override func mouseUp(with event: NSEvent) {
    guard self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
      return
    }
    var view = self.superview
    while let current = view, !(current is ChatTranscriptTextView) {
      view = current.superview
    }
    if let textView = view as? ChatTranscriptTextView, let openURL = textView.openURLAction {
      openURL(self.url)
    }
    else {
      NSWorkspace.shared.open(self.url)
    }
  }
}
