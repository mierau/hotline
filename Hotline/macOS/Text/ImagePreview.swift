import AppKit
import AVFoundation
import CoreImage
import Kingfisher
import os
import SensitiveContentAnalysis
import SwiftUI
import UniformTypeIdentifiers

/// Small previews of linked images, shown under the line with the link, in chat, on the board, in
/// the news and in private messages.
///
/// Each preview is a text attachment backed by a view, which TextKit 2 only creates while the line
/// is on screen, so a long chat full of image links costs nothing until you scroll to them.
///
/// Previews are kept on disk once they've loaded, and so is each image's size, so when they're
/// shown again they show straight away, at their real size, without downloading again.
enum ImagePreview {
  /// Previews fit within this. Smaller images show at their own size, and tall ones, like a phone's
  /// screenshots, have room to be more than a sliver.
  static let maximumSize = CGSize(width: 240, height: 200)
  /// The size of an image we haven't seen before, until it loads.
  static let placeholderSize = CGSize(width: 160, height: 90)

  private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "bmp", "tif", "tiff"]

  /// Bigger images don't download, whether they say how big they are first or not.
  static let sizeLimit: Int64 = 10 * 1024 * 1024

  /// Bigger pictures among a server's files aren't previewed: one linked to downloads to everyone
  /// there at once, from a server that could be on a home connection.
  static let serverSizeLimit = 5 * 1024 * 1024

  /// Whether a link looks like an image worth previewing. Only https, since the app doesn't allow
  /// insecure loads anyway.
  static func canPreview(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && self.imageExtensions.contains(url.pathExtension.lowercased())
  }

  /// The picture in a link to a page that only shows one: Reddit's viewer's, whose links are to
  /// reddit.com/media with the picture's own link after url=.
  static func picture(in url: URL) -> URL? {
    guard let host = url.host(percentEncoded: false)?.lowercased(),
          host == "reddit.com" || host.hasSuffix(".reddit.com"),
          url.path(percentEncoded: false) == "/media",
          let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value else {
      return nil
    }
    return URL(string: link)
  }

  /// Where pictures load from by themselves, rather than once their link's clicked. Loading one tells
  /// whoever serves it your IP address, and when you looked, so by themselves only from hosts where
  /// whoever put a picture up can't see who looked at it, image search's copies, and the server
  /// you're on, which has your address already, or from anywhere, as Settings can have it.
  struct Sources: Equatable, Sendable {
    /// The address of the server a window's for, whose own pictures load there too, but only there.
    var server: String?
    /// The server's port, and the connection to it, which pictures among its files load through,
    /// from links to them, hotline://server/files/....
    var serverPort: Int?
    var connection: UUID?
    /// Pictures from any site, as Settings can have it.
    var anySite = false

    /// Where a link to a file among the server's files goes: its path there, ending with its name,
    /// for a link in the server's own window, which it loads through the connection to it.
    func serverFile(at url: URL) -> [String]? {
      guard self.connection != nil, let server = self.server, let port = self.serverPort,
            let linked = Server(url: url), linked.address == server.lowercased(), linked.port == port,
            linked.initialSection == .files, let path = linked.initialFilePath else {
        return nil
      }
      return path
    }

    /// Whether pictures from where `url` is load by themselves, which a redirect to it can too.
    func trusts(_ url: URL) -> Bool {
      if self.serverFile(at: url) != nil {
        return true
      }
      guard url.scheme?.lowercased() == "https", let host = url.host(percentEncoded: false)?.lowercased() else {
        return false
      }
      return self.anySite
        || ImagePreview.trustedHosts.contains(host)
        || ImagePreview.trustedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
        || ImagePreview.thumbnailHosts.contains(host)
        || self.server?.lowercased() == host
    }

    /// Whether a link is shown as its picture's preview, loading by itself: from where it can, to
    /// one by its extension, or written as a picture in Markdown, or to image search's copies, which
    /// have none.
    func loadsByItself(_ url: URL, isImage: Bool) -> Bool {
      guard self.trusts(url) else {
        return false
      }
      return isImage
        || ImagePreview.imageExtensions.contains(url.pathExtension.lowercased())
        || ImagePreview.thumbnailHosts.contains(url.host(percentEncoded: false)?.lowercased() ?? "")
    }

    /// The picture shown for a link, loading by itself, if there's one: the link's own, or for a
    /// link to a page that only shows a picture, the picture in it, which loads from where it is,
    /// without the page.
    func picture(for url: URL, isImage: Bool) -> URL? {
      let picture = ImagePreview.picture(in: url) ?? url
      guard self.loadsByItself(picture, isImage: isImage) else {
        return nil
      }
      // One among the server's files, without the login and password its link can have, which the
      // window's connected with already, so they aren't kept with it.
      if self.serverFile(at: picture) != nil, var components = URLComponents(url: picture, resolvingAgainstBaseURL: false) {
        components.user = nil
        components.password = nil
        return components.url ?? picture
      }
      return picture
    }
  }

  /// Hosts of pictures where whoever put one up can't see who looked at it: image hosts, chat's and
  /// social sites', and reference sites'. Only these hosts, and not others under the same names,
  /// which could be anyone's.
  static let trustedHosts: Set<String> = [
    // Image hosts
    "i.imgur.com", "imgur.com",
    "i.giphy.com", "media.giphy.com", "media0.giphy.com", "media1.giphy.com", "media2.giphy.com", "media3.giphy.com", "media4.giphy.com",
    "media.tenor.com", "media1.tenor.com", "c.tenor.com",
    "i.gyazo.com",
    "image.prntscr.com",
    "i.postimg.cc",
    "i.ibb.co",
    "files.catbox.moe",
    // Chat and social sites
    "cdn.discordapp.com", "media.discordapp.net", "images-ext-1.discordapp.net", "images-ext-2.discordapp.net",
    "i.redd.it", "preview.redd.it", "external-preview.redd.it",
    "pbs.twimg.com",
    "cdn.bsky.app",
    "64.media.tumblr.com",
    "i.pinimg.com",
    "i.ytimg.com", "img.youtube.com",
    // Photos and reference
    "upload.wikimedia.org",
    "images.unsplash.com",
    "lh3.googleusercontent.com", "blogger.googleusercontent.com",
    "1.bp.blogspot.com", "2.bp.blogspot.com", "3.bp.blogspot.com", "4.bp.blogspot.com",
    "i.sstatic.net", "i.stack.imgur.com",
    // Apple's own pictures, and its artwork for apps, music and podcasts
    "www.apple.com",
    "is1-ssl.mzstatic.com", "is2-ssl.mzstatic.com", "is3-ssl.mzstatic.com", "is4-ssl.mzstatic.com", "is5-ssl.mzstatic.com",
    // GitHub
    "user-images.githubusercontent.com", "raw.githubusercontent.com", "avatars.githubusercontent.com",
  ]

  /// Sites whose every host under their name is their own: the Internet Archive, whose downloads
  /// come from numbered servers, like dn721509.ca.archive.org, and whose Wayback Machine has its own
  /// copies of old sites' pictures, so those sites don't see you either, Flickr, whose older links
  /// are to numbered servers too, and Meta, whose pictures for Instagram, Threads and Facebook come
  /// from servers all over, like scontent-lax3-1.cdninstagram.com. Their links stop working after a
  /// while, as Discord's do, by which time a preview's been kept.
  static let trustedDomains: [String] = ["archive.org", "staticflickr.com", "cdninstagram.com", "fbcdn.net"]

  /// Image search's own copies of pictures, whose links have no extension: Google's and Bing's
  /// thumbnails, and DuckDuckGo's and Brave's, which get the picture from where it is themselves,
  /// so that site doesn't see you either.
  static let thumbnailHosts: Set<String> = [
    "encrypted-tbn0.gstatic.com", "encrypted-tbn1.gstatic.com", "encrypted-tbn2.gstatic.com", "encrypted-tbn3.gstatic.com",
    "th.bing.com", "tse1.mm.bing.net", "tse2.mm.bing.net", "tse3.mm.bing.net", "tse4.mm.bing.net",
    "external-content.duckduckgo.com",
    "imgs.search.brave.com",
  ]

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
  /// downloads again. Named for chat, where previews were first, so the ones kept then still are.
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
  static let sizes = ImagePreviewSizes(fileURL: directory.appending(path: "Sizes.plist", directoryHint: .notDirectory))

  /// Links whose image couldn't be had, which aren't shown or tried again for a while.
  static let failures = ImagePreviewFailures(fileURL: directory.appending(path: "Failures.plist", directoryHint: .notDirectory))

  /// Downloads previews, turning away anything that isn't an image or is too big to be worth it, or
  /// still coming after a minute, as one that never ends would be.
  static let downloader: ImageDownloader = {
    let downloader = ImageDownloader(name: "Chat Image Previews")
    downloader.downloadTimeout = 20
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 60
    downloader.sessionConfiguration = configuration
    downloader.delegate = ImageDownloadCheck.shared
    return downloader
  }()
}

