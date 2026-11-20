import Accessibility
import AppKit
import AVFoundation
import CoreImage
import Kingfisher
import Network
import os
#if SENSITIVE_CONTENT_ANALYSIS
import SensitiveContentAnalysis
#endif
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

  /// The kinds of pictures macOS reads, AVIF and JPEG XL among them.
  private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "avif", "jxl", "bmp", "tif", "tiff"]

  /// Bigger images don't download, whether they say how big they are first or not.
  static let sizeLimit: Int64 = 10 * 1024 * 1024

  /// Why a picture's download was stopped: more of it came than a preview's worth.
  struct TooBig: Error {}

  /// How much of a picture's start is kept to read its size from. Most say it in their first few
  /// dozen bytes, and a photo whose camera says a lot about it, a few kilobytes in.
  static let sizingLimit = 256 * 1024

  /// A picture's size in pixels, the way it's shown, from as much of its start as has come, once
  /// that's enough to tell: straight from a GIF's, PNG's or WebP's header, which says it in its first
  /// 30 bytes, or else as ImageIO reads it, as for a JPEG, turned the way it says. Nil until then,
  /// and for HEIC and AVIF, which ImageIO only reads whole.
  static func pixelSize(ofStart data: Data) -> CGSize? {
    let bytes = [UInt8](data.prefix(32))
    func says(_ text: String, at index: Int) -> Bool {
      bytes.count >= index + text.utf8.count && bytes[index..<(index + text.utf8.count)].elementsEqual(text.utf8)
    }
    func little16(_ index: Int) -> Int {
      Int(bytes[index]) | Int(bytes[index + 1]) << 8
    }
    func little24(_ index: Int) -> Int {
      little16(index) | Int(bytes[index + 2]) << 16
    }
    func big32(_ index: Int) -> Int {
      Int(bytes[index]) << 24 | Int(bytes[index + 1]) << 16 | Int(bytes[index + 2]) << 8 | Int(bytes[index + 3])
    }
    func size(_ width: Int, _ height: Int) -> CGSize? {
      width > 0 && height > 0 ? CGSize(width: width, height: height) : nil
    }
    if says("GIF8", at: 0) {
      return bytes.count >= 10 ? size(little16(6), little16(8)) : nil
    }
    if bytes.count >= 8, bytes[0..<8].elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
      return bytes.count >= 24 && says("IHDR", at: 12) ? size(big32(16), big32(20)) : nil
    }
    if says("RIFF", at: 0) {
      guard bytes.count >= 30, says("WEBP", at: 8) else {
        return nil
      }
      // Extended, as an animation is, lossy, and lossless.
      if says("VP8X", at: 12) {
        return size(little24(24) + 1, little24(27) + 1)
      }
      if says("VP8 ", at: 12), bytes[23] == 0x9D, bytes[24] == 0x01, bytes[25] == 0x2A {
        return size(little16(26) & 0x3FFF, little16(28) & 0x3FFF)
      }
      if says("VP8L", at: 12), bytes[20] == 0x2F {
        let bits = little16(21) | little16(23) << 16
        return size((bits & 0x3FFF) + 1, (bits >> 14 & 0x3FFF) + 1)
      }
      return nil
    }
    if says("ftyp", at: 4) {
      return nil
    }
    let source = CGImageSourceCreateIncremental(nil)
    CGImageSourceUpdateData(source, data as CFData, false)
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int else {
      return nil
    }
    let orientation = properties[kCGImagePropertyOrientation] as? UInt32 ?? 1
    return orientation >= 5 ? size(height, width) : size(width, height)
  }

  /// Bigger pictures among a server's files aren't previewed: one linked to downloads to everyone
  /// there at once, from a server that could be on a home connection.
  static let serverSizeLimit = 5 * 1024 * 1024

  /// Whether a link looks like an image worth previewing: by its extension, or one GitHub gives a
  /// picture put up there. Only https, since the app doesn't allow insecure loads anyway.
  static func canPreview(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https"
      && (self.imageExtensions.contains(url.pathExtension.lowercased()) || self.isGitHubAttachment(url))
  }

  /// Whether a link is the one GitHub gives a picture put up there, which lasts:
  /// github.com/user-attachments/assets/ and the picture's ID, or from before those,
  /// github.com/owner/repo/assets/, the number of whoever put it up, and its ID. Each time it's
  /// opened, it sends you on to a link to the picture that lasts five minutes. It has no extension,
  /// and can be to a video, which isn't shown, as it isn't an image.
  static func isGitHubAttachment(_ url: URL) -> Bool {
    guard url.scheme?.lowercased() == "https", url.host(percentEncoded: false)?.lowercased() == "github.com" else {
      return false
    }
    let parts = url.pathComponents.filter { $0 != "/" }
    switch parts.count {
    case 3:
      return parts[0] == "user-attachments" && parts[1] == "assets"
    case 5:
      return parts[2] == "assets" && parts[3].allSatisfy { ("0"..."9").contains($0) }
    default:
      return false
    }
  }

  /// The picture in a link to a page that only shows one, or an animation's, in a link to it in a
  /// form a preview can't play, or one it can have smaller:
  /// - Reddit's viewer's, whose links are to reddit.com/media with the picture's own link after url=.
  /// - Giphy's pages, its stickers' and its embeds', its GIFs at their own size, and its MP4 copies
  ///   of them, whose WebP copy, a third to two thirds the size of the GIF, is at i.giphy.com by its
  ///   ID. Not its GIFs at other sizes, some of which have no WebP.
  /// - Tenor's pages, which send you on to their GIF with .gif after them.
  /// - Imgur's pages for a picture, but not an album's, and its videos of GIFs, whose picture is at
  ///   i.imgur.com by its ID, as a GIF, which Imgur sends as whatever the picture is, still or not.
  static func picture(in url: URL) -> URL? {
    guard let host = url.host(percentEncoded: false)?.lowercased() else {
      return nil
    }
    if host == "reddit.com" || host.hasSuffix(".reddit.com") {
      guard url.path(percentEncoded: false) == "/media",
            let link = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "url" })?.value else {
        return nil
      }
      return URL(string: link)
    }
    let parts = url.pathComponents.filter { $0 != "/" }
    if let id = self.giphyID(host: host, parts: parts) {
      return URL(string: "https://i.giphy.com/\(id).webp")
    }
    if host == "tenor.com" || host == "www.tenor.com" {
      return self.tenorGIF(url, parts: parts)
    }
    if let id = self.imgurID(host: host, parts: parts) {
      return URL(string: "https://i.imgur.com/\(id).gif")
    }
    return nil
  }

  /// The ID of the animation a Giphy link's for, when it isn't to its WebP at its own size: its
  /// page, giphy.com/gifs/ and its name with the ID after it, or the ID alone, a sticker's page, the
  /// same, its embed, and its GIF or MP4, at i.giphy.com, or its GIF at its own size, giphy.gif, or
  /// an MP4 or WebP of any, at media.giphy.com/media/ and the ID, after v1. and more, sometimes.
  private static func giphyID(host: String, parts: [String]) -> String? {
    let id: Substring?
    switch host {
    case "giphy.com", "www.giphy.com":
      guard parts.count == 2 else {
        return nil
      }
      switch parts[0] {
      case "gifs", "stickers":
        id = parts[1].split(separator: "-").last
      case "embed":
        id = Substring(parts[1])
      default:
        return nil
      }
    case "i.giphy.com":
      guard parts.count == 1, ["gif", "mp4"].contains((parts[0] as NSString).pathExtension.lowercased()) else {
        return nil
      }
      id = Substring((parts[0] as NSString).deletingPathExtension)
    case _ where host.hasSuffix(".giphy.com") && self.trustedHosts.contains(host):
      guard parts.count >= 3, parts[0] == "media", let file = parts.last?.lowercased(),
            file == "giphy.gif" || ["mp4", "webp"].contains((file as NSString).pathExtension) else {
        return nil
      }
      id = Substring(parts[parts.count - 2])
    default:
      return nil
    }
    guard let id, (5...40).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else {
      return nil
    }
    return String(id)
  }

  /// The GIF of a Giphy animation previewed as its WebP, at i.giphy.com: what's opened, or dragged
  /// out, as that's what's expected of a file of one, what's had should its WebP not be, and what
  /// it was previewed as before WebP was.
  static func giphyGIF(for url: URL) -> URL? {
    guard url.host(percentEncoded: false)?.lowercased() == "i.giphy.com", url.pathExtension.lowercased() == "webp" else {
      return nil
    }
    return url.deletingPathExtension().appendingPathExtension("gif")
  }

  /// A Tenor page's GIF: the page's link, tenor.com/view/ and its name with its number after it, or
  /// with a language before view, with .gif after it, which Tenor sends on to the GIF.
  private static func tenorGIF(_ url: URL, parts: [String]) -> URL? {
    guard let view = parts.firstIndex(of: "view"), view <= 1, parts.count == view + 2,
          let number = parts[view + 1].split(separator: "-").last, number.allSatisfy({ $0.isASCII && $0.isNumber }) else {
      return nil
    }
    var path = url.path(percentEncoded: true)
    while path.hasSuffix("/") {
      path.removeLast()
    }
    return URL(string: "https://tenor.com" + path + ".gif")
  }

  /// The ID of the picture an Imgur link's for, when it isn't to a picture: its page, imgur.com/ and
  /// the ID, but not an album's or a gallery's, and its videos of GIFs, .gifv and .mp4.
  private static func imgurID(host: String, parts: [String]) -> String? {
    switch host {
    case "imgur.com", "www.imgur.com", "m.imgur.com":
      guard parts.count == 1, self.isImgurID(parts[0]) else {
        return nil
      }
      return parts[0]
    case "i.imgur.com":
      guard parts.count == 1 else {
        return nil
      }
      let file = parts[0] as NSString
      guard ["gifv", "mp4"].contains(file.pathExtension.lowercased()), self.isImgurID(file.deletingPathExtension) else {
        return nil
      }
      return file.deletingPathExtension
    default:
      return nil
    }
  }

  /// Whether a word could be Imgur's ID for a picture: five to eight letters and digits, with a
  /// digit or a capital among them, which words for Imgur's own pages, like upload, don't have.
  private static func isImgurID(_ word: String) -> Bool {
    (5...8).contains(word.count)
      && word.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
      && word.contains { $0.isNumber || $0.isUppercase }
  }

  /// Whether animations play by themselves, as Settings has it, unless the system's Animated Images
  /// setting has them stop, or the Mac's in Low Power Mode, or else only while the pointer's over
  /// them.
  @MainActor
  static var playsByThemselves: Bool {
    Prefs.shared.playsGIFs && AccessibilitySettings.animatedImagesEnabled && !LowPowerMode.isOn
  }

  /// How long an animation's stayed where it is on screen before it's decoded and played.
  static let animationDelay: Duration = .milliseconds(100)
  /// How long one that's moving, as you scroll, has been on screen before it's played anyway, as it
  /// is while you scroll slowly. One that flies by never is.
  static let movingAnimationDelay: Duration = .milliseconds(300)

  /// Whether a link's picture might be an animation: a GIF or a WebP, by its extension, or a short
  /// link to a GIF.
  static func mayBeAnimated(_ url: URL) -> Bool {
    ["gif", "webp"].contains(url.pathExtension.lowercased()) || self.isShortLink(url)
  }

  /// Whether a link's a short one to a GIF's page, Giphy's, gph.is, whose GIF can't be had from the
  /// link itself, but from the page it sends you on to.
  static func isShortLink(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "https" && url.host(percentEncoded: false)?.lowercased() == "gph.is" && url.pathComponents.count > 1
  }

  /// Where a link to a picture goes: for a short link, the picture of the page it sends you on to,
  /// asked for without going there, or the link as it is.
  static func resolved(_ url: URL) async -> URL {
    guard self.isShortLink(url) else {
      return url
    }
    var request = URLRequest(url: url, timeoutInterval: 10)
    request.httpMethod = "HEAD"
    let session = URLSession(configuration: .ephemeral, delegate: StayingPut(), delegateQueue: nil)
    defer {
      session.finishTasksAndInvalidate()
    }
    guard let (_, response) = try? await session.data(for: request),
          let location = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Location"),
          let page = URL(string: location, relativeTo: url)?.absoluteURL,
          let picture = self.picture(in: page) else {
      return url
    }
    return picture
  }

  /// Doesn't go where a response sends it, so where it would is in the response.
  private final class StayingPut: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
      nil
    }
  }

  /// Whether a picture's gone, by what its host sends you on to in its place: Imgur's picture that
  /// says so, which isn't shown, as a picture that isn't there.
  static func isGone(_ url: URL?) -> Bool {
    url?.host(percentEncoded: false)?.lowercased() == "i.imgur.com" && url?.path(percentEncoded: false) == "/removed.png"
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
      guard url.scheme?.lowercased() == "https", let host = url.host(percentEncoded: false).map(ImagePreview.hostName) else {
        return false
      }
      // The server you're on, by whatever address it has, as it has yours already.
      if let server = self.server, ImagePreview.hostName(server) == host {
        return true
      }
      // Never an IP address, or a name only a network of its own knows, which reach whatever's
      // there, as a router, a printer, or something on this Mac, rather than a site.
      guard !ImagePreview.isAddressOrLocalName(host) else {
        return false
      }
      return self.anySite
        || ImagePreview.trustedHosts.contains(host)
        || ImagePreview.trustedDomains.contains { host == $0 || host.hasSuffix("." + $0) }
        || ImagePreview.thumbnailHosts.contains(host)
    }

    /// Whether a link is shown as its picture's preview, loading by itself: from where it can, to
    /// one by its extension, or written as a picture in Markdown, or to image search's copies, or
    /// to a picture put on GitHub, which have none.
    func loadsByItself(_ url: URL, isImage: Bool) -> Bool {
      guard self.trusts(url) else {
        return false
      }
      return isImage
        || ImagePreview.imageExtensions.contains(url.pathExtension.lowercased())
        || ImagePreview.thumbnailHosts.contains(url.host(percentEncoded: false)?.lowercased() ?? "")
        || ImagePreview.isGitHubAttachment(url)
        || ImagePreview.isShortLink(url)
    }

    /// The picture shown for a link, loading by itself, if there's one: the link's own, or for a
    /// link to a page that only shows a picture, the picture in it, which loads from where it is,
    /// without the page.
    func picture(for url: URL, isImage: Bool) -> URL? {
      var picture = ImagePreview.picture(in: url) ?? url
      // A Giphy animation previewed before as its GIF, as it was before its WebP was, as it's kept,
      // and its size is known, rather than its WebP downloading.
      if let gif = ImagePreview.giphyGIF(for: picture), ImagePreview.sizes.size(for: gif) != nil {
        picture = gif
      }
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

  /// A host as it's compared: in lowercase, without an IPv6 address's brackets, or the dot after a
  /// name.
  static func hostName(_ host: String) -> String {
    var name = host.lowercased()
    if name.hasPrefix("["), name.hasSuffix("]") {
      name = String(name.dropFirst().dropLast())
    }
    while name.hasSuffix(".") {
      name.removeLast()
    }
    return name
  }

  /// Whether a host's an IP address, IPv6, with its colons, or IPv4, or a number standing for one,
  /// as no site's name ends in a number, or a name only a network of its own knows: one word alone,
  /// as a router's or a printer's can be, and `localhost`, or names under it, or `local`,
  /// `internal`, `home.arpa`, `lan` or `home`, which aren't the internet's.
  static func isAddressOrLocalName(_ host: String) -> Bool {
    let name = self.hostName(host)
    guard !name.contains(":"), let last = name.split(separator: ".").last else {
      return true
    }
    if last.allSatisfy({ $0.isASCII && $0.isNumber }) || last.hasPrefix("0x") || !name.contains(".") {
      return true
    }
    return ["localhost", "local", "internal", "home.arpa", "lan", "home"].contains { name == $0 || name.hasSuffix("." + $0) }
  }

  /// Hosts of pictures where whoever put one up can't see who looked at it: image hosts, chat's and
  /// social sites', and reference sites'. Only these hosts, and not others under the same names,
  /// which could be anyone's.
  static let trustedHosts: Set<String> = [
    // Image hosts
    "i.imgur.com", "imgur.com",
    "i.giphy.com", "media.giphy.com", "media0.giphy.com", "media1.giphy.com", "media2.giphy.com", "media3.giphy.com", "media4.giphy.com",
    "media.tenor.com", "media1.tenor.com", "c.tenor.com",
    // Tenor's own, whose pages' links, with .gif after them, send you on to the GIF, and Giphy's
    // short links, which send you on to the GIF's page, and from there to the GIF
    "tenor.com",
    "gph.is",
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
    // GitHub, whose links to pictures put up there send you on to links that last five minutes,
    // on private-user-images, or when you aren't signed in, on its own storage at Amazon
    "github.com",
    "user-images.githubusercontent.com", "private-user-images.githubusercontent.com",
    "raw.githubusercontent.com", "avatars.githubusercontent.com",
    "github-production-user-asset-6210df.s3.amazonaws.com",
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
  /// so that site doesn't see you either. GitHub's are copies of pictures from other sites on its
  /// pages, as in a README, got the same way.
  static let thumbnailHosts: Set<String> = [
    "camo.githubusercontent.com",
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
  /// Tests keep theirs in another, so they never touch yours.
  static let directory = URL.cachesDirectory
    .appending(path: Bundle.main.bundleIdentifier ?? "Hotline", directoryHint: .isDirectory)
    .appending(path: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil ? "Chat Image Previews" : "Image Previews for Tests",
               directoryHint: .isDirectory)

  /// Previews that have loaded. Only the preview is kept, not the full image, since clicking a
  /// preview opens its link rather than showing the image here, but for an animation, which is kept
  /// on disk as it came, for its frames to be played from. In memory, it's its preview alone, its
  /// first frame, made from that file again once it's gone from there.
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

  /// A picture that might be an animation, as it came, from the file it's kept in, by its link's
  /// key. Off the main thread, since even the file's name takes a while, a hash of the link.
  static func animation(forKey key: String) -> Data? {
    try? Data(contentsOf: self.cache.diskStorage.cacheFileURL(forKey: key))
  }

  /// The most pixels a preview's picture has along its longer side: enough for a Retina screen,
  /// whatever screen it's on, so it's kept the same way everywhere.
  static func previewPixels(scale: CGFloat) -> CGFloat {
    max(self.maximumSize.width, self.maximumSize.height) * scale
  }

  /// The colors a window's previews are decoded in: its own, if they're RGB, or else sRGB.
  static func previewColors(_ colorSpace: CGColorSpace?) -> CGColorSpace {
    colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
  }

  /// A preview's picture, from a picture as it came, or a preview kept before: decoded with no more
  /// than `maxPixelSize` pixels along its longer side, in a window's colors, premultiplied BGRA, as
  /// an animation's frames are. So Core Animation shows it as it is, rather than keeping a copy of
  /// it in those colors as well, made on the main thread. A point for each pixel, as Kingfisher
  /// makes its own, since it reckons the memory one takes by its size.
  static func still(from data: Data, maxPixelSize: CGFloat, in colorSpace: CGColorSpace) -> NSImage? {
    let thumbnail = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
    ] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
          let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail) else {
      return nil
    }
    return self.still(drawing: frame, in: colorSpace)
  }

  /// Whether a picture has no see-through parts: none at all, or, as premultiplied BGRA, as a
  /// preview's is, none whole all over. Any other layout is taken to have some.
  static func isOpaque(_ picture: CGImage) -> Bool {
    switch picture.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
      return true
    case .premultipliedFirst where picture.bitsPerPixel == 32
      && picture.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue:
      guard let data = picture.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
        return false
      }
      for y in 0..<picture.height {
        let row = bytes + y * picture.bytesPerRow
        for x in 0..<picture.width where row[x * 4 + 3] != 255 {
          return false
        }
      }
      return true
    default:
      return false
    }
  }

  /// A preview's picture drawn again, at the size it is, in a window's colors, premultiplied BGRA.
  static func still(drawing picture: CGImage, in colorSpace: CGColorSpace) -> NSImage? {
    guard let context = CGContext(data: nil, width: picture.width, height: picture.height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
      return nil
    }
    context.draw(picture, in: CGRect(x: 0, y: 0, width: picture.width, height: picture.height))
    guard let image = context.makeImage() else {
      return nil
    }
    let representation = NSBitmapImageRep(cgImage: image)
    let still = NSImage(size: representation.size)
    still.addRepresentation(representation)
    return still
  }

  /// Makes a preview's picture, as `still(from:maxPixelSize:in:)` does, at preview size.
  struct Still: ImageProcessor {
    let identifier: String
    private let colorSpace: CGColorSpace

    /// For a picture that might be an animation: its first frame, only ever kept in memory, by a
    /// name with the window's colors in it, so a window with other colors makes its own.
    static func firstFrame(in colorSpace: CGColorSpace?) -> Still {
      let space = ImagePreview.previewColors(colorSpace)
      // A screen's colors often have no name, but a profile, which is the same for each window on
      // the screen.
      let colors = (space.name as String?) ?? "\((space.copyICCData() as Data?)?.hashValue ?? 0)"
      let size = ImagePreview.maximumSize
      return Still(identifier: "co.goodmake.hotline.ImagePreview.FirstFrame(\(size.width)x\(size.height), \(colors))", colorSpace: space)
    }

    /// For a still picture, whose preview's kept on disk, by the name Kingfisher's downsampler gave
    /// the previews it made before, so they're still found, and read in the window's colors by
    /// `StillSerializer`, rather than downloading again.
    static func preview(in colorSpace: CGColorSpace?) -> Still {
      Still(identifier: DownsamplingImageProcessor(size: ImagePreview.maximumSize).identifier, colorSpace: ImagePreview.previewColors(colorSpace))
    }

    private init(identifier: String, colorSpace: CGColorSpace) {
      self.identifier = identifier
      self.colorSpace = colorSpace
    }

    func process(item: ImageProcessItem, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
      let data: Data?
      switch item {
      case .data(let given):
        data = given
      case .image(let image):
        data = image.kf.data(format: .GIF) ?? image.kf.data(format: .unknown)
      }
      return data.flatMap { ImagePreview.still(from: $0, maxPixelSize: ImagePreview.previewPixels(scale: options.scaleFactor), in: self.colorSpace) }
    }
  }

  /// Keeps a still picture's preview on disk, with its colors, and reads one back in the window's
  /// colors, as `Still` makes it, including those kept before. As a JPEG, about a quarter the size
  /// of one at full quality, with no difference to see at a preview's size, whatever the picture
  /// came as, unless it has see-through parts, which only a PNG keeps.
  struct StillSerializer: CacheSerializer {
    private let colorSpace: CGColorSpace

    init(in colorSpace: CGColorSpace?) {
      self.colorSpace = ImagePreview.previewColors(colorSpace)
    }

    func data(with image: KFCrossPlatformImage, original: Data?) -> Data? {
      guard let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
      }
      let isJPEG = ImagePreview.isOpaque(picture)
      let data = NSMutableData()
      guard let destination = CGImageDestinationCreateWithData(data, (isJPEG ? UTType.jpeg : UTType.png).identifier as CFString, 1, nil) else {
        return nil
      }
      CGImageDestinationAddImage(destination, picture, isJPEG ? [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary : nil)
      return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    func image(with data: Data, options: KingfisherParsedOptionsInfo) -> KFCrossPlatformImage? {
      ImagePreview.still(from: data, maxPixelSize: ImagePreview.previewPixels(scale: options.scaleFactor), in: self.colorSpace)
    }

    /// What it keeps is a JPEG or a PNG, which anything can read.
    var producesDecodableImageData: Bool {
      true
    }
  }

  /// The sizes of images previewed before.
  static let sizes = ImagePreviewSizes(fileURL: directory.appending(path: "Sizes.plist", directoryHint: .notDirectory))

  /// Links whose image couldn't be had, which aren't shown or tried again for a while.
  static let failures = ImagePreviewFailures(fileURL: directory.appending(path: "Failures.plist", directoryHint: .notDirectory))

  /// How long after a preview's picture couldn't be had for now, as a server's busy with others',
  /// it's tried again, once it's on screen.
  static let retryDelay: Duration = .seconds(15)

  /// Posted on the main thread once the Mac's back on a network, after being off one, when the links
  /// that couldn't be reached are tried again.
  static let networkDidReturn = Notification.Name("ImagePreviewNetworkDidReturn")

  /// Posted on the main thread as a picture from the web that doesn't say how big it is starts to
  /// come, which Kingfisher says nothing of, with the link it was asked for as its object.
  static let pictureDidStart = Notification.Name("ImagePreviewPictureDidStart")

  /// Posted on the main thread once a picture from the web's first bytes say how big it is, before
  /// the rest of it's here, with the link it was asked for as its object, and its size in pixels,
  /// as an NSValue, as "size".
  static let pictureSizeDidArrive = Notification.Name("ImagePreviewPictureSizeDidArrive")

  private static let network: NWPathMonitor = {
    let monitor = NWPathMonitor()
    // On a network to start with, so only coming back to one, after being off, counts.
    let wasOn = OSAllocatedUnfairLock(initialState: true)
    monitor.pathUpdateHandler = { path in
      let isOn = path.status == .satisfied
      let cameBack = wasOn.withLock { wasOn in
        defer {
          wasOn = isOn
        }
        return isOn && !wasOn
      }
      guard cameBack else {
        return
      }
      ImagePreview.failures.forgetUnreachable()
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: ImagePreview.networkDidReturn, object: nil)
      }
    }
    monitor.start(queue: DispatchQueue(label: "Image Previews' Network"))
    return monitor
  }()

  /// Watches for the network coming back, from now on.
  static func watchNetwork() {
    _ = self.network
  }

  /// Where a picture's download may be sent on to: on to a page whose picture's known, as a short
  /// link's GIF's page, the picture, and only somewhere it could load from by itself, so a link from
  /// a host it trusts can't send it somewhere else that would see you.
  static func redirects(for sources: Sources) -> AnyRedirectHandler {
    AnyRedirectHandler { _, _, request, completion in
      var request = request
      if let page = request.url, let picture = ImagePreview.picture(in: page) {
        request.url = picture
      }
      completion(request.url.map(sources.trusts) == true ? request : nil)
    }
  }

  /// A picture as it is where it's from, to copy: from disk, should it be kept whole there, as an
  /// animation is, or else downloaded again, as its preview was, an image no bigger than a preview's
  /// limit, from where it could load from by itself.
  static func original(of url: URL, sources: Sources) async -> Data? {
    let key = url.absoluteString
    if let data = await Task.detached(priority: .userInitiated, operation: { ImagePreview.animation(forKey: key) }).value {
      return data
    }
    return try? await self.downloader.downloadImage(with: url, options: [.redirectHandler(self.redirects(for: sources))]).originalData
  }

  /// Puts a picture on the clipboard as it came, for an app that takes that kind of file, as a
  /// GIF's to keep it moving, and as an image any app takes, made only once one asks for it.
  @MainActor
  static func copy(_ data: Data, to pasteboard: NSPasteboard = .general) {
    let item = NSPasteboardItem()
    let type: NSPasteboard.PasteboardType? = CGImageSourceCreateWithData(data as CFData, nil)
      .flatMap { CGImageSourceGetType($0) as String? }
      .map { NSPasteboard.PasteboardType(rawValue: $0) }
    if let type {
      item.setData(data, forType: type)
    }
    if type != NSPasteboard.PasteboardType.tiff {
      let image = CopiedImage(data)
      item.setDataProvider(image, forTypes: [.tiff])
      self.copied = image
    }
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
  }

  /// The picture last copied, kept while the clipboard might ask it for its image.
  @MainActor private static var copied: CopiedImage?

  /// Downloads previews, turning away anything that isn't an image, and stopping one once it's more
  /// than a preview's worth, or still coming after a minute.
  static let downloader: ImageDownloader = {
    let downloader = ImageDownloader(name: "Chat Image Previews")
    downloader.downloadTimeout = 20
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForResource = 60
    downloader.sessionConfiguration = configuration
    downloader.sessionDelegate = ImageDownloadLimit()
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
    // A short link's picture, rather than the page it sends you on to.
    else if self.isShortLink(url) {
      Task {
        let picture = await self.resolved(url)
        openWindow(id: "preview-quicklook", value: PreviewFileInfo(webImage: self.giphyGIF(for: picture) ?? picture))
      }
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

  /// Not one that says it's too big. One that doesn't say is stopped once too much of it has come,
  /// by `ImageDownloadLimit`. Nor what a host sends in place of a picture that's gone.
  func imageDownloader(_ downloader: ImageDownloader, didReceive response: URLResponse) async -> URLSession.ResponseDisposition {
    guard response.mimeType?.lowercased().hasPrefix("image/") == true,
          response.expectedContentLength <= ImagePreview.sizeLimit,
          !ImagePreview.isGone(response.url) else {
      return .cancel
    }
    return .allow
  }
}

/// Stops a preview's download once more of it has come than a preview's worth, which one that
/// doesn't say how big it is could send without end, as Kingfisher only counts what's come of one
/// that does. And says when one like that starts to come, which Kingfisher doesn't either, and how
/// big any picture is, as soon as its first bytes say, before the rest of it's here.
final class ImageDownloadLimit: SessionDelegate, @unchecked Sendable {
  /// How much of each download has come, and the start of each whose picture's size isn't known
  /// yet, only touched on the session's queue, one call at a time.
  private var received: [Int: Int64] = [:]
  private var starts: [Int: Data] = [:]

  override func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    let id = dataTask.taskIdentifier
    let isFirst = self.received[id] == nil
    let received = self.received[id, default: 0] + Int64(data.count)
    guard received <= ImagePreview.sizeLimit else {
      // Ended as too big for whoever's waiting on it, then stopped, which Kingfisher, done with it,
      // pays no attention to.
      self.received[id] = nil
      self.starts[id] = nil
      super.urlSession(session, task: dataTask, didCompleteWithError: ImagePreview.TooBig())
      dataTask.cancel()
      return
    }
    self.received[id] = received
    let url = dataTask.originalRequest?.url
    if isFirst, (dataTask.response?.expectedContentLength ?? -1) < 0, let url {
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: ImagePreview.pictureDidStart, object: url)
      }
    }
    super.urlSession(session, dataTask: dataTask, didReceive: data)
    // Its size, as soon as its start says it, or not, should it say nothing that far in.
    guard isFirst || self.starts[id] != nil, let url else {
      return
    }
    var start = self.starts[id] ?? Data()
    start.append(data.prefix(ImagePreview.sizingLimit - start.count))
    if let size = ImagePreview.pixelSize(ofStart: start) {
      self.starts[id] = nil
      DispatchQueue.main.async {
        NotificationCenter.default.post(name: ImagePreview.pictureSizeDidArrive, object: url, userInfo: ["size": NSValue(size: size)])
      }
    }
    else {
      self.starts[id] = start.count < ImagePreview.sizingLimit ? start : nil
    }
  }

  override func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
    self.received[task.taskIdentifier] = nil
    self.starts[task.taskIdentifier] = nil
    super.urlSession(session, task: task, didCompleteWithError: error)
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

  /// Forgets the links that couldn't be reached, to be tried again, as the network's come back. Not
  /// those the server refused, which are kept as long as ever.
  func forgetUnreachable() {
    self.lock.withLock {
      self.thisTime.removeAll()
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

extension NSTextView {
  /// The words VoiceOver reads, with each preview among them as the picture it shows, called what
  /// it's called, where the text system leaves an attachment with nothing to say: the preview
  /// itself, while it's laid out, or else one standing in for it, as it's scrolled away.
  func withPreviewsForAccessibility(_ text: NSAttributedString?, in range: NSRange) -> NSAttributedString? {
    guard let text, let storage = self.textContentStorage?.textStorage else {
      return text
    }
    let searched = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
    guard searched.length > 0 else {
      return text
    }
    var shown: NSMutableAttributedString?
    storage.enumerateAttribute(.attachment, in: searched) { value, found, _ in
      let offset = found.location - range.location
      guard let attachment = value as? ImageAttachment, offset >= 0, offset + found.length <= text.length else {
        return
      }
      let words = shown ?? NSMutableAttributedString(attributedString: text)
      words.addAttribute(NSAttributedString.Key(rawValue: "AXAttachment"), value: self.accessibilityElement(for: attachment, at: found.location),
                         range: NSRange(location: offset, length: found.length))
      shown = words
    }
    return shown ?? text
  }

  private func accessibilityElement(for attachment: ImageAttachment, at index: Int) -> Any {
    if let textLayoutManager = self.textLayoutManager, let content = textLayoutManager.textContentManager,
       let location = content.location(content.documentRange.location, offsetBy: index),
       let fragment = textLayoutManager.textLayoutFragment(for: location),
       let view = fragment.textAttachmentViewProviders.first(where: { $0.textAttachment === attachment })?.view {
      return view
    }
    return NSAccessibilityElement.element(withRole: attachment.showsLink ? .link : .image, frame: .zero, label: attachment.accessibilityName, parent: self) as Any
  }
}

extension LinkActions {
  /// What can be done with a link to an image, for its preview's menu: open the image in a preview
  /// window, while there's one, or the link the way a click on it does, or copy it, as macOS's menu
  /// for a link has.
  func linkMenuItems(for url: URL, image: URL?) -> [NSMenuItem] {
    var items: [NSMenuItem] = []
    if let image, let openImage = self.openImageAction {
      items.append(ChatMenuItem("Open Image", systemImage: "photo") {
        openImage(image)
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
  /// or an address shown as its preview alone, rather than a preview under a link that's there too.
  let standsForLink: Bool
  /// The link it stands for, as it was written, which its menu opens and copies, and copying it
  /// does, and how it looks, to show in its place if its image can't be had.
  let link: URL?
  let linkText: NSAttributedString?
  /// The image's size in pixels, once it's known, from loading it now or before.
  var imageSize: CGSize?
  /// Whether the preview takes up any room: from the start for an image that's loaded before, or
  /// one that stands for its link, whose box says where it's coming from while it waits, or else
  /// once its image starts to come in, so a link to one that can't be had takes none.
  var isShown: Bool
  /// Whether it's showing the link it stands for in its place, as its image can't be had.
  var showsLink = false
  /// Where it loads from by itself, which a redirect has to be to as well.
  let sources: ImagePreview.Sources

  init(url: URL, standsForLink: Bool = false, link: URL? = nil, linkText: NSAttributedString? = nil, sources: ImagePreview.Sources = ImagePreview.Sources()) {
    self.url = url
    self.standsForLink = standsForLink
    self.link = link
    self.linkText = standsForLink ? linkText : nil
    self.sources = sources
    self.imageSize = ImagePreview.sizes.size(for: url)
    self.isShown = (self.imageSize != nil || self.linkText != nil) && !ImagePreview.failures.contains(url)
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

  /// The words written for the picture, as a Markdown image's are, rather than its link.
  var altText: String? {
    guard let words = self.linkText?.string, !words.isEmpty, !words.contains("://") else {
      return nil
    }
    return words
  }

  /// What VoiceOver calls it: by the words written for it, or where it's from, or, showing its link
  /// in its place, the link.
  var accessibilityName: String {
    if self.showsLink, let linkText = self.linkText {
      return linkText.string
    }
    return self.altText ?? (self.link ?? self.url).host(percentEncoded: false).map { "From \($0)" } ?? "Picture"
  }
}

final class ImagePreviewProvider: NSTextAttachmentViewProvider {
  override func loadView() {
    guard let attachment = self.textAttachment as? ImageAttachment else {
      return
    }
    let view = ImagePreviewView(url: attachment.url, link: attachment.link, sources: attachment.sources)
    view.showsPlaceholder = attachment.isShown
    // A link not previewed before says where its picture's coming from, in its box, as it waits.
    if attachment.imageSize == nil, let linkText = attachment.linkText {
      view.placeholderText = linkText.string
    }
    // Called by the words written for it, as a Markdown image's are, rather than its link.
    view.altText = attachment.altText
    if attachment.showsLink, let linkText = attachment.linkText {
      view.showLink(linkText)
    }
    view.onStart = { [weak self] in
      self?.show()
    }
    view.onSize = { [weak self] imageSize in
      self?.sizeDidArrive(imageSize)
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
    // The link it stands for, as a line of words, on the line, and no wider than it, with the room
    // a label has around its words.
    if let attachment = self.textAttachment as? ImageAttachment, attachment.showsLink, let linkText = attachment.linkText {
      let size = linkText.size()
      let font = linkText.length > 0 ? linkText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont : nil
      let width = min(ceil(size.width) + 6, max(1, proposedLineFragment.width - position.x))
      return CGRect(x: 0, y: font?.descender ?? -3, width: width, height: ceil(size.height))
    }
    // A point, rather than nothing, which TextKit would take to mean the attachment's usual size.
    guard let attachment = self.textAttachment as? ImageAttachment, attachment.isShown else {
      return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    let size = attachment.previewSize
    // Sit on the line a little above the baseline, with some room below.
    return CGRect(x: 0, y: -4, width: size.width, height: size.height)
  }

  /// Makes room for the preview once its image starts to come in, until it's here, in place of the
  /// link it stands for, should it be trying again after it couldn't be had.
  private func show() {
    guard let attachment = self.textAttachment as? ImageAttachment, !attachment.isShown else {
      return
    }
    attachment.isShown = true
    attachment.showsLink = false
    (self.view as? ImagePreviewView)?.hideLink()
    (self.view as? ImagePreviewView)?.showsPlaceholder = true
    self.layOutAgain()
  }

  /// Takes the picture's shape as soon as its first bytes say what that is, before the rest of it's
  /// here, so nothing moves once it is.
  private func sizeDidArrive(_ imageSize: CGSize) {
    guard let attachment = self.textAttachment as? ImageAttachment, attachment.imageSize == nil, !attachment.showsLink,
          imageSize.width > 0, imageSize.height > 0 else {
      return
    }
    let previousSize = attachment.previewSize
    let wasShown = attachment.isShown
    attachment.imageSize = imageSize
    attachment.isShown = true
    (self.view as? ImagePreviewView)?.showsPlaceholder = true
    guard attachment.previewSize != previousSize || !wasShown else {
      return
    }
    self.layOutAgain()
  }

  /// Takes the preview away, for an image that can't be had: for a while if the server refused it,
  /// until the app opens again if it couldn't be reached, or only for now. One in its link's place
  /// shows the link instead.
  private func hide(for failure: ImagePreview.Failure) {
    guard let attachment = self.textAttachment as? ImageAttachment else {
      return
    }
    if failure != .notNow {
      ImagePreview.failures.insert(attachment.url, refused: failure == .refused)
      ImagePreview.sizes.forget(attachment.url)
    }
    if let linkText = attachment.linkText, !attachment.showsLink {
      attachment.showsLink = true
      attachment.isShown = false
      (self.view as? ImagePreviewView)?.showLink(linkText)
      self.layOutAgain()
      return
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
  /// showing at the right size, lays the line out again at it, in place of its link, should that
  /// have shown as the image couldn't be had before.
  private func imageDidLoad(imageSize: CGSize) {
    guard let attachment = self.textAttachment as? ImageAttachment, imageSize.width > 0, imageSize.height > 0 else {
      return
    }
    ImagePreview.sizes.remember(imageSize, for: attachment.url)
    let previousSize = attachment.previewSize
    // Shown already, rather than its link in its place, as when it couldn't be had before.
    let wasShown = attachment.isShown && !attachment.showsLink
    attachment.imageSize = imageSize
    attachment.isShown = true
    attachment.showsLink = false
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
  /// The link it stands for, as it was written, which its menu opens and copies, when it's in the
  /// link's place.
  let link: URL?
  /// Where it loads from by itself, which a redirect has to be to as well.
  let sources: ImagePreview.Sources
  /// Called once the image starts to come in.
  var onStart: (() -> Void)?
  /// Called with the image's size in pixels, as soon as its first bytes say it, before it's here.
  var onSize: ((CGSize) -> Void)?
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
  /// What the gray box says while the image is coming the first time: the link it stands for, as a
  /// caption, in the tertiary color, as a placeholder's words are, along its bottom, shortened in
  /// the middle to fit.
  var placeholderText: String? {
    didSet {
      guard let text = self.placeholderText else {
        self.placeholderLabel?.removeFromSuperview()
        self.placeholderLabel = nil
        return
      }
      let scheme = ["https://", "http://"].first { text.lowercased().hasPrefix($0) }
      let label = self.placeholderLabel ?? NSTextField(labelWithString: "")
      label.stringValue = scheme.map { String(text.dropFirst($0.count)) } ?? text
      label.font = .preferredFont(forTextStyle: .caption1)
      label.textColor = .tertiaryLabelColor
      label.alignment = .center
      label.lineBreakMode = .byTruncatingMiddle
      label.usesSingleLineMode = true
      label.maximumNumberOfLines = 1
      label.isHidden = true
      // Said already, by the preview's own name.
      label.setAccessibilityElement(false)
      if label.superview == nil {
        self.addSubview(label)
      }
      self.placeholderLabel = label
      self.needsLayout = true
      self.updatePlaceholder()
    }
  }
  private var placeholderLabel: NSTextField?
  /// The words written for the picture, as a Markdown image's are, which VoiceOver calls it by.
  var altText: String? {
    didSet {
      self.updateAccessibility()
    }
  }

  private let imageView = NSImageView()
  private var started = false
  /// Whether the picture's hidden while it's checked, as it might be sensitive, before it's seen.
  /// Not to be played, dragged out, or shown until it's known not to be.
  private var isChecking = false
  /// The picture as it came, while it's covered, blurred, since it might be sensitive, and what was
  /// found in it.
  private var covered: (image: NSImage, finding: SensitiveContent.Finding)?
  /// What's over the picture while it's covered: that it might be sensitive, and Show.
  private var coverLabel: NSView?

  /// The link it stands for, shown in its place, as its image can't be had.
  private var linkLabel: NSTextField?

  /// An animation's frames, over the image view, which shows its first frame until they're here,
  /// played by Core Animation, rather than by the image view, which would draw each frame on the
  /// main thread.
  private let framesView = NSView()
  private let framesLayer = CALayer()
  private lazy var player = AnimationPlayer(layer: self.framesLayer, in: self)
  /// The animation, once it's opened, while it's on screen.
  private var animation: AnimationFrames?
  /// Opening the animation, once it's been on screen a moment.
  private var opening: Task<Void, Never>?

  /// Where its picture comes from, and how it's had, once it's started to load, so it can be had
  /// again from the cache once it's back on screen, as it lets it go while it's away. Its preview's
  /// made for its window's colors then, which change as the window moves to another screen.
  private var source: Source?
  private var baseOptions: KingfisherOptionsInfo = []
  /// The picture's size in pixels, once it's loaded.
  private var pictureSize: CGSize?
  /// Whether its picture might be an animation, by its link.
  private let mayBeAnimated: Bool
  /// The pixels to a point of the screen its animation was opened for.
  private var animationScale: CGFloat?

  init(url: URL, link: URL? = nil, sources: ImagePreview.Sources) {
    self.url = url
    self.link = link
    self.sources = sources
    self.mayBeAnimated = ImagePreview.mayBeAnimated(url)
    super.init(frame: .zero)

    self.wantsLayer = true
    self.layer?.cornerRadius = 6
    self.layer?.masksToBounds = true
    self.toolTip = self.linkToolTip
    // One picture to VoiceOver, named for what it's of, which a press opens, as a click does.
    self.setAccessibilityElement(true)
    self.updateAccessibility()

    self.imageView.setAccessibilityElement(false)
    self.framesView.setAccessibilityElement(false)
    self.imageView.imageScaling = .scaleProportionallyUpOrDown
    self.imageView.animates = false
    self.imageView.wantsLayer = true
    self.imageView.layer?.cornerRadius = 6
    self.imageView.layer?.masksToBounds = true
    self.imageView.frame = self.bounds
    self.addSubview(self.imageView)

    self.framesView.wantsLayer = true
    self.framesView.layer?.cornerRadius = 6
    self.framesView.layer?.masksToBounds = true
    self.framesLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
    self.framesLayer.contentsGravity = .resize
    self.framesView.layer?.addSublayer(self.framesLayer)
    self.framesView.isHidden = true
    self.addSubview(self.framesView)

    self.progress.style = .spinning
    self.progress.controlSize = .small
    self.progress.isDisplayedWhenStopped = false
    self.progress.isIndeterminate = true
    self.progress.isHidden = true
    self.progress.setAccessibilityLabel("Loading image")
    self.progress.sizeToFit()
    self.addSubview(self.progress)

    // Played while the pointer's over it, when animations don't play by themselves, and started or
    // stopped as Settings, the system's Animated Images setting, or Low Power Mode, changes.
    self.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil))
    NotificationCenter.default.addObserver(self, selector: #selector(self.playingDidChange), name: Prefs.playsGIFsDidChange, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(self.playingDidChange), name: AccessibilitySettings.animatedImagesEnabledDidChangeNotification, object: nil)
    LowPowerMode.watch()
    NotificationCenter.default.addObserver(self, selector: #selector(self.playingDidChange), name: LowPowerMode.didChange, object: nil)
    // Tried again, should it not have been had, once the network's back.
    ImagePreview.watchNetwork()
    NotificationCenter.default.addObserver(self, selector: #selector(self.networkDidReturn), name: ImagePreview.networkDidReturn, object: nil)
    // Made room for once it starts to come, should it not say how big it is, and given its shape as
    // soon as its first bytes say what that is.
    NotificationCenter.default.addObserver(self, selector: #selector(self.pictureDidStart(_:)), name: ImagePreview.pictureDidStart, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(self.pictureSizeDidArrive(_:)), name: ImagePreview.pictureSizeDidArrive, object: nil)
  }

  /// Whether the pointer's over it, which plays an animation that doesn't play by itself.
  private var isPointedAt = false

  override func mouseEntered(with event: NSEvent) {
    self.isPointedAt = true
    if !ImagePreview.playsByThemselves {
      self.animate(waiting: false)
    }
  }

  override func mouseExited(with event: NSEvent) {
    self.isPointedAt = false
    if !ImagePreview.playsByThemselves {
      self.stopAnimating()
    }
  }

  @objc private func playingDidChange() {
    if ImagePreview.playsByThemselves || self.isPointedAt {
      self.animate(waiting: false)
    }
    else {
      self.stopAnimating()
    }
  }

  // A preview of an image we haven't seen before takes the image's size once it loads, but until
  // its size catches up, keep the image from stretching: fit it from the top left.
  override func layout() {
    super.layout()
    // What says it might be sensitive covers the picture, wherever it is, and an animation's frames
    // are where its first is. Its progress, should it be slow to come, is in the middle.
    defer {
      self.coverLabel?.frame = self.imageView.frame
      self.framesView.frame = self.imageView.frame
      self.framesLayer.frame = self.framesView.bounds
      let side = self.progress.frame.size
      self.progress.setFrameOrigin(NSPoint(x: (self.bounds.midX - side.width / 2).rounded(), y: (self.bounds.midY - side.height / 2).rounded()))
      if let label = self.placeholderLabel {
        let height = ceil(label.fittingSize.height)
        label.frame = NSRect(x: 8, y: self.bounds.height - height - 6, width: max(0, self.bounds.width - 16), height: height)
      }
      self.updatePlaceholder()
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
      // Showing it's still coming, should it have become slow to while it was away.
      self.updatePlaceholder()
    }
    else {
      // Gone, as it scrolls away, and the pointer with it.
      self.isPointedAt = false
      self.letGo()
    }
    // Played again in another window, as leaving one takes its animation away.
    self.player.windowDidChange()
  }

  /// Lets go of its picture and an animation's frames as it leaves the window, so a preview that's
  /// scrolled away holds nothing. Once it's back, its picture's had again from the cache, straight
  /// away from memory, or a moment later from disk, and an animation's frames are decoded again once
  /// it's been back a moment. Not while it's covered, as it might be sensitive, or still loading the
  /// first time, which lets go once it's loaded.
  private func letGo() {
    self.stopAnimating()
    self.animation = nil
    guard self.pictureSize != nil, self.covered == nil else {
      return
    }
    self.imageView.kf.cancelDownloadTask()
    self.isLoading = false
    self.stopShowingProgress()
    self.imageView.image = nil
    self.updatePlaceholder()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    // On a screen with other colors, its picture's drawn again in them, and an animation's frames
    // are decoded again in them, or opened again for one with other pixels to a point.
    self.recolorIfNeeded()
    guard let animation = self.animation else {
      return
    }
    if let scale = self.window?.backingScaleFactor, scale != self.animationScale {
      self.stopAnimating()
      self.animation = nil
      self.animate(waiting: false)
    }
    else if self.player.needsDecodingAgain {
      self.play(animation)
    }
  }

  /// Draws its picture again in its window's colors, off the main thread, should it be in others,
  /// as one made for a window on another screen is, or for this one before it moved, and keeps it in
  /// memory in their place, so Core Animation shows it as it is, rather than keeping a copy of it in
  /// those colors as well.
  private func recolorIfNeeded() {
    guard let colorSpace = self.window?.colorSpace?.cgColorSpace, let key = self.source?.cacheKey, self.covered == nil,
          let image = self.imageView.image, let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return
    }
    let colors = ImagePreview.previewColors(colorSpace)
    guard picture.colorSpace != colors else {
      return
    }
    let name = self.previewName(in: colorSpace)
    Task { [weak self] in
      let redrawn = await Task.detached(priority: .userInitiated) {
        ImagePreview.still(drawing: picture, in: colors)
      }.value
      // Unless it's had another picture since, or let go of it.
      guard let self, let redrawn, self.imageView.image === image else {
        return
      }
      self.imageView.image = redrawn
      ImagePreview.cache.store(redrawn, forKey: key, processorIdentifier: name, toDisk: false, completionHandler: nil)
    }
  }

  /// Plays an animation's frames over the image view, which goes once the first is showing, as it
  /// would show through where a frame's clear.
  private func play(_ animation: AnimationFrames) {
    self.player.onShow = { [weak self] in
      self?.framesView.isHidden = false
      self?.imageView.isHidden = true
    }
    self.player.play(animation)
  }

  /// Stops an animation, or its opening, leaving the image view, and its first frame, or what's in
  /// its place, but for the link it shows in place of an image it can't have, which it leaves as it
  /// is.
  private func stopAnimating() {
    self.opening?.cancel()
    self.opening = nil
    self.player.stop()
    self.framesView.isHidden = true
    if self.linkLabel == nil, !self.isChecking {
      self.imageView.isHidden = false
    }
  }

  /// Plays the picture, should it be an animation, while animations play by themselves, or it's
  /// pointed at: once it's settled on screen, so one that only goes by as you scroll is never
  /// decoded, or straight away. Opened from the file it's kept in, as it came, off the main thread,
  /// fitted to the preview. Never while it's being checked, or covered, or showing its link, or out
  /// of a window.
  private func animate(waiting: Bool = true) {
    guard self.mayBeAnimated, ImagePreview.playsByThemselves || self.isPointedAt, self.window != nil, !self.isChecking, self.covered == nil,
          self.linkLabel == nil, self.imageView.image != nil, let key = self.source?.cacheKey, let pictureSize = self.pictureSize else {
      return
    }
    if let animation = self.animation {
      self.play(animation)
      return
    }
    // Being opened, or found not to be an animation, since it came back.
    guard self.opening == nil else {
      return
    }
    let size = ImagePreview.previewSize(forImageSize: pictureSize)
    self.opening = Task { [weak self] in
      // Once it's stayed where it is a moment, or else been on screen a while, as it is while you
      // scroll slowly, so one that flies by isn't decoded.
      if waiting {
        var place = self?.placeInWindow
        var waited = Duration.zero
        while waited < ImagePreview.movingAnimationDelay {
          try? await Task.sleep(for: ImagePreview.animationDelay)
          waited += ImagePreview.animationDelay
          guard let self, !Task.isCancelled else {
            return
          }
          let now = self.placeInWindow
          if now == place {
            break
          }
          place = now
        }
      }
      guard !Task.isCancelled else {
        return
      }
      // With pixels enough for the screen it's on.
      let scale = self?.window?.backingScaleFactor ?? 2
      let opened = await Task.detached(priority: .userInitiated) {
        ImagePreview.animation(forKey: key).flatMap { AnimationFrames(data: $0, fitting: size, scale: scale) }
      }.value
      // Unless it's stopped since, as when it's left the window, or the pointer's left it.
      guard let self, let opened, !Task.isCancelled else {
        return
      }
      self.animation = opened
      self.animationScale = scale
      self.play(opened)
    }
  }

  /// Where it is in its window, which changes as it scrolls.
  private var placeInWindow: NSPoint {
    self.convert(NSPoint.zero, to: nil)
  }

  // The layer's color doesn't follow the appearance on its own.
  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    self.updatePlaceholder()
  }

  /// Shows the link it stands for, as words, in place of its image, which can't be had, cut short
  /// in the middle where there isn't the room for all of it.
  func showLink(_ text: NSAttributedString) {
    self.stopAnimating()
    self.imageView.isHidden = true
    self.showsPlaceholder = false
    self.layer?.cornerRadius = 0
    let shown = NSMutableAttributedString(attributedString: text)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byTruncatingMiddle
    shown.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: shown.length))
    let label = self.linkLabel ?? NSTextField(labelWithAttributedString: shown)
    label.attributedStringValue = shown
    label.usesSingleLineMode = true
    label.lineBreakMode = .byTruncatingMiddle
    label.maximumNumberOfLines = 1
    label.frame = self.bounds
    label.autoresizingMask = [.width, .height]
    if label.superview == nil {
      self.addSubview(label)
    }
    self.linkLabel = label
    label.setAccessibilityElement(false)
    self.toolTip = (self.link ?? self.url).absoluteString
    self.updateAccessibility()
    self.window?.invalidateCursorRects(for: self)
  }

  private func updatePlaceholder() {
    // Until the picture's here, and checked, if it's to be.
    let showsPlaceholder = self.showsPlaceholder && (self.imageView.image == nil || self.isChecking)
    self.effectiveAppearance.performAsCurrentDrawingAppearance {
      self.layer?.backgroundColor = showsPlaceholder ? NSColor.quaternarySystemFill.cgColor : nil
    }
    // And, should it be slow to come, that it's coming, where there's room for that.
    let showsProgress = showsPlaceholder && self.isSlow && self.imageView.image == nil && self.linkLabel == nil
      && self.window != nil && self.bounds.width >= 32 && self.bounds.height >= 24
    if showsProgress == self.progress.isHidden {
      self.progress.isHidden = !showsProgress
      if showsProgress {
        self.progress.startAnimation(nil)
      }
      else {
        self.progress.stopAnimation(nil)
      }
    }
    // And where it's coming from, until it's been had once, so it never shows as it's had again.
    if let label = self.placeholderLabel {
      label.isHidden = !(showsPlaceholder && self.imageView.image == nil && self.pictureSize == nil && self.linkLabel == nil
        && self.bounds.width >= 60 && self.bounds.height >= 40)
    }
  }

  /// Shown in the gray box, should the picture be slow to come: filling as it comes, when it's
  /// known how big it is, or else spinning.
  private let progress = NSProgressIndicator()
  /// Whether the picture's been coming a while, waiting to show its progress.
  private var isSlow = false
  private var slow: Task<Void, Never>?

  /// Waits a moment before showing that its picture's coming, so it never shows for one that
  /// comes quickly, from the cache, or a fast connection.
  private func waitToShowProgress() {
    self.stopShowingProgress()
    self.slow = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard let self, !Task.isCancelled, self.isLoading, self.imageView.image == nil else {
        return
      }
      self.isSlow = true
      self.updatePlaceholder()
    }
  }

  /// How much of the picture's come, of how much it said there is, if it said.
  private func showProgress(received: Int64, of total: Int64) {
    guard total > 0 else {
      return
    }
    self.progress.isIndeterminate = false
    self.progress.doubleValue = min(100, Double(received) / Double(total) * 100)
  }

  private func stopShowingProgress() {
    self.slow?.cancel()
    self.slow = nil
    self.isSlow = false
    self.progress.isIndeterminate = true
    self.progress.doubleValue = 0
    self.updatePlaceholder()
  }

  private func load() {
    guard !self.started else {
      if self.failedAt != nil {
        self.tryAgain()
      }
      else {
        self.loadAgain()
      }
      return
    }
    self.started = true

    // From the cache if it's been shown before.
    var options: KingfisherOptionsInfo = [
      .targetCache(ImagePreview.cache),
      .downloader(ImagePreview.downloader),
      .scaleFactor(2),
    ]
    // A picture among the server's files, through the connection to it, or one from the web, only
    // redirected on to somewhere it could load from by itself, so a link from a host it trusts
    // can't send it somewhere else that would see you.
    let source: Source
    if let path = self.sources.serverFile(at: self.url), let connection = self.sources.connection {
      source = .provider(ServerPicture(url: self.url, path: path, connection: connection) { [weak self] in
        self?.pictureStarted()
      })
    }
    else {
      source = .network(self.url)
      options.append(.redirectHandler(ImagePreview.redirects(for: self.sources)))
      // A Giphy animation's GIF, should its WebP not be had, as some at other sizes aren't.
      if let gif = ImagePreview.giphyGIF(for: self.url) {
        options.append(.alternativeSources([.network(gif)]))
      }
    }
    self.source = source
    self.baseOptions = options
    // Not one that couldn't be had a while ago, until it can be tried again.
    guard !ImagePreview.failures.contains(self.url) else {
      self.failedAt = .now
      self.onFail?(.notNow)
      return
    }
    self.loadPicture(first: true)
  }

  /// When its picture last couldn't be had, until it's had, which it's tried for again.
  private var failedAt: ContinuousClock.Instant?

  /// Tries again for its picture, which couldn't be had before: once it's back on screen, a while
  /// after, or straight away, as once the network's back. Not while it's among the links that
  /// can't be had for a while, as one the server refused.
  private func tryAgain(now: Bool = false) {
    guard let failedAt = self.failedAt, self.window != nil, now || ContinuousClock.now - failedAt >= ImagePreview.retryDelay,
          !ImagePreview.failures.contains(self.url) else {
      return
    }
    self.failedAt = nil
    self.loadPicture(first: true)
  }

  @objc private func networkDidReturn() {
    self.tryAgain(now: true)
  }

  /// Takes away the link shown in its picture's place, now it's coming, or here.
  func hideLink() {
    guard let label = self.linkLabel else {
      return
    }
    label.removeFromSuperview()
    self.linkLabel = nil
    self.layer?.cornerRadius = 6
    self.imageView.isHidden = self.isChecking
    self.showsPlaceholder = true
    self.toolTip = self.linkToolTip
    self.updateAccessibility()
    self.window?.invalidateCursorRects(for: self)
  }

  /// How its picture's had: decoded at preview size, in its window's colors, off the main thread.
  /// One that might be an animation is kept on disk as it came, for its frames to be played from,
  /// and in memory as its first frame alone, which is made from that file again once it's gone from
  /// there. It's on disk before it shows, for its frames to be read from. A still one is kept as its
  /// preview.
  private var options: KingfisherOptionsInfo {
    let colorSpace = self.window?.colorSpace?.cgColorSpace
    if self.mayBeAnimated {
      return self.baseOptions + [.processor(ImagePreview.Still.firstFrame(in: colorSpace)), .cacheOriginalImage, .cacheMemoryOnly, .waitForCache]
    }
    return self.baseOptions + [.processor(ImagePreview.Still.preview(in: colorSpace)), .cacheSerializer(ImagePreview.StillSerializer(in: colorSpace))]
  }

  /// The name its preview's kept in memory by, made for a window's colors.
  private func previewName(in colorSpace: CGColorSpace?) -> String {
    (self.mayBeAnimated ? ImagePreview.Still.firstFrame(in: colorSpace) : ImagePreview.Still.preview(in: colorSpace)).identifier
  }

  /// Whether its picture's coming from where it is, rather than from the cache, which it fades in
  /// from once it's here.
  private var isDownloading = false

  /// Its picture's started to come from where it is, which makes room for the preview.
  private func pictureStarted() {
    self.isDownloading = true
    self.onStart?()
  }

  /// A picture from the web that doesn't say how big it is has started to come, which, should it be
  /// this one's, it makes room for, as it does for one that says.
  @objc private func pictureDidStart(_ notification: Notification) {
    guard self.isLoading, !self.isDownloading, self.isHaving(notification.object as? URL) else {
      return
    }
    self.pictureStarted()
  }

  /// A picture from the web's first bytes have said how big it is, which, should it be this one's,
  /// the first time it's had, it takes the shape of, before the rest of it's here.
  @objc private func pictureSizeDidArrive(_ notification: Notification) {
    guard self.isLoading, self.pictureSize == nil, self.isHaving(notification.object as? URL),
          let size = (notification.userInfo?["size"] as? NSValue)?.sizeValue else {
      return
    }
    self.onSize?(size)
  }

  /// Whether a link's the one its picture's being had from: its own, the one it's had from since it
  /// fell back to it, or a Giphy animation's GIF, should its WebP not be had.
  private func isHaving(_ url: URL?) -> Bool {
    guard let url else {
      return false
    }
    return url == self.url || url == self.source?.url || url == ImagePreview.giphyGIF(for: self.url)
  }

  /// Fades its picture in, as it's just come.
  private func fadeIn() {
    let fade = CABasicAnimation(keyPath: "opacity")
    fade.fromValue = 0
    fade.toValue = 1
    fade.duration = 0.2
    fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
    self.imageView.layer?.add(fade, forKey: "fade in")
  }

  /// Its picture again, once it's back on screen, having let it go while it was away: from memory,
  /// straight away, or else made again from what's on disk.
  private func loadAgain() {
    guard self.pictureSize != nil, self.imageView.image == nil, self.covered == nil, self.linkLabel == nil else {
      return
    }
    self.loadPicture(first: false)
  }

  /// Has its picture, and shows it, checked first if it's to be, and plays it, should it be an
  /// animation. Only the first time does a picture that can't be had take the preview away.
  private func loadPicture(first: Bool) {
    guard let source = self.source else {
      return
    }
    // Checked before it's seen, while the Mac asks for that, unless it's been shown already.
    let key = self.url.absoluteString
    let checks = SensitiveContent.isOn && !SensitiveContent.shown.contains(key)
    self.isChecking = checks
    self.imageView.isHidden = checks

    var reportedStart = false
    self.isDownloading = false
    self.isLoading = true
    // Its progress, which Kingfisher only gives for a picture that says how big it is. One that
    // doesn't is stopped by the downloader once it's more than a preview's worth, and says it's
    // started to come through `pictureDidStart`.
    self.imageView.kf.setImage(with: source, options: self.options, progressBlock: { [weak self] received, total in
      self?.showProgress(received: received, of: total)
      guard !reportedStart else {
        return
      }
      reportedStart = true
      self?.pictureStarted()
    }) { [weak self] result in
      guard let self else {
        return
      }
      // Not one it's had again since, which this says nothing of.
      if case .failure(let error) = result, error.isNotCurrentTask {
        return
      }
      self.isLoading = false
      self.stopShowingProgress()
      switch result {
      case .success(let value):
        let downloaded = self.isDownloading
        self.isDownloading = false
        // In place of the link it showed, should it not have been had before.
        self.failedAt = nil
        self.hideLink()
        // Had from where it falls back to, as a Giphy animation's GIF, which it's had from from now
        // on, its frames played from, and kept by.
        if value.source.cacheKey != source.cacheKey {
          self.source = value.source
        }
        let size = Self.pixelSize(of: value.image)
        self.pictureSize = size
        if checks {
          self.check(value, key: key)
        }
        self.updatePlaceholder()
        self.needsLayout = true
        self.onLoad?(size)
        // Let go of again, should it have left the window while it loaded, or else played, should
        // it be an animation, unless it's to be checked first.
        if self.window == nil {
          self.letGo()
        }
        else {
          // In this window's colors, should it have been made for another's.
          self.recolorIfNeeded()
          if downloaded, !checks {
            self.fadeIn()
          }
          if !checks {
            self.animate()
          }
        }
      case .failure(let error):
        // Not when it was only stopped, as when the view went away, or loading again.
        if first, !error.isNotCurrentTask, let failure = Self.failure(of: error) {
          self.failedAt = .now
          self.onFail?(failure)
        }
      }
    }
    // Still coming, as it wasn't in memory, which it shows, should it take a while.
    if self.isLoading {
      self.waitToShowProgress()
    }
  }

  /// Whether its picture's being had.
  private var isLoading = false

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
    // Stopped as more of it came than a preview's worth.
    case .responseError(reason: .URLSessionError(error: let error)) where error is ImagePreview.TooBig:
      return .refused
    case .imageSettingError(reason: .dataProviderError(provider: _, error: let error)):
      if error is CancellationError {
        return nil
      }
      return (error as? ServerPictureError)?.isFinal == true ? .refused : .notNow
    // A Giphy animation's WebP and then its GIF, as the GIF couldn't be had.
    case .imageSettingError(reason: .alternativeSourcesExhausted(let errors)):
      guard let last = errors.last else {
        return .unreachable
      }
      return self.failure(of: last.error)
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
    (self.link ?? self.url).host(percentEncoded: false).map { "View image from \($0)" } ?? "View Image"
  }

  /// What VoiceOver says it is: the picture, by the words written for it, or where it's from, and
  /// that it might be sensitive, while it's covered, or the link, when that's in its place.
  private func updateAccessibility() {
    if let label = self.linkLabel {
      self.setAccessibilityRole(.link)
      self.setAccessibilityLabel(label.stringValue)
      return
    }
    self.setAccessibilityRole(.image)
    let name = self.altText ?? (self.link ?? self.url).host(percentEncoded: false).map { "From \($0)" } ?? "Picture"
    self.setAccessibilityLabel(self.covered != nil ? "\(name), may be sensitive" : name)
  }

  /// Checks the picture before it's seen, then shows it, covered if it might be sensitive.
  private func check(_ value: RetrieveImageResult, key: String) {
    let image = value.image
    // An animation's frames from along it, from the file it's kept in, as it came, since its first
    // can be harmless, or the picture as it's previewed.
    let animation = (self.mayBeAnimated ? self.source?.cacheKey : nil).map { key -> @Sendable () -> Data? in
      { ImagePreview.animation(forKey: key) }
    }
    let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    Task { [weak self] in
      let cover = await SensitiveContent.cover(for: picture, animation: animation, key: key)
      // Unless it's gone, or covered already, by a check from when it loaded before.
      guard let self, self.covered == nil else {
        return
      }
      self.isChecking = false
      if let cover {
        self.cover(image, with: cover)
      }
      self.imageView.isHidden = false
      self.updatePlaceholder()
      // Played, as an animation, once it's known not to need covering.
      if cover == nil {
        self.animate()
      }
    }
  }

  /// Blurs the picture, which might be sensitive, and says so, until it's asked for.
  private func cover(_ image: NSImage, with cover: SensitiveContent.Cover) {
    self.covered = (image, cover.finding)
    self.stopAnimating()
    // At the picture's size, which the preview's laid out by.
    self.imageView.image = NSImage(cgImage: cover.image, size: image.size)
    let label = NSHostingView(rootView: SensitiveContentLabel(style: .preview))
    label.frame = self.imageView.frame
    self.addSubview(label)
    self.coverLabel = label
    self.toolTip = "This may be sensitive. Click to show it."
    self.updateAccessibility()
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
    self.toolTip = self.linkToolTip
    self.updateAccessibility()
    // Played again, as an animation.
    self.animate(waiting: false)
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

  // Clicks go to the preview, not the image view inside it, or the link it shows in its place, and
  // nowhere while it isn't showing.
  override func hitTest(_ point: NSPoint) -> NSView? {
    guard self.showsPlaceholder || self.imageView.image != nil || self.linkLabel != nil else {
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
    self.open()
  }

  override func accessibilityPerformPress() -> Bool {
    self.open()
    return true
  }

  // Its parts aren't said again, as its name says them, but for its progress, while that's shown.
  override func accessibilityChildren() -> [Any]? {
    self.progress.isHidden ? [] : [self.progress]
  }

  /// What a click does: shows a picture covered as it might be sensitive, or else opens the image
  /// in a preview window, or the link, should that be in its place.
  private func open() {
    // Covered, as it might be sensitive, it's shown here, rather than opened.
    if self.covered != nil {
      self.showCovered()
      return
    }
    // The image in a preview window, or showing its link in its place, the link, as a click on it.
    let textView = self.textView
    let link = self.link ?? self.url
    if self.linkLabel == nil, let openImage = textView?.openImageAction {
      openImage(self.fileURL)
    }
    else if let openURL = textView?.openURLAction {
      openURL(link)
    }
    else {
      NSWorkspace.shared.open(link)
    }
  }

  /// The picture as a file, to open, or drag out: for a Giphy animation previewed as its WebP, its
  /// GIF, as that's what's expected of a file of one.
  private var fileURL: URL {
    ImagePreview.giphyGIF(for: self.url) ?? self.url
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
  /// link does, and any other picture a link's, for the link as it was written, and the image, but
  /// for one that can't be had.
  private func linkMenu() -> NSMenu? {
    if self.sources.serverFile(at: self.url) != nil, let menu = self.textView?.fileLinkMenu?(self.url) {
      return menu
    }
    guard let textView = self.textView else {
      return nil
    }
    let menu = NSMenu()
    for item in textView.linkMenuItems(for: self.link ?? self.url, image: self.linkLabel == nil ? self.fileURL : nil) {
      menu.addItem(item)
    }
    // The picture itself, once it's here, and seen, saved or copied as it is where it's from, after
    // opening it.
    if self.linkLabel == nil, self.pictureSize != nil, self.covered == nil, !self.isChecking {
      let index = textView.openImageAction == nil ? 0 : 1
      menu.insertItem(ChatMenuItem("Copy Image", systemImage: "doc.on.doc") { [weak self] in
        self?.copyImage()
      }, at: index)
      menu.insertItem(ChatMenuItem("Save Image…", systemImage: "square.and.arrow.down") { [weak self] in
        self?.saveImage()
      }, at: index)
    }
    return menu
  }

  /// Copies the picture as it is where it's from: straight away, should it be kept whole already,
  /// as an animation is, or else once it's downloaded again.
  private func copyImage() {
    let url = self.fileURL
    let sources = self.sources
    Task {
      guard let data = await ImagePreview.original(of: url, sources: sources) else {
        NSSound.beep()
        return
      }
      ImagePreview.copy(data)
    }
  }

  /// Saves the picture as it is where it's from, where it's asked to go, as dragging it out does.
  private func saveImage() {
    guard let window = self.window else {
      return
    }
    let url = self.fileURL
    let panel = NSSavePanel()
    panel.nameFieldStringValue = ImageFilePromise.fileName(for: url)
    if let type = UTType(filenameExtension: url.pathExtension) {
      panel.allowedContentTypes = [type]
    }
    panel.beginSheetModal(for: window) { [weak window] response in
      guard response == .OK, let destination = panel.url else {
        return
      }
      ImageFilePromise.download(url, to: destination) { error in
        guard let error else {
          return
        }
        DispatchQueue.main.async {
          if let window {
            window.presentError(error)
          }
        }
      }
    }
  }

  // MARK: Dragging

  // Dragged a little way, it takes the image along, which arrives whole where it's dropped, with
  // its first frame as it goes, should it be playing. Not while it's being checked, or covered.
  override func mouseDragged(with event: NSEvent) {
    guard !self.dragged, !self.isChecking, self.covered == nil, let down = self.mouseDownEvent, let image = self.imageView.image else {
      return
    }
    let start = down.locationInWindow
    let now = event.locationInWindow
    guard hypot(now.x - start.x, now.y - start.y) > 3 else {
      return
    }
    self.dragged = true
    let item = NSDraggingItem(pasteboardWriter: ImageFilePromise(url: self.fileURL, sources: self.sources))
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

  func filePromiseProvider(_ filePromiseProvider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
    Self.fileName(for: self.url)
  }

  /// A picture's address's last part, decoded once, as it already is, as one name, so it lands
  /// where it's dropped, or saved, whatever the link says.
  static func fileName(for url: URL) -> String {
    let name = url.lastPathComponent
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
    Self.download(self.url, to: url, completion: completionHandler)
  }

  /// A picture from the web, downloaded whole to where it's to go, in place of what's there, which
  /// is asked about first, when it's saved.
  static func download(_ source: URL, to url: URL, completion: @escaping ((any Error)?) -> Void) {
    URLSession.shared.downloadTask(with: source) { downloaded, response, error in
      guard let downloaded, let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
        completion(error ?? URLError(.badServerResponse))
        return
      }
      do {
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
          _ = try FileManager.default.replaceItemAt(url, withItemAt: downloaded)
        }
        else {
          try FileManager.default.moveItem(at: downloaded, to: url)
        }
        completion(nil)
      }
      catch {
        completion(error)
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

// MARK: - Copying

/// A copied picture's image, made only once an app pasting it asks for one, as one that doesn't take
/// the kind of file it is would.
final class CopiedImage: NSObject, NSPasteboardItemDataProvider {
  let data: Data

  init(_ data: Data) {
    self.data = data
  }

  func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
    if type == .tiff, let tiff = NSImage(data: self.data)?.tiffRepresentation {
      item.setData(tiff, forType: .tiff)
    }
  }
}

// MARK: - Sensitive Content

/// Pictures and videos that might be sensitive, as Apple's Sensitive Content Analysis finds them on
/// this Mac: in previews, server banners and preview windows, which show them blurred until they're
/// asked for. Only while the Mac has it on: Sensitive Content Warning, which someone turns on for
/// themselves, or Communication Safety, which is for children. Otherwise nothing's checked. Nothing
/// about what's found leaves the Mac, as Apple asks.
///
/// Only in builds with SENSITIVE_CONTENT_ANALYSIS, which Apple's checker is behind, below. Without
/// it, nothing's ever checked, and none of this shows.
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

  /// Whether anything's checked.
  static var isOn: Bool {
    self.intervention != .none
  }

  /// Sensitive Content Warning, in System Settings' Privacy & Security, which is where it's turned on.
  static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_NudityDetection")!

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

  fileprivate static func remember(_ finding: Finding, for key: String) {
    self.found.withLock { $0[key] = finding }
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

#if SENSITIVE_CONTENT_ANALYSIS
// Apple's checker, in builds with SENSITIVE_CONTENT_ANALYSIS and the Sensitive Content Analysis
// capability. Its entitlement is only for the App Store and development, not Developer ID, which
// Hotline's downloaded with, so without them, nothing's checked.
extension SensitiveContent {
  /// How the Mac has sensitive content shown.
  static var intervention: Intervention {
    switch self.policy {
    case .simpleInterventions: .brief
    case .descriptiveInterventions: .descriptive
    default: .none
    }
  }

  /// How the Mac has it now, read again, for Settings, which shows it.
  static func currentIntervention() -> Intervention {
    self.cachedPolicy.withLock { $0 = nil }
    return self.intervention
  }

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

  /// What's in a picture, by its frames, checked once: nothing, when nothing's checked, or none of
  /// them can be, which is tried again next time.
  @concurrent
  fileprivate static func check(_ frames: [CGImage], key: String) async -> Finding {
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

  /// What's in a video, all through, checked once.
  @concurrent
  fileprivate static func check(videoAt url: URL, key: String) async -> Finding {
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
}
#else
// Without Apple's checker: nothing's checked, so nothing's covered.
extension SensitiveContent {
  static var intervention: Intervention {
    .none
  }

  static func currentIntervention() -> Intervention {
    .none
  }

  fileprivate static func check(_ frames: [CGImage], key: String) async -> Finding {
    .nothing
  }

  fileprivate static func check(videoAt url: URL, key: String) async -> Finding {
    .nothing
  }
}
#endif

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
