import AppKit
import Kingfisher
import UniformTypeIdentifiers

/// Small previews of images linked in chat, shown under the message.
///
/// Each preview is a text attachment backed by a view, which TextKit 2 only creates while the
/// message is on screen, so a long chat full of image links costs nothing until you scroll to them.
///
/// Previews are kept on disk once they've loaded, and so is each image's size, so when the chat
/// opens again they show straight away, at their real size, without downloading again.
enum ChatImagePreview {
  /// Previews fit within this. Smaller images show at their own size, and tall ones, like a phone's
  /// screenshots, have room to be more than a sliver.
  static let maximumSize = CGSize(width: 240, height: 200)
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

  /// Links whose image couldn't be had, which aren't shown or tried again for a while.
  static let failures = ChatImagePreviewFailures(fileURL: directory.appending(path: "Failures.plist", directoryHint: .notDirectory))

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

// MARK: - Failures

/// Links whose image couldn't be had: while the app's open, and when the server said no, as long
/// after as a preview that loaded is kept. One that couldn't be reached, which may be there next
/// time, gets another try once the app opens again.
final class ChatImagePreviewFailures: @unchecked Sendable {
  private let fileURL: URL
  /// How long a link the server said no to isn't tried again.
  private let keepFor: TimeInterval
  private let lock = NSLock()
  private var thisTime: Set<String> = []
  /// When the server said no to each link. Nil until read from disk, the first time it's needed.
  private var refused: [String: TimeInterval]?
  private var saveScheduled = false

  init(fileURL: URL, keepFor: TimeInterval = 30 * 24 * 60 * 60) {
    self.fileURL = fileURL
    self.keepFor = keepFor
  }

  func contains(_ url: URL) -> Bool {
    self.lock.withLock {
      let key = url.absoluteString
      if self.thisTime.contains(key) {
        return true
      }
      self.loadIfNeeded()
      guard let date = self.refused?[key] else {
        return false
      }
      return Date().timeIntervalSince1970 - date < self.keepFor
    }
  }

  /// Keeps a link whose image couldn't be had, past this time the app's open if the server
  /// `refused` it. Saved a moment later, along with any others that come in.
  func insert(_ url: URL, refused: Bool) {
    let scheduleSave: Bool = self.lock.withLock {
      let key = url.absoluteString
      self.thisTime.insert(key)
      guard refused else {
        return false
      }
      self.loadIfNeeded()
      self.refused?[key] = Date().timeIntervalSince1970
      defer { self.saveScheduled = true }
      return !self.saveScheduled
    }
    if scheduleSave {
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
        self.save()
      }
    }
  }