extension EnvironmentValues {
  /// Where a window's pictures load from by themselves: in a server's window, its server too.
  @Entry var imageSources = ImagePreview.Sources()
}

extension ImagePreview {
  /// Why a preview's picture couldn't be had, which says when it's tried again.
  enum Failure {
    /// The server said no, as for a picture that isn't one, or is too big: not for a while.
    case refused
    /// It couldn't be reached: not until the app opens again.
    case unreachable
    /// Not now, as for a server busy with others' downloads: the next time it's shown.
    case notNow
  }

  /// Opens a picture in a preview window, as clicking its preview does: one among a server's files
  /// as Quick Look in Files does, through the connection to it, and one from the web as it is.
  @MainActor
  static func open(_ url: URL, sources: Sources, openWindow: OpenWindowAction) {
    if let path = sources.serverFile(at: url), let name = path.last,
       let model = sources.connection.flatMap({ AppState.shared.hotline(id: $0) }) {
      FileActions(model: model, openWindow: openWindow).previewFile(FileInfo(linkedName: name, path: path, isFolder: false))
    }
    else {
      openWindow(id: "preview-quicklook", value: PreviewFileInfo(webImage: url))
    }
  }
}

/// A picture among the files of the server a window's connected to, read whole through the
/// connection, for Kingfisher to show, and keep, as it does a picture from the web.
struct ServerPicture: ImageDataProvider {
  let url: URL
  /// Where it is among the server's files, ending with its name.
  let path: [String]
  let connection: UUID
  /// Called as it starts to come.
  let started: @MainActor @Sendable () -> Void

  var cacheKey: String {
    self.url.absoluteString
  }

  func data() async throws -> Data {
    try await Self.read(self.path, through: self.connection, started: self.started)
  }

  @MainActor
  private static func read(_ path: [String], through connection: UUID, started: @MainActor () -> Void) async throws -> Data {
    guard let model = AppState.shared.hotline(id: connection) else {
      throw ServerPictureError.disconnected
    }
    return try await model.readPicture(at: path, limit: ImagePreview.serverSizeLimit, started: started)
  }
}

/// Checks each preview's response before its data downloads.
private final class ImageDownloadCheck: ImageDownloaderDelegate {
  static let shared = ImageDownloadCheck()

  /// Not one that says it's too big. One that doesn't say is stopped once too much of it has come.
  func imageDownloader(_ downloader: ImageDownloader, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
    guard response.mimeType?.lowercased().hasPrefix("image/") == true,
          response.expectedContentLength <= ImagePreview.sizeLimit else {
      return .cancel
    }
    return .allow
  }
}

// MARK: - Failures

/// Links whose image couldn't be had: while the app's open, and when the server said no, as long
/// after as a preview that loaded is kept. One that couldn't be reached, which may be there next
/// time, gets another try once the app opens again.
final class ImagePreviewFailures: @unchecked Sendable {
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
final class ImagePreviewSizes: @unchecked Sendable {
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

// MARK: - Text Views

/// A text view showing links and previews of images, which knows what clicking them does.
@MainActor
protocol LinkActions: AnyObject {
  /// Opens a link, as clicking it does.
  var openURLAction: ((URL) -> Void)? { get }
  /// Opens an image in a preview window, as clicking its preview does.
  var openImageAction: ((URL) -> Void)? { get }
  /// What can be done with a file a link's to, for its menu, which its picture's preview has too.
  var fileLinkMenu: ((URL) -> NSMenu?)? { get }
  /// After a preview's grown, or shrunk, to fit its image, or gone.
  func previewDidResize()
}

extension LinkActions {
  /// What can be done with a link to an image, for its preview's menu: open the image in a preview
  /// window, or the link the way a click on it does, or copy it, as macOS's menu for a link has.
  func linkMenuItems(for url: URL) -> [NSMenuItem] {
    var items: [NSMenuItem] = []
    if let openImage = self.openImageAction {
      items.append(ChatMenuItem("Open Image", systemImage: "photo") {
        openImage(url)
      })
    }
    let open = self.openURLAction
    items.append(ChatMenuItem("Open Link", systemImage: "arrow.up.forward.app") {
      if let open {
        open(url)
      }
      else {
        NSWorkspace.shared.open(url)
      }
    })
    items.append(ChatMenuItem("Copy Link", systemImage: "link") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(url.absoluteString, forType: .string)
    })
    return items
  }
}

// MARK: - Attachment

/// A link to an image, shown as a preview.
final class ImageAttachment: NSTextAttachment {
  let url: URL
  /// Whether it's all there is of its link, for an image written as one, ![like this](where it is),
  /// rather than a preview under a link that's there too.
  let standsForLink: Bool
  /// The image's size in pixels, once it's known, from loading it now or before.
  var imageSize: CGSize?
  /// Whether the preview takes up any room: from the start for an image that's loaded before, or
  /// else once its image starts to come in, so a link to one that can't be had shows nothing.
  var isShown: Bool
  /// Where it loads from by itself, which a redirect has to be to as well.
  let sources: ImagePreview.Sources

  init(url: URL, standsForLink: Bool = false, sources: ImagePreview.Sources = ImagePreview.Sources()) {
    self.url = url
    self.standsForLink = standsForLink
    self.sources = sources
    self.imageSize = ImagePreview.sizes.size(for: url)
    self.isShown = self.imageSize != nil && !ImagePreview.failures.contains(url)
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
    let provider = ImagePreviewProvider(
      textAttachment: self,
      parentView: parentView,
      textLayoutManager: textContainer?.textLayoutManager,
      location: location
    )
    provider.tracksTextAttachmentViewBounds = true
    return provider
  }