  private func save() {
    let plist: [String: Double] = self.lock.withLock {
      self.saveScheduled = false
      // Only the ones still kept.
      let now = Date().timeIntervalSince1970
      return (self.refused ?? [:]).filter { now - $0.value < self.keepFor }
    }
    guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else {
      return
    }
    try? FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: self.fileURL, options: .atomic)
  }

  private func loadIfNeeded() {
    guard self.refused == nil else {
      return
    }
    if let data = try? Data(contentsOf: self.fileURL),
       let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Double] {
      self.refused = plist
    }
    else {
      self.refused = [:]
    }
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

  /// Forgets an image's size, for one that can't be had anymore.
  func forget(_ url: URL) {
    let scheduleSave: Bool = self.lock.withLock {
      self.loadIfNeeded()
      guard self.entries?.removeValue(forKey: url.absoluteString) != nil else {
        return false
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
  /// Whether the preview takes up any room: from the start for an image that's loaded before, or
  /// else once its image starts to come in, so a link to one that can't be had shows nothing.
  var isShown: Bool

  init(url: URL) {
    self.url = url
    self.imageSize = ChatImagePreview.sizes.size(for: url)
    self.isShown = self.imageSize != nil && !ChatImagePreview.failures.contains(url)
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
    view.showsPlaceholder = attachment.isShown
    view.onStart = { [weak self] in
      self?.show()
    }
    view.onLoad = { [weak self] imageSize in
      self?.imageDidLoad(imageSize: imageSize)
    }
    view.onFail = { [weak self] refused in
      self?.hide(refused: refused)
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
    // A point, rather than nothing, which TextKit would take to mean the attachment's usual size.
    guard let attachment = self.textAttachment as? ChatImageAttachment, attachment.isShown else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let size = attachment.previewSize
    // Sit on the line a little above the baseline, with some room below.
    return CGRect(x: 0, y: -4, width: size.width, height: size.height)
  }

  /// Makes room for the preview once its image starts to come in, until it's here.
  private func show() {
    guard let attachment = self.textAttachment as? ChatImageAttachment, !attachment.isShown else {
      return
    }
    attachment.isShown = true
    (self.view as? ChatImagePreviewView)?.showsPlaceholder = true
    self.layOutAgain()
  }

  /// Takes the preview away, for an image that can't be had: for good if the server `refused` it,
  /// or else until the app opens again.
  private func hide(refused: Bool) {
    guard let attachment = self.textAttachment as? ChatImageAttachment else {
      return
    }
    ChatImagePreview.failures.insert(attachment.url, refused: refused)
    ChatImagePreview.sizes.forget(attachment.url)
    guard attachment.isShown else {
      return
    }
    attachment.isShown = false
    (self.view as? ChatImagePreviewView)?.showsPlaceholder = false
    self.layOutAgain()
  }

  /// Lays the preview's line out again at its new size. Scrolled to the bottom of the chat, it
  /// stays there.
  private func layOutAgain() {
    guard let textLayoutManager = self.textLayoutManager,
          let end = textLayoutManager.location(self.location, offsetBy: 1),
          let range = NSTextRange(location: self.location, end: end) else {
      return
    }
    textLayoutManager.invalidateLayout(for: range)
    textLayoutManager.textViewportLayoutController.layoutViewport()
  }

  /// Once the image loads, remembers its size for next time and, unless the preview was already
  /// showing at the right size, lays the line out again at it.
  private func imageDidLoad(imageSize: CGSize) {
    guard let attachment = self.textAttachment as? ChatImageAttachment, imageSize.width > 0, imageSize.height > 0 else {
      return
    }
    ChatImagePreview.sizes.remember(imageSize, for: attachment.url)
    let previousSize = attachment.previewSize
    let wasShown = attachment.isShown
    attachment.imageSize = imageSize
    attachment.isShown = true
    guard attachment.previewSize != previousSize || !wasShown else {
      return
    }
    self.layOutAgain()
  }
}

// MARK: - View

/// The preview itself: the image, rounded, filling its box. Clicking it opens the image in a
/// preview window, dragging it takes the image along, and its menu has what a link's has.
final class ChatImagePreviewView: NSView, NSDraggingSource {
  let url: URL
  /// Called once the image starts to come in.
  var onStart: (() -> Void)?
  /// Called with the image's size in pixels once it loads.
  var onLoad: ((CGSize) -> Void)?
  /// Called if the image can't be had, with whether the server said no, rather than not being
  /// reached.
  var onFail: ((_ refused: Bool) -> Void)?
  /// Whether the gray box shows where the image will be, until it's here.
  var showsPlaceholder = false {
    didSet {
      self.updatePlaceholder()
    }
  }

  private let imageView = NSImageView()
  private var started = false

  init(url: URL) {
    self.url = url
    super.init(frame: .zero)

    self.wantsLayer = true
    self.layer?.cornerRadius = 6
    self.layer?.masksToBounds = true
    self.toolTip = url.host(percentEncoded: false).map { "View image from \($0)" } ?? "View Image"
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
    self.updatePlaceholder()
  }

  private func updatePlaceholder() {
    let showsPlaceholder = self.showsPlaceholder && self.imageView.image == nil
    self.effectiveAppearance.performAsCurrentDrawingAppearance {
      self.layer?.backgroundColor = showsPlaceholder ? NSColor.quaternarySystemFill.cgColor : nil
    }
  }

  private func load() {
    guard !self.started else {
      return
    }
    self.started = true
    guard !ChatImagePreview.failures.contains(self.url) else {
      self.onFail?(false)
      return
    }

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

    var reportedStart = false
    self.imageView.kf.setImage(with: self.url, options: options, progressBlock: { [weak self] _, _ in
      guard !reportedStart else {
        return
      }
      reportedStart = true
      self?.onStart?()
    }) { [weak self] result in
      guard let self else {
        return
      }
      switch result {
      case .success(let value):
        self.updatePlaceholder()
        self.needsLayout = true
        self.onLoad?(Self.pixelSize(of: value.image))
      case .failure(let error):
        // Not when it was only stopped, as when the view went away.
        if !error.isTaskCancelled && !error.isNotCurrentTask {
          self.onFail?(Self.wasRefused(error))
        }
      }
    }
  }

  /// Whether the server said no: turned the request away, or sent something that isn't an image,
  /// or one too big, or one that can't be read. Not when it couldn't be reached, or was busy or in
  /// trouble for the moment, which can pass.
  private static func wasRefused(_ error: KingfisherError) -> Bool {
    switch error {
    case .responseError(reason: .invalidHTTPStatusCode(let response)):
      return (400..<500).contains(response.statusCode) && response.statusCode != 408 && response.statusCode != 429
    case .responseError(reason: .cancelledByDelegate), .processorError:
      return true
    default:
      return false
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

  // Clicks go to the preview, not the image view inside it, and nowhere while it isn't showing.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard self.showsPlaceholder || self.imageView.image != nil else {
      return nil
    }
    return self.frame.contains(point) ? self : nil
  }

  override func resetCursorRects() {
    self.addCursorRect(self.bounds, cursor: .pointingHand)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  /// Where the button went down, until it comes up, in case it's the start of a drag.
  private var mouseDownEvent: NSEvent?
  private var dragged = false

  override func mouseDown(with event: NSEvent) {
    self.mouseDownEvent = event
    self.dragged = false
  }

  override func mouseUp(with event: NSEvent) {
    defer {
      self.mouseDownEvent = nil
    }
    guard !self.dragged, self.bounds.contains(self.convert(event.locationInWindow, from: nil)) else {
      return
    }
    let textView = self.transcript
    if let openImage = textView?.openImageAction {
      openImage(self.url)
    }
    else if let openURL = textView?.openURLAction {
      openURL(self.url)
    }
    else {
      NSWorkspace.shared.open(self.url)
    }
  }

  /// The transcript it's in.
  private var transcript: ChatTranscriptTextView? {
    var view = self.superview
    while let current = view, !(current is ChatTranscriptTextView) {
      view = current.superview
    }
    return view as? ChatTranscriptTextView
  }

  // MARK: Menu

  override func menu(for event: NSEvent) -> NSMenu? {
    guard let items = self.transcript?.linkMenuItems(for: self.url) else {
      return nil
    }
    let menu = NSMenu()
    for item in items {
      menu.addItem(item)
    }
    return menu
  }

  // MARK: Dragging

  // Dragged a little way, it takes the image along, which arrives whole where it's dropped.
  override func mouseDragged(with event: NSEvent) {
    guard !self.dragged, let down = self.mouseDownEvent, let image = self.imageView.image else {
      return
    }
    let start = down.locationInWindow
    let now = event.locationInWindow
    guard hypot(now.x - start.x, now.y - start.y) > 3 else {
      return
    }
    self.dragged = true
    let item = NSDraggingItem(pasteboardWriter: ChatImageFilePromise(url: self.url))
    item.setDraggingFrame(self.imageView.frame, contents: image)
    self.beginDraggingSession(with: [item], event: down, source: self)
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    .copy
  }
}

// MARK: - Dragging Out

/// A preview dragged out of chat: the image as a file, downloaded whole once it's dropped, and its
/// link, for anywhere a link goes rather than a file.
final class ChatImageFilePromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
  let url: URL

  private static let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated
    return queue
  }()

  init(url: URL) {
    self.url = url
    super.init()
    self.fileType = (UTType(filenameExtension: url.pathExtension) ?? .image).identifier
    self.delegate = self
  }

  override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
    super.writableTypes(for: pasteboard) + [.URL, .string]
  }

  override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
    switch type {
    case .URL:
      return (self.url as NSURL).pasteboardPropertyList(forType: .URL)
    case .string:
      return self.url.absoluteString
    default:
      return super.pasteboardPropertyList(forType: type)
    }
  }

  func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
    let name = self.url.lastPathComponent.removingPercentEncoding ?? self.url.lastPathComponent
    return name.isEmpty || name == "/" ? "Image" : name
  }

  func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
    Self.queue
  }

  func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void) {
    URLSession.shared.downloadTask(with: self.url) { downloaded, response, error in
      guard let downloaded, let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
        completionHandler(error ?? URLError(.badServerResponse))
        return
      }
      do {
        try FileManager.default.moveItem(at: downloaded, to: url)
        completionHandler(nil)
      }
      catch {
        completionHandler(error)
      }
    }.resume()
  }
}