  var previewSize: CGSize {
    ImagePreview.previewSize(forImageSize: self.imageSize)
  }
}

final class ImagePreviewProvider: NSTextAttachmentViewProvider {
  override func loadView() {
    guard let attachment = self.textAttachment as? ImageAttachment else {
      return
    }
    let view = ImagePreviewView(url: attachment.url, sources: attachment.sources)
    view.showsPlaceholder = attachment.isShown
    view.onStart = { [weak self] in
      self?.show()
    }
    view.onLoad = { [weak self] imageSize in
      self?.imageDidLoad(imageSize: imageSize)
    }
    view.onFail = { [weak self] failure in
      self?.hide(for: failure)
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
    guard let attachment = self.textAttachment as? ImageAttachment, attachment.isShown else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let size = attachment.previewSize
    // Sit on the line a little above the baseline, with some room below.
    return CGRect(x: 0, y: -4, width: size.width, height: size.height)
  }

  /// Makes room for the preview once its image starts to come in, until it's here.
  private func show() {
    guard let attachment = self.textAttachment as? ImageAttachment, !attachment.isShown else {
      return
    }
    attachment.isShown = true
    (self.view as? ImagePreviewView)?.showsPlaceholder = true
    self.layOutAgain()
  }

  /// Takes the preview away, for an image that can't be had: for a while if the server refused it,
  /// until the app opens again if it couldn't be reached, or only for now.
  private func hide(for failure: ImagePreview.Failure) {
    guard let attachment = self.textAttachment as? ImageAttachment else {
      return
    }
    if failure != .notNow {
      ImagePreview.failures.insert(attachment.url, refused: failure == .refused)
      ImagePreview.sizes.forget(attachment.url)
    }
    guard attachment.isShown else {
      return
    }
    attachment.isShown = false
    (self.view as? ImagePreviewView)?.showsPlaceholder = false
    self.layOutAgain()
  }

  /// Lays the preview's line out again at its new size, and tells the text view it's in, which can
  /// keep its place, or grow to fit it.
  private func layOutAgain() {
    guard let textLayoutManager = self.textLayoutManager,
          let end = textLayoutManager.location(self.location, offsetBy: 1),
          let range = NSTextRange(location: self.location, end: end) else {
      return
    }
    textLayoutManager.invalidateLayout(for: range)
    textLayoutManager.textViewportLayoutController.layoutViewport()
    // On the main thread, where the image's view says it's loaded.
    MainActor.assumeIsolated {
      (textLayoutManager.textContainer?.textView as? LinkActions)?.previewDidResize()
    }
  }

  /// Once the image loads, remembers its size for next time and, unless the preview was already
  /// showing at the right size, lays the line out again at it.
  private func imageDidLoad(imageSize: CGSize) {
    guard let attachment = self.textAttachment as? ImageAttachment, imageSize.width > 0, imageSize.height > 0 else {
      return
    }
    ImagePreview.sizes.remember(imageSize, for: attachment.url)
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
final class ImagePreviewView: NSView, NSDraggingSource {
  let url: URL
  /// Where it loads from by itself, which a redirect has to be to as well.
  let sources: ImagePreview.Sources
  /// Called once the image starts to come in.
  var onStart: (() -> Void)?
  /// Called with the image's size in pixels once it loads.
  var onLoad: ((CGSize) -> Void)?
  /// Called if the image can't be had, with why.
  var onFail: ((ImagePreview.Failure) -> Void)?
  /// Whether the gray box shows where the image will be, until it's here.
  var showsPlaceholder = false {
    didSet {
      self.updatePlaceholder()
    }
  }

  private let imageView = NSImageView()
  private var started = false
  /// The picture as it came, while it's covered, blurred, since it might be sensitive, and what was
  /// found in it.
  private var covered: (image: NSImage, finding: SensitiveContent.Finding)?
  /// What's over the picture while it's covered: that it might be sensitive, and Show.
  private var coverLabel: NSView?

  init(url: URL, sources: ImagePreview.Sources) {
    self.url = url
    self.sources = sources
    super.init(frame: .zero)

    self.wantsLayer = true
    self.layer?.cornerRadius = 6
    self.layer?.masksToBounds = true
    self.toolTip = self.linkToolTip
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
    // What says it might be sensitive covers the picture, wherever it is.
    defer {
      self.coverLabel?.frame = self.imageView.frame
    }
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
    // Until the picture's here, and checked, if it's to be.
    let showsPlaceholder = self.showsPlaceholder && (self.imageView.image == nil || self.imageView.isHidden)
    self.effectiveAppearance.performAsCurrentDrawingAppearance {
      self.layer?.backgroundColor = showsPlaceholder ? NSColor.quaternarySystemFill.cgColor : nil
    }
  }

  private func load() {
    guard !self.started else {
      return
    }
    self.started = true
    guard !ImagePreview.failures.contains(self.url) else {
      self.onFail?(.notNow)
      return
    }

    // From the cache if it's been shown before, which fades in only after a download.
    var options: KingfisherOptionsInfo = [
      .targetCache(ImagePreview.cache),
      .downloader(ImagePreview.downloader),
      .backgroundDecode,
      .transition(.fade(0.2)),
    ]
    // Big images are decoded at preview size, with pixels enough for a Retina screen whatever
    // screen it's on, so it's cached the same way everywhere. Not GIFs, which would lose their
    // animation.
    if self.url.pathExtension.lowercased() != "gif" {
      options.append(.processor(DownsamplingImageProcessor(size: ImagePreview.maximumSize)))
      options.append(.scaleFactor(2))
    }
    // A picture among the server's files, through the connection to it, or one from the web, only
    // redirected on to somewhere it could load from by itself, so a link from a host it trusts
    // can't send it somewhere else that would see you.
    let source: Source
    if let path = self.sources.serverFile(at: self.url), let connection = self.sources.connection {
      source = .provider(ServerPicture(url: self.url, path: path, connection: connection) { [weak self] in
        self?.onStart?()
      })
    }
    else {
      source = .network(self.url)
      let sources = self.sources
      options.append(.redirectHandler(AnyRedirectHandler { _, _, request, completion in
        completion(request.url.map(sources.trusts) == true ? request : nil)
      }))
    }

    // Checked before it's seen, while the Mac asks for that, unless it's been shown already.
    let key = self.url.absoluteString
    let checks = SensitiveContent.isOn && !SensitiveContent.shown.contains(key)
    self.imageView.isHidden = checks

    var reportedStart = false
    var tooBig = false
    self.imageView.kf.setImage(with: source, options: options, progressBlock: { [weak self] received, _ in
      // Stopped once more has come than a preview's worth, which one that didn't say how big it is
      // could be, without end.
      if received > ImagePreview.sizeLimit, !tooBig {
        tooBig = true
        self?.imageView.kf.cancelDownloadTask()
        return
      }
      guard !reportedStart else {
        return
      }
      reportedStart = true
      self?.onStart?()
    }) { [weak self] result in
      guard let self else {
        return
      }
      if tooBig {
        self.onFail?(.refused)
        return
      }
      switch result {
      case .success(let value):
        if checks {
          self.check(value, key: key)
        }
        self.updatePlaceholder()
        self.needsLayout = true
        self.onLoad?(Self.pixelSize(of: value.image))
      case .failure(let error):
        // Not when it was only stopped, as when the view went away.
        if !error.isNotCurrentTask, let failure = Self.failure(of: error) {
          self.onFail?(failure)
        }
      }
    }
  }

  /// Why the image couldn't be had. Refused, when the server said no: turned the request away, or
  /// sent something that isn't an image, or one too big, or one that can't be read. Unreachable,
  /// when it couldn't be reached, or was busy or in trouble for the moment, which can pass. For a
  /// picture among a server's files, not now, but for one too big. Nothing when it was only
  /// stopped, as when the view went away.
  private static func failure(of error: KingfisherError) -> ImagePreview.Failure? {
    switch error {
    case .requestError(reason: .taskCancelled), .requestError(reason: .asyncTaskContextCancelled),
         .requestError(reason: .dataProviderCancelled):
      return nil
    case .responseError(reason: .invalidHTTPStatusCode(let response)):
      return (400..<500).contains(response.statusCode) && response.statusCode != 408 && response.statusCode != 429 ? .refused : .unreachable
    case .responseError(reason: .cancelledByDelegate), .processorError:
      return .refused
    case .imageSettingError(reason: .dataProviderError(provider: _, error: let error)):
      if error is CancellationError {
        return nil
      }
      return (error as? ServerPictureError)?.isFinal == true ? .refused : .notNow
    default:
      return .unreachable
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

  // MARK: Sensitive

  /// Where clicking it goes, for its tooltip.
  private var linkToolTip: String {
    self.url.host(percentEncoded: false).map { "View image from \($0)" } ?? "View Image"
  }

  /// Checks the picture before it's seen, then shows it, covered if it might be sensitive.
  private func check(_ value: RetrieveImageResult, key: String) {
    let image = value.image
    // An animation's frames from along it, as it came, since its first can be harmless, or the
    // picture as it's previewed.
    let animation = (image.kf.imageFrameCount ?? 1) > 1 ? value.data : nil
    let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    Task { [weak self] in
      let cover = await SensitiveContent.cover(for: picture, animation: animation, key: key)
      // Unless it's gone. It only ever loads once.
      guard let self else {
        return
      }
      if let cover {
        self.cover(image, with: cover)
      }
      self.imageView.isHidden = false
      self.updatePlaceholder()
    }
  }

  /// Blurs the picture, which might be sensitive, and says so, until it's asked for.
  private func cover(_ image: NSImage, with cover: SensitiveContent.Cover) {
    self.covered = (image, cover.finding)
    self.imageView.animates = false
    // At the picture's size, which the preview's laid out by.
    self.imageView.image = NSImage(cgImage: cover.image, size: image.size)
    let label = NSHostingView(rootView: SensitiveContentLabel(style: .preview))
    label.frame = self.imageView.frame
    self.addSubview(label)
    self.coverLabel = label
    self.toolTip = "This may be sensitive. Click to show it."
    self.setAccessibilityLabel("Image preview that may be sensitive")
  }

  /// Shows the picture, once it's asked for: straight away, or for a child, once they're sure.
  private func showCovered() {
    guard let covered = self.covered else {
      return
    }
    Task {
      guard await SensitiveContent.confirmShowing(covered.finding, in: self.window) else {
        return
      }
      SensitiveContent.shown.insert(self.url.absoluteString)
      self.uncover()
    }
  }

  private func uncover() {
    guard let covered = self.covered else {
      return
    }
    self.covered = nil
    self.coverLabel?.removeFromSuperview()
    self.coverLabel = nil
    self.imageView.image = covered.image
    self.imageView.animates = true
    self.toolTip = self.linkToolTip
    self.setAccessibilityLabel("Image preview")
  }

  /// Covers the picture again, once it's been shown, for one that might be sensitive.
  private func hideShown() {
    let key = self.url.absoluteString
    guard self.covered == nil, let image = self.imageView.image else {
      return
    }
    SensitiveContent.shown.remove(key)
    let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    Task { [weak self] in
      // Known already, so it isn't checked again.
      guard let cover = await SensitiveContent.cover(for: picture, animation: nil, key: key),
            let self, self.covered == nil, self.imageView.image === image else {
        return
      }
      self.cover(image, with: cover)
    }
  }

  /// Whether it's a picture shown since it was found to be sensitive, which can be covered again.
  private var isShownSensitive: Bool {
    let key = self.url.absoluteString
    return self.covered == nil && SensitiveContent.isOn && SensitiveContent.shown.contains(key) && SensitiveContent.finding(for: key)?.isSensitive == true
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
    // Covered, as it might be sensitive, it's shown here, rather than opened.
    if self.covered != nil {
      self.showCovered()
      return
    }
    let textView = self.textView
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

  /// The text view it's in.
  private var textView: LinkActions? {
    var view = self.superview
    while let current = view, !(current is LinkActions) {
      view = current.superview
    }
    return view as? LinkActions
  }

  // MARK: Menu

  override func menu(for event: NSEvent) -> NSMenu? {
    let menu = self.linkMenu() ?? NSMenu()
    // Covered, Show comes first, and once it's shown, there's a way to cover it again.
    if self.covered != nil {
      if !menu.items.isEmpty {
        menu.insertItem(.separator(), at: 0)
      }
      menu.insertItem(ChatMenuItem("Show Picture", systemImage: "eye") { [weak self] in
        self?.showCovered()
      }, at: 0)
    }
    else if self.isShownSensitive {
      if !menu.items.isEmpty {
        menu.addItem(.separator())
      }
      menu.addItem(ChatMenuItem("Hide Picture", systemImage: "eye.slash") { [weak self] in
        self?.hideShown()
      })
    }
    return menu.items.isEmpty ? nil : menu
  }

  /// What can be done with its link: a picture among the server's files has its file's menu, as its
  /// link does, and any other picture a link's.
  private func linkMenu() -> NSMenu? {
    if self.sources.serverFile(at: self.url) != nil, let menu = self.textView?.fileLinkMenu?(self.url) {
      return menu
    }
    guard let items = self.textView?.linkMenuItems(for: self.url) else {
      return nil
    }
    let menu = NSMenu()
    for item in items {
      menu.addItem(item)
    }
    return menu
  }

  // MARK: Dragging

  // Dragged a little way, it takes the image along, which arrives whole where it's dropped. Not
  // while it's covered.
  override func mouseDragged(with event: NSEvent) {
    guard !self.dragged, self.covered == nil, !self.imageView.isHidden, let down = self.mouseDownEvent, let image = self.imageView.image else {
      return
    }
    let start = down.locationInWindow
    let now = event.locationInWindow
    guard hypot(now.x - start.x, now.y - start.y) > 3 else {
      return
    }
    self.dragged = true
    let item = NSDraggingItem(pasteboardWriter: ImageFilePromise(url: self.url, sources: self.sources))
    item.setDraggingFrame(self.imageView.frame, contents: image)
    self.beginDraggingSession(with: [item], event: down, source: self)
  }

  func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
    .copy
  }
}

// MARK: - Dragging Out

/// A preview dragged out: the image as a file, downloaded whole once it's dropped, and its
/// link, for anywhere a link goes rather than a file. One among a server's files downloads as one
/// dragged out of Files does, with its progress in the transfers list.
final class ImageFilePromise: NSFilePromiseProvider, NSFilePromiseProviderDelegate {
  let url: URL
  /// For a picture among a server's files, where it is there, and the connection it downloads
  /// through.
  private let serverFile: (path: [String], connection: UUID)?

  private static let queue: OperationQueue = {
    let queue = OperationQueue()
    queue.qualityOfService = .userInitiated
    return queue
  }()

  init(url: URL, sources: ImagePreview.Sources = ImagePreview.Sources()) {
    self.url = url
    if let path = sources.serverFile(at: url), let connection = sources.connection {
      self.serverFile = (path, connection)
    }
    else {
      self.serverFile = nil
    }
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

  /// Its address's last part, decoded once, as it already is, as one name, so it lands where it's
  /// dropped whatever the link says.
  func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
    let name = self.url.lastPathComponent
    return (name.isEmpty || name == "/" ? "Image" : name).safeFileName
  }

  /// A server's picture on the main queue, where its connection is.
  func operationQueue(for filePromiseProvider: NSFilePromiseProvider) -> OperationQueue {
    self.serverFile == nil ? Self.queue : .main
  }

  func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void) {
    if let serverFile = self.serverFile {
      MainActor.assumeIsolated {
        Self.download(serverFile.path, through: serverFile.connection, to: url, completion: completionHandler)
      }
      return
    }
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

  /// A picture among a server's files, downloaded to where it's dropped as one dragged out of
  /// Files is.
  @MainActor
  private static func download(_ path: [String], through connection: UUID, to url: URL, completion: @escaping ((any Error)?) -> Void) {
    guard let model = AppState.shared.hotline(id: connection), let name = path.last else {
      completion(CocoaError(.fileWriteUnknown))
      return
    }
    // Where it's dropped can be somewhere it's let in only for this.
    let accessing = url.startAccessingSecurityScopedResource()
    model.enqueueDownload(FileInfo(linkedName: name, path: path, isFolder: false), to: url) { error in
      if accessing {
        url.stopAccessingSecurityScopedResource()
      }
      // Stopped from the transfers list, or the Finder, which isn't an error to show.
      completion(error is CancellationError ? CocoaError(.userCancelled) : error)
    }
  }
}

// MARK: - Sensitive Content

/// Pictures and videos that might be sensitive, as Apple's Sensitive Content Analysis finds them on
/// this Mac: in previews, server banners and preview windows, which show them blurred until they're
/// asked for. Only while the Mac has it on: Sensitive Content Warning, which someone turns on for
/// themselves, or Communication Safety, which is for children. Otherwise nothing's checked. Nothing
/// about what's found leaves the Mac, as Apple asks.
enum SensitiveContent {
  /// How the Mac has sensitive content shown.
  enum Intervention {
    /// It doesn't: nothing's checked.
    case none
    /// Briefly, for someone who asked to be warned: blurred, with Show.
    case brief
    /// For a child, with Communication Safety: blurred, and asked about twice before it's shown.
    case descriptive
  }

  /// What a check found.
  enum Finding: Sendable {
    case nothing
    /// Nudity, or before macOS 27, which can't tell, anything sensitive.
    case nudity
    /// Violence or gore, and no nudity, which macOS 27 tells apart.
    case violence

    var isSensitive: Bool {
      self != .nothing
    }
  }

  /// Something that might be sensitive, blurred too much to make out, and what was found in it.
  struct Cover: Sendable {
    let image: CGImage
    let finding: Finding
  }

  /// How the Mac has sensitive content shown.
  static var intervention: Intervention {
    switch self.policy {
    case .simpleInterventions: .brief
    case .descriptiveInterventions: .descriptive
    default: .none
    }
  }

  /// Whether anything's checked.
  static var isOn: Bool {
    self.intervention != .none
  }

  /// How the Mac has it now, read again, for Settings, which shows it.
  static func currentIntervention() -> Intervention {
    self.cachedPolicy.withLock { $0 = nil }
    return self.intervention
  }

  /// Sensitive Content Warning, in System Settings' Privacy & Security, which is where it's turned on.
  static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_NudityDetection")!

  private static let analyzer = SCSensitivityAnalyzer()

  /// The Mac's setting, as of when the app last came to the front, since it's changed elsewhere: in
  /// System Settings, or Screen Time.
  private static let cachedPolicy = OSAllocatedUnfairLock<SCSensitivityAnalysisPolicy?>(initialState: nil)
  nonisolated(unsafe) private static let policyRefresher = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: nil) { _ in
    SensitiveContent.cachedPolicy.withLock { $0 = nil }
  }

  private static var policy: SCSensitivityAnalysisPolicy {
    _ = self.policyRefresher
    if let policy = self.cachedPolicy.withLock({ $0 }) {
      return policy
    }
    let policy = self.analyzer.analysisPolicy
    self.cachedPolicy.withLock { $0 = policy }
    return policy
  }

  /// What's been found of each picture or video checked, by its key, for as long as the app's open,
  /// so one shown again isn't checked again.
  private static let found = OSAllocatedUnfairLock<[String: Finding]>(initialState: [:])

  /// What was found of something, once it's been checked.
  static func finding(for key: String) -> Finding? {
    self.found.withLock { $0[key] }
  }

  /// What's been shown since it was found to be sensitive, by key, for as long as the app's open, so
  /// it isn't covered again each time it's seen.
  @MainActor static let shown = Shown()

  @MainActor
  @Observable
  final class Shown {
    private(set) var keys: Set<String> = []

    func contains(_ key: String) -> Bool {
      self.keys.contains(key)
    }

    func insert(_ key: String) {
      self.keys.insert(key)
    }

    func remove(_ key: String) {
      self.keys.remove(key)
    }
  }

  /// A key for a file, which changes when the file does, as a server's banner can. From the file as
  /// it is, rather than its URL's resource values, which the URL keeps from when they were first read.
  static func key(forFileAt url: URL) -> String {
    let path = url.path(percentEncoded: false)
    let attributes = try? FileManager.default.attributesOfItem(atPath: path)
    let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    return "\(path) \(size) \(modified)"
  }

  // MARK: Covers

  /// A picture's cover, if it might be sensitive: checked as it's previewed, or an animation by its
  /// frames from along it, as it came, since its first can be harmless. Nil when it isn't, or
  /// nothing's checked.
  @concurrent
  static func cover(for picture: CGImage?, animation: (@Sendable () -> Data?)?, key: String) async -> Cover? {
    guard self.isOn, let picture else {
      return nil
    }
    var finding = self.finding(for: key)
    if finding == nil {
      var frames = animation?().map { self.frames(of: $0) } ?? []
      if frames.isEmpty {
        frames = [picture]
      }
      finding = await self.check(frames, key: key)
    }
    // Dark gray, should it not blur, rather than shown as it is.
    guard let finding, finding.isSensitive, let image = self.blurred(picture) ?? self.blank() else {
      return nil
    }
    return Cover(image: image, finding: finding)
  }

  /// A picture file's cover, if it might be sensitive, checked by its frames, for an animation from
  /// along it.
  @concurrent
  static func cover(forImageAt url: URL, key: String) async -> Cover? {
    guard self.isOn else {
      return nil
    }
    let frames = self.frames(at: url)
    let finding = await self.check(frames, key: key)
    guard finding.isSensitive, let image = frames.first.flatMap({ self.blurred($0) }) ?? self.blank() else {
      return nil
    }
    return Cover(image: image, finding: finding)
  }

  /// A video's cover, if it might be sensitive, from a frame a moment into it. All of it's checked,
  /// which can take a moment.
  @concurrent
  static func cover(forVideoAt url: URL, key: String) async -> Cover? {
    guard self.isOn else {
      return nil
    }
    let finding = await self.check(videoAt: url, key: key)
    guard finding.isSensitive else {
      return nil
    }
    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: 256, height: 256)
    let frame = try? await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
    // Dark gray, without a frame.
    guard let image = frame.flatMap({ self.blurred($0) }) ?? self.blank() else {
      return nil
    }
    return Cover(image: image, finding: finding)
  }

  // MARK: Checking

  /// What's in a picture, by its frames, checked once: nothing, when nothing's checked, or none of
  /// them can be, which is tried again next time.
  @concurrent
  private static func check(_ frames: [CGImage], key: String) async -> Finding {
    guard self.isOn, !frames.isEmpty else {
      return .nothing
    }
    if let known = self.finding(for: key) {
      return known
    }
    var finding = Finding.nothing
    var checked = false
    for frame in frames {
      guard let analysis = try? await self.analyzer.analyzeImage(frame) else {
        continue
      }
      checked = true
      if analysis.isSensitive {
        finding = self.finding(of: analysis)
        break
      }
    }
    if checked {
      self.remember(finding, for: key)
    }
    return finding
  }

  private static func remember(_ finding: Finding, for key: String) {
    self.found.withLock { $0[key] = finding }
  }

  /// What's in a video, all through, checked once.
  @concurrent
  private static func check(videoAt url: URL, key: String) async -> Finding {
    if let known = self.finding(for: key) {
      return known
    }
    guard let analysis = try? await self.analyzer.videoAnalysis(forFileAt: url).hasSensitiveContent() else {
      return .nothing
    }
    let finding = analysis.isSensitive ? self.finding(of: analysis) : .nothing
    self.remember(finding, for: key)
    return finding
  }

  private static func finding(of analysis: SCSensitivityAnalysis) -> Finding {
    if #available(macOS 27, *), !analysis.detectedTypes.isEmpty, !analysis.detectedTypes.contains(.sexuallyExplicit) {
      return .violence
    }
    return .nudity
  }

  /// A picture's frames, small, as a check needs no more: an animation's from along it, and any
  /// other picture's one.
  private static func frames(of source: CGImageSource) -> [CGImage] {
    let count = CGImageSourceGetCount(source)
    guard count > 0 else {
      return []
    }
    let checked = min(count, 4)
    let options = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 512,
    ] as CFDictionary
    return (0..<checked).compactMap { CGImageSourceCreateThumbnailAtIndex(source, $0 * count / checked, options) }
  }

  static func frames(of data: Data) -> [CGImage] {
    CGImageSourceCreateWithData(data as CFData, nil).map { self.frames(of: $0) } ?? []
  }

  private static func frames(at url: URL) -> [CGImage] {
    CGImageSourceCreateWithURL(url as CFURL, nil).map { self.frames(of: $0) } ?? []
  }

  // MARK: Blurring

  private static let context = CIContext(options: [.cacheIntermediates: false])

  /// A picture blurred too much to make out: made small, then blurred, which looks smooth at any
  /// size, with nothing sharp left in it.
  static func blurred(_ image: CGImage) -> CGImage? {
    let input = CIImage(cgImage: image)
    let longest = max(input.extent.width, input.extent.height)
    guard longest > 0 else {
      return nil
    }
    // Averaged down, so even its edges are, rather than sampled, which keeps whatever's along them.
    let small = input.applyingFilter("CILanczosScaleTransform", parameters: [
      kCIInputScaleKey: min(1, 64 / longest),
      kCIInputAspectRatioKey: 1,
    ])
    let extent = small.extent.integral
    let blurred = small.clampedToExtent()
      .applyingGaussianBlur(sigma: max(extent.width, extent.height) / 12)
      // Back up to four times that, smoothly, so it isn't blotchy shown big, as in a window.
      .applyingFilter("CILanczosScaleTransform", parameters: [
        kCIInputScaleKey: 4,
        kCIInputAspectRatioKey: 1,
      ])
      .cropped(to: CGRect(x: extent.minX * 4, y: extent.minY * 4, width: extent.width * 4, height: extent.height * 4))
    return self.context.createCGImage(blurred, from: blurred.extent)
  }

  /// Dark gray, for a video no frame could be had of.
  private static func blank() -> CGImage? {
    let context = CGContext(data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    context?.setFillColor(CGColor(gray: 0.2, alpha: 1))
    context?.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    return context?.makeImage()
  }

  // MARK: Showing

  /// Whether to show something that might be sensitive, once Show's been clicked: for a child, asked
  /// twice first, in words for them, as Messages does, so it never comes as a surprise, and for
  /// anyone else, straight away.
  @MainActor
  static func confirmShowing(_ finding: Finding, isVideo: Bool = false, in window: NSWindow?) async -> Bool {
    guard self.intervention == .descriptive else {
      return true
    }
    let kind = isVideo ? "video" : "picture"
    let ask = NSAlert()
    if finding == .violence {
      ask.messageText = "This \(kind) could be upsetting. Are you sure you want to see it?"
      ask.informativeText = "It might show violence, or someone getting hurt. You don't have to look."
    }
    else {
      ask.messageText = "This \(kind) could be sensitive. Are you sure you want to see it?"
      ask.informativeText = "Sensitive pictures and videos show the private parts of the body that a swimsuit covers. It's not your fault it's here, and you don't have to look."
    }
    ask.addButton(withTitle: "Not Now")
    ask.addButton(withTitle: "I'm Sure")
    guard await ask.answer(in: window) == .alertSecondButtonReturn else {
      return false
    }
    let check = NSAlert()
    check.messageText = "It's your choice, but make sure you feel safe."
    check.informativeText = "If something you see upsets you, you can talk to a grown-up you trust."
    check.addButton(withTitle: "Don't View")
    check.addButton(withTitle: "View")
    return await check.answer(in: window) == .alertSecondButtonReturn
  }
}

private extension NSAlert {
  /// Shown as a sheet on a window, or on its own without one, and what was chosen.
  @MainActor
  func answer(in window: NSWindow?) async -> NSApplication.ModalResponse {
    guard let window, window.isVisible, window.attachedSheet == nil else {
      return self.runModal()
    }
    return await withCheckedContinuation { continuation in
      self.beginSheetModal(for: window) { response in
        continuation.resume(returning: response)
      }
    }
  }
}

/// What's over something that might be sensitive, while it's blurred: that it might be, and Show, as
/// Messages has it, brief, in a preview as small as one gets, along a banner, or in a window.
struct SensitiveContentLabel: View {
  enum Style {
    /// In a preview, whose Show is the whole preview, clicked: as much as fits.
    case preview
    /// Along a server's banner.
    case banner
    /// In a preview window.
    case window
  }

  let style: Style
  /// What Show does, as a button, along a banner or in a window.
  var show: (() -> Void)? = nil

  var body: some View {
    Group {
      switch self.style {
      case .preview:
        ViewThatFits {
          VStack(spacing: 5) {
            self.symbol(size: 15)
            self.title(size: 11)
            self.showLabel(size: 11)
          }
          VStack(spacing: 4) {
            self.symbol(size: 14)
            self.showLabel(size: 11)
          }
          self.symbol(size: 12)
        }
        .padding(4)
        .accessibilityElement(children: .combine)
      case .banner:
        HStack(spacing: 8) {
          self.symbol(size: 13)
          self.title(size: 12)
          self.showButton(size: 11)
        }
      case .window:
        VStack(spacing: 10) {
          self.symbol(size: 28)
          self.title(size: 15)
          self.showButton(size: 13)
        }
      }
    }
    .foregroundStyle(.white)
    .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    // A little darker, so it reads over any picture.
    .background {
      Color.black.opacity(0.2)
        .allowsHitTesting(false)
    }
  }

  private func symbol(size: CGFloat) -> some View {
    Image(systemName: "eye.slash")
      .font(.system(size: size, weight: .medium))
      .allowsHitTesting(false)
  }

  private func title(size: CGFloat) -> some View {
    Text("This may be sensitive")
      .font(.system(size: size, weight: .semibold))
      .lineLimit(1)
      .allowsHitTesting(false)
  }

  /// Show, in a light capsule, as Messages has it.
  private func showLabel(size: CGFloat) -> some View {
    Text("Show")
      .font(.system(size: size, weight: .semibold))
      .padding(.horizontal, size)
      .padding(.vertical, size / 4)
      .background(Color.white.opacity(0.25), in: .capsule)
  }

  @ViewBuilder
  private func showButton(size: CGFloat) -> some View {
    if let show = self.show {
      Button(action: show) {
        self.showLabel(size: size)
      }
      .buttonStyle(.plain)
    }
  }
}

/// A server's banner, checked before it's seen while the Mac has that on, and blurred, with Show, if
/// it might be sensitive. It keeps its place, unseen, for the moment it's checked.
private struct SensitiveBannerCover: ViewModifier {
  let fileURL: URL?
  let cornerRadius: CGFloat
  /// Whether a child's asked in a sheet on the window it's in, or on its own, from a panel.
  let asksInWindow: Bool

  /// The banner that's been checked, and its cover, if it might be sensitive.
  @State private var checked: URL?
  @State private var cover: SensitiveContent.Cover?
  @State private var key: String?

  func body(content: Content) -> some View {
    let isCovered = self.cover != nil && !SensitiveContent.shown.contains(self.key ?? "")
    content
      .opacity(isCovered || (SensitiveContent.isOn && self.fileURL != nil && self.checked != self.fileURL) ? 0 : 1)
      .overlay {
        if isCovered, let cover = self.cover, let key = self.key {
          Image(decorative: cover.image, scale: 1)
            .resizable()
            .overlay {
              SensitiveContentLabel(style: .banner) {
                self.show(cover, key: key)
              }
            }
            .clipShape(RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous))
        }
      }
      .task(id: self.fileURL) {
        self.cover = nil
        self.key = nil
        guard let fileURL = self.fileURL, SensitiveContent.isOn else {
          self.checked = self.fileURL
          return
        }
        let key = SensitiveContent.key(forFileAt: fileURL)
        self.cover = await SensitiveContent.cover(forImageAt: fileURL, key: key)
        self.key = key
        self.checked = fileURL
      }
  }

  private func show(_ cover: SensitiveContent.Cover, key: String) {
    Task {
      guard await SensitiveContent.confirmShowing(cover.finding, in: self.asksInWindow ? NSApp.keyWindow : nil) else {
        return
      }
      SensitiveContent.shown.insert(key)
    }
  }
}

extension View {
  /// Covers a server's banner while it might be sensitive, until it's asked for.
  func sensitiveBanner(_ fileURL: URL?, cornerRadius: CGFloat = 0, asksInWindow: Bool = true) -> some View {
    self.modifier(SensitiveBannerCover(fileURL: fileURL, cornerRadius: cornerRadius, asksInWindow: asksInWindow))
  }
}
