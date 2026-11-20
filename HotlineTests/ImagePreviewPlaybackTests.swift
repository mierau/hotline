// ImagePreviewPlaybackTests

import Testing
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Kingfisher
import UniformTypeIdentifiers
@testable import Hotline

/// Previews' pictures and animations: made in a window's colors, kept small, let go of off screen,
/// and played as their frames are decoded, each for its own delay. In the tests' own preview folder.
@MainActor
@Suite(.serialized)
struct ImagePreviewPlaybackTests {
  /// A window off screen, which counts as seen.
  final class SeenWindow: NSWindow {
    override var occlusionState: NSWindow.OcclusionState { .visible }
  }

  private static let displayP3 = CGColorSpace(name: CGColorSpace.displayP3)!
  private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

  /// A photo-like picture: a color with a block of another in its middle, as a JPEG, or as a PNG
  /// whose edges can be seen through.
  private static func picture(width: Int = 1200, height: Int = 700, seeThrough: Bool = false) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: self.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.85, green: 0.45, blue: 0.2, alpha: seeThrough ? 0.5 : 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: width / 3, y: height / 4, width: width / 3, height: height / 2))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, (seeThrough ? UTType.png : UTType.jpeg).identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  /// A GIF of a bar moving along it, a frame for each delay.
  private static func gif(delays: [Double], width: Int = 480, height: Int = 270) -> Data {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, delays.count, nil)!
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for (frame, delay) in delays.enumerated() {
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: self.sRGB,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.setFillColor(CGColor(srgbRed: 0.3, green: 0.5, blue: 0.8, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      context.setFillColor(CGColor(srgbRed: 0.9, green: 0.8, blue: 0.2, alpha: 1))
      context.fill(CGRect(x: CGFloat(frame * width / delays.count) - 40, y: 0, width: 80, height: CGFloat(height)))
      CGImageDestinationAddImage(destination, context.makeImage()!,
                                 [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
    }
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  /// A picture's average color, as it's seen, in sRGB, from 0 to 255, in part of it, by fractions.
  private static func averageColor(of image: CGImage, in region: CGRect) -> [Double] {
    let side = 8
    let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4, space: self.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let crop = image.cropping(to: CGRect(x: region.minX * CGFloat(image.width), y: region.minY * CGFloat(image.height),
                                         width: region.width * CGFloat(image.width), height: region.height * CGFloat(image.height)).integral)!
    context.draw(crop, in: CGRect(x: 0, y: 0, width: side, height: side))
    let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
    return (0..<3).map { channel in
      (0..<(side * side)).reduce(0.0) { $0 + Double(bytes[$1 * 4 + channel]) } / Double(side * side)
    }
  }

  private static func decoded(_ data: Data) -> CGImage {
    CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
  }

  /// Whether two colors are the same, as near as `slack` allows for each part.
  private static func same(_ a: [Double], _ b: [Double], slack: Double) -> Bool {
    zip(a, b).allSatisfy { abs($0 - $1) <= slack }
  }

  private static let middle = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
  private static let edge = CGRect(x: 0.02, y: 0.02, width: 0.15, height: 0.15)

  private static func isPremultipliedBGRA(_ image: CGImage) -> Bool {
    image.alphaInfo == .premultipliedFirst
      && image.bitmapInfo.rawValue & CGBitmapInfo.byteOrderMask.rawValue == CGBitmapInfo.byteOrder32Little.rawValue
  }

  /// Waits for something to come true, for up to a few seconds.
  private static func until(_ seconds: Double = 3, _ condition: () -> Bool) async throws -> Bool {
    let start = ContinuousClock.now
    while ContinuousClock.now - start < .seconds(seconds) {
      if condition() {
        return true
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    return condition()
  }

  // MARK: Pictures

  @Test func stillIsInTheWindowsColors() throws {
    let data = Self.picture()
    let still = try #require(ImagePreview.still(from: data, maxPixelSize: 480, in: Self.displayP3)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(still.width == 480)
    #expect(still.height == 280)
    #expect(still.colorSpace == Self.displayP3)
    #expect(Self.isPremultipliedBGRA(still))
    // Its colors as they were.
    let original = Self.decoded(data)
    #expect(Self.same(Self.averageColor(of: still, in: Self.middle), Self.averageColor(of: original, in: Self.middle), slack: 2))
    #expect(Self.same(Self.averageColor(of: still, in: Self.edge), Self.averageColor(of: original, in: Self.edge), slack: 2))
  }

  @Test func previewsAreKeptSmallWithTheirColors() throws {
    let serializer = ImagePreview.StillSerializer(in: Self.displayP3)
    let options = KingfisherParsedOptionsInfo(nil)

    // One with no see-through parts, as a JPEG, whatever it came as.
    let photo = Self.picture()
    let still = try #require(ImagePreview.still(from: photo, maxPixelSize: 480, in: Self.displayP3))
    let kept = try #require(serializer.data(with: still, original: nil))
    let keptSource = try #require(CGImageSourceCreateWithData(kept as CFData, nil))
    #expect(CGImageSourceGetType(keptSource) as String? == UTType.jpeg.identifier)

    // Read back in another window's colors, as on another screen, as they were.
    let back = try #require(ImagePreview.StillSerializer(in: Self.sRGB).image(with: kept, options: options)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(back.colorSpace == Self.sRGB)
    #expect(Self.isPremultipliedBGRA(back))
    let original = Self.decoded(photo)
    #expect(Self.same(Self.averageColor(of: back, in: Self.middle), Self.averageColor(of: original, in: Self.middle), slack: 3))

    // One with see-through parts, as a PNG, which keeps them.
    let seeThrough = try #require(ImagePreview.still(from: Self.picture(seeThrough: true), maxPixelSize: 480, in: Self.displayP3))
    let keptSeeThrough = try #require(serializer.data(with: seeThrough, original: nil))
    #expect(CGImageSourceGetType(try #require(CGImageSourceCreateWithData(keptSeeThrough as CFData, nil))) as String? == UTType.png.identifier)
  }

  // MARK: Animations

  @Test func framesKeepTheirOwnDelays() throws {
    // None, or next to none, shows for a tenth of a second, as browsers have it.
    let frames = try #require(AnimationFrames(data: Self.gif(delays: [0.04, 0.5, 0, 0.02, 0.12]), fitting: CGSize(width: 240, height: 135)))
    #expect(frames.durations.map { ($0 * 1000).rounded() } == [40, 500, 100, 20, 120])
    #expect(abs(frames.loopDuration - 0.78) < 0.0001)
  }

  /// An animated WebP, as Giphy has its animations, which the system reads, but can't make: three
  /// frames, red, green and blue, 16 by 9, for a tenth, a fifth and three tenths of a second. Made
  /// with libwebp's img2webp.
  private static let webP = Data(base64Encoded: "UklGRrQAAABXRUJQVlA4WAoAAAACAAAADwAACAAAQU5JTQYAAAD/////AABBTk1GKAAAAAAAAAAAAA8AAAgAAGQAAAJWUDhMDwAAAC8PAAIABxD9j/4HIqL/AQBBTk1GKAAAAAAAAAAAAA8AAAgAAMgAAABWUDhMDwAAAC8PAAIAB9D/iP4HIqL/AQBBTk1GKAAAAAAAAAAAAA8AAAgAACwBAABWUDhMDwAAAC8PAAIABxDR//4HIqL/AQA=")!

  @Test func webPPlaysWithItsOwnDelays() throws {
    let frames = try #require(AnimationFrames(data: Self.webP, fitting: CGSize(width: 16, height: 9)))
    #expect(frames.count == 3)
    #expect(frames.durations.map { ($0 * 1000).rounded() } == [100, 200, 300])
    // Each frame, decoded, its own color.
    let whole = CGRect(x: 0, y: 0, width: 1, height: 1)
    let colors = frames.frames(0..<3, in: Self.sRGB).map { Self.averageColor(of: $0, in: whole) }
    #expect(colors.count == 3)
    #expect(Self.same(colors[0], [255, 0, 0], slack: 2))
    #expect(Self.same(colors[1], [0, 255, 0], slack: 2))
    #expect(Self.same(colors[2], [0, 0, 255], slack: 2))
    // Its preview's still, its first frame.
    let still = try #require(ImagePreview.still(from: Self.webP, maxPixelSize: 480, in: Self.sRGB)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
    #expect(Self.same(Self.averageColor(of: still, in: whole), [255, 0, 0], slack: 2))
  }

  @Test func framesHavePixelsForTheScreen() throws {
    let data = Self.gif(delays: [0.1, 0.1])
    let retina = try #require(AnimationFrames(data: data, fitting: CGSize(width: 240, height: 135), scale: 2))
    let plain = try #require(AnimationFrames(data: data, fitting: CGSize(width: 240, height: 135), scale: 1))
    #expect(retina.frames(0..<1, in: nil).first?.width == 480)
    #expect(plain.frames(0..<1, in: nil).first?.width == 240)
  }

  @Test func firstLoopPlaysAsItsFramesDecode() async throws {
    let frames = try #require(AnimationFrames(data: Self.gif(delays: Array(repeating: 0.04, count: 24)), fitting: CGSize(width: 240, height: 135)))
    #expect(frames.firstPartLength < frames.count)
    let window = SeenWindow(contentRect: NSRect(x: -4000, y: 0, width: 240, height: 135), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 135))
    view.wantsLayer = true
    window.contentView = view
    let layer = CALayer()
    view.layer?.addSublayer(layer)
    let player = AnimationPlayer(layer: layer, in: view)
    defer {
      player.stop()
      window.close()
    }
    player.play(frames)

    // Its first part plays from the start while the rest are decoded.
    #expect(try await Self.until { layer.animation(forKey: "first 0") != nil })
    let first = try #require(layer.animation(forKey: "first 0") as? CAKeyframeAnimation)
    #expect(first.values?.count == frames.firstPartLength)

    // Then all of them, looping by themselves from the same start, in place of the parts.
    #expect(try await Self.until { layer.animationKeys() == ["frames"] })
    let whole = try #require(layer.animation(forKey: "frames") as? CAKeyframeAnimation)
    #expect(whole.values?.count == 24)
    #expect(whole.beginTime == first.beginTime)
    #expect(whole.repeatCount == .infinity)
    #expect(abs(whole.duration - 0.96) < 0.0001)
  }

  // MARK: Previews

  /// A preview of a picture kept on disk, as one downloaded before, in a window off screen, in the
  /// colors given.
  private static func preview(of data: Data, named name: String, colors: NSColorSpace? = nil) async throws -> (ImagePreviewView, SeenWindow) {
    let url = URL(string: "https://example.invalid/\(UUID().uuidString)/\(name)")!
    try await ImagePreview.cache.storeToDisk(data, forKey: url.absoluteString)
    let view = ImagePreviewView(url: url, sources: ImagePreview.Sources(server: "example.invalid"))
    view.frame = NSRect(x: 0, y: 0, width: 240, height: 135)
    let window = SeenWindow(contentRect: NSRect(x: -4000, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    if let colors {
      window.colorSpace = colors
    }
    window.contentView?.addSubview(view)
    window.orderFront(nil)
    return (view, window)
  }

  private static func imageView(of preview: ImagePreviewView) -> NSImageView? {
    preview.subviews.lazy.compactMap { $0 as? NSImageView }.first
  }

  /// The layer an animation's frames play on, over the picture.
  private static func framesLayer(of preview: ImagePreviewView) -> CALayer? {
    preview.subviews.lazy.compactMap { $0 is NSImageView ? nil : $0.layer?.sublayers?.first }.first
  }

  private static func still(of preview: ImagePreviewView) -> CGImage? {
    Self.imageView(of: preview)?.image?.cgImage(forProposedRect: nil, context: nil, hints: nil)
  }

  /// Played: by itself, or while pointed at, as Settings has it.
  private static func point(at preview: ImagePreviewView) {
    if let event = NSEvent.enterExitEvent(with: .mouseEntered, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: preview.window?.windowNumber ?? 0,
                                          context: nil, eventNumber: 0, trackingNumber: 0, userData: nil) {
      preview.mouseEntered(with: event)
    }
  }

  private static func cleanUp(_ window: NSWindow) {
    window.orderOut(nil)
    window.contentView = nil
    window.close()
    ImagePreview.cache.clearMemoryCache()
    try? FileManager.default.removeItem(at: ImagePreview.directory)
  }

  @Test func copiedPictureGoesOnTheClipboardAsItCame() async throws {
    // A GIF kept whole on disk, as an animation's original is, had from there, not the network.
    let gif = Self.gif(delays: [0.1, 0.1, 0.1])
    let url = URL(string: "https://example.invalid/\(UUID().uuidString)/dance.gif")!
    try await ImagePreview.cache.storeToDisk(gif, forKey: url.absoluteString)
    defer {
      ImagePreview.cache.clearMemoryCache()
      try? FileManager.default.removeItem(at: ImagePreview.directory)
    }
    let original = try #require(await ImagePreview.original(of: url, sources: ImagePreview.Sources(server: "example.invalid")))
    #expect(original == gif)
    // On a clipboard of the tests' own, as the GIF it is, to keep it moving where it's pasted, and as
    // an image, made once one's asked for.
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("Hotline Tests \(UUID().uuidString)"))
    defer {
      pasteboard.releaseGlobally()
    }
    ImagePreview.copy(original, to: pasteboard)
    #expect(pasteboard.data(forType: NSPasteboard.PasteboardType("com.compuserve.gif")) == gif)
    let tiff = try #require(pasteboard.data(forType: .tiff))
    #expect(NSImage(data: tiff)?.size == CGSize(width: 480, height: 270))
  }

  @Test func loadedPreviewsMenuSavesAndCopiesIt() async throws {
    let url = URL(string: "https://example.invalid/\(UUID().uuidString)/photo.jpg")!
    try await ImagePreview.cache.storeToDisk(Self.picture(), forKey: url.absoluteString)
    let textView = MarkdownTextView(usingTextLayoutManager: true)
    textView.configure()
    textView.openImageAction = { _ in }
    textView.frame = NSRect(x: 0, y: 0, width: 300, height: 200)
    let preview = ImagePreviewView(url: url, link: url, sources: ImagePreview.Sources(server: "example.invalid"))
    preview.frame = NSRect(x: 0, y: 0, width: 240, height: 135)
    textView.addSubview(preview)
    let window = SeenWindow(contentRect: NSRect(x: -4000, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView?.addSubview(textView)
    window.orderFront(nil)
    defer {
      Self.cleanUp(window)
    }
    #expect(try await Self.until { Self.still(of: preview) != nil })
    let click = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                                                 context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    // Once it's here: saved or copied, after opening it, then its link's.
    #expect(preview.menu(for: click)?.items.map(\.title) == ["Open Image", "Save Image…", "Copy Image", "Open Link", "Copy Link"])
    // Its link, in its place, only the link's.
    preview.showLink(NSAttributedString(string: url.absoluteString))
    #expect(preview.menu(for: click)?.items.map(\.title) == ["Open Link", "Copy Link"])
  }

  /// pictures.example, for downloads through the shared session: a picture, whole, for anything.
  final class AnyPicture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()

    override class func canInit(with request: URLRequest) -> Bool {
      request.url?.host == "pictures.example"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      request
    }

    override func startLoading() {
      let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                     headerFields: ["Content-Type": "image/jpeg", "Content-Length": "\(Self.body.count)"])!
      self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      self.client?.urlProtocol(self, didLoad: Self.body)
      self.client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
  }

  @Test func savedPictureTakesThePlaceOfWhatsThere() async throws {
    URLProtocol.registerClass(AnyPicture.self)
    defer {
      URLProtocol.unregisterClass(AnyPicture.self)
    }
    AnyPicture.body = Self.picture()
    let folder = URL.temporaryDirectory.appending(path: "Saved Pictures \(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: folder)
    }
    // Saved over a file, as the save panel lets it be once it's asked about, in its place.
    let destination = folder.appending(path: "photo.jpg")
    try Data("not a picture".utf8).write(to: destination)
    let failure: String? = await withCheckedContinuation { continuation in
      ImageFilePromise.download(URL(string: "https://pictures.example/photo.jpg")!, to: destination) { error in
        continuation.resume(returning: error.map { "\($0)" })
      }
    }
    #expect(failure == nil)
    #expect(try Data(contentsOf: destination) == AnyPicture.body)
  }

  @Test func avifPicturesArePreviewed() async throws {
    // The photo-like picture as an AVIF, as macOS writes one.
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, "public.avif" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, Self.decoded(Self.picture()), nil)
    #expect(CGImageDestinationFinalize(destination))
    let (preview, window) = try await Self.preview(of: data as Data, named: "photo.avif")
    defer {
      Self.cleanUp(window)
    }
    #expect(try await Self.until { Self.still(of: preview) != nil })
    // Its blue middle, in its orange.
    let still = try #require(Self.still(of: preview))
    #expect(Self.same(Self.averageColor(of: still, in: Self.middle), [51, 153, 230], slack: 25))
    #expect(Self.same(Self.averageColor(of: still, in: Self.edge), [217, 115, 51], slack: 25))
  }

  @Test func previewLetsGoOffScreen() async throws {
    let (preview, window) = try await Self.preview(of: Self.gif(delays: Array(repeating: 0.04, count: 12)), named: "playing.gif")
    defer {
      Self.cleanUp(window)
    }
    Self.point(at: preview)
    #expect(try await Self.until { Self.framesLayer(of: preview)?.animationKeys()?.isEmpty == false })
    #expect(Self.imageView(of: preview)?.image != nil)

    // Away, it holds nothing: no picture, and no frames.
    preview.removeFromSuperview()
    #expect(Self.imageView(of: preview)?.image == nil)
    #expect(Self.framesLayer(of: preview)?.animationKeys()?.isEmpty != false)
    #expect(Self.framesLayer(of: preview)?.contents == nil)

    // Back, its picture's there at once, from memory, and it plays again.
    window.contentView?.addSubview(preview)
    #expect(Self.imageView(of: preview)?.image != nil)
    Self.point(at: preview)
    #expect(try await Self.until { Self.framesLayer(of: preview)?.animationKeys()?.isEmpty == false })
  }

  @Test func previewThatCouldntBeHadShowsOnceItCanBe() async throws {
    // A picture that can't be had: a link to where nothing answers, shown in its preview's place,
    // as it is for a preview that stands for its link.
    let url = URL(string: "https://example.invalid/\(UUID().uuidString)/photo.jpg")!
    let preview = ImagePreviewView(url: url, link: url, sources: ImagePreview.Sources(server: "example.invalid"))
    preview.frame = NSRect(x: 0, y: 0, width: 240, height: 135)
    var failure: ImagePreview.Failure?
    preview.onFail = { [weak preview] reason in
      failure = reason
      preview?.showLink(NSAttributedString(string: url.absoluteString))
    }
    let window = SeenWindow(contentRect: NSRect(x: -4000, y: 0, width: 300, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer {
      Self.cleanUp(window)
    }
    window.contentView?.addSubview(preview)
    window.orderFront(nil)
    #expect(try await Self.until(20) { failure != nil })
    #expect(failure == .unreachable)
    #expect(preview.subviews.contains { $0 is NSTextField })

    // Once it can be had, as the network's back, its picture, in its link's place.
    try await ImagePreview.cache.storeToDisk(Self.picture(), forKey: url.absoluteString)
    NotificationCenter.default.post(name: ImagePreview.networkDidReturn, object: nil)
    #expect(try await Self.until { Self.still(of: preview) != nil })
    #expect(!preview.subviews.contains { $0 is NSTextField })
  }

  @Test func previewsAreNamedForVoiceOver() throws {
    // Kept, as a text view keeps them, while it's shown.
    var providers: [ImagePreviewProvider] = []
    func preview(_ attachment: ImageAttachment) throws -> ImagePreviewView {
      let storage = NSTextContentStorage()
      storage.attributedString = NSAttributedString(attachment: attachment)
      let provider = ImagePreviewProvider(textAttachment: attachment, parentView: nil, textLayoutManager: nil, location: storage.documentRange.location)
      provider.loadView()
      providers.append(provider)
      return try #require(provider.view as? ImagePreviewView)
    }
    // A Markdown image, by the words written for it, as one picture.
    let cat = URL(string: "https://example.com/\(UUID().uuidString)/cat.png")!
    let described = try preview(ImageAttachment(url: cat, standsForLink: true, link: cat, linkText: NSAttributedString(string: "A cat on a keyboard")))
    #expect(described.isAccessibilityElement() && described.accessibilityRole() == .image)
    #expect(described.accessibilityLabel() == "A cat on a keyboard")
    // An address, by where it's from, and once it can't be had, as the link in its place.
    let dog = URL(string: "https://example.com/\(UUID().uuidString)/dog.png")!
    let address = try preview(ImageAttachment(url: dog, standsForLink: true, link: dog, linkText: NSAttributedString(string: dog.absoluteString)))
    #expect(address.accessibilityRole() == .image && address.accessibilityLabel() == "From example.com")
    address.onFail?(.unreachable)
    #expect(address.accessibilityRole() == .link && address.accessibilityLabel() == dog.absoluteString)
    // Its parts aren't said again, but for its progress, while that's shown.
    #expect(address.subviews.allSatisfy { !$0.isAccessibilityElement() || $0 is NSProgressIndicator })
    #expect(address.accessibilityChildren()?.isEmpty == true)
    #expect(described.accessibilityChildren()?.isEmpty == true)
  }

  @Test func voiceOverReadsPreviewsAmongTheWords() throws {
    // A post with a picture by its address, and one written as a Markdown image, with words.
    let textView = MarkdownTextView(usingTextLayoutManager: true)
    textView.configure()
    let address = "https://i.imgur.com/\(UUID().uuidString.prefix(8)).png"
    textView.show("look \(address)\n\n![A cat on a keyboard](https://i.imgur.com/\(UUID().uuidString.prefix(8)).png)", layout: .board)
    let string = textView.string as NSString
    let attachments = (0..<string.length).filter { string.character(at: $0) == 0xFFFC }
    #expect(attachments.count == 2)
    // Each, where it is in the words, as the picture it is, by where it's from, or its words.
    let named = try attachments.map { index -> String in
      let words = try #require(textView.accessibilityAttributedString(for: NSRange(location: index, length: 1)))
      let element = words.attribute(NSAttributedString.Key(rawValue: "AXAttachment"), at: 0, effectiveRange: nil) as? NSAccessibilityElement
      return "\(element?.accessibilityRole()?.rawValue ?? "nothing") \(element?.accessibilityLabel() ?? "")"
    }
    #expect(named.sorted() == ["AXImage A cat on a keyboard", "AXImage From i.imgur.com"])
  }

  @Test func newLinksBoxSaysWhereItsPictureIsComing() throws {
    // A link never previewed, shown as its preview alone: its box from the start, saying where its
    // picture's coming from, without the https://, while it comes.
    let url = URL(string: "https://example.com/\(UUID().uuidString)/cat.png")!
    let attachment = ImageAttachment(url: url, standsForLink: true, link: url, linkText: NSAttributedString(string: url.absoluteString))
    #expect(attachment.isShown && !attachment.showsLink)
    #expect(attachment.previewSize == ImagePreview.placeholderSize)
    let storage = NSTextContentStorage()
    storage.attributedString = NSAttributedString(attachment: attachment)
    let provider = ImagePreviewProvider(textAttachment: attachment, parentView: nil, textLayoutManager: nil, location: storage.documentRange.location)
    provider.loadView()
    let preview = try #require(provider.view as? ImagePreviewView)
    preview.frame = NSRect(origin: .zero, size: ImagePreview.placeholderSize)
    preview.needsLayout = true
    preview.layoutSubtreeIfNeeded()
    func shown() -> [String] {
      preview.subviews.compactMap { $0 as? NSTextField }.filter { !$0.isHidden }.map(\.stringValue)
    }
    #expect(shown() == [String(url.absoluteString.dropFirst("https://".count))])
    // Should it not be had, the link in its place, as it was written.
    preview.onFail?(.unreachable)
    #expect(attachment.showsLink && !attachment.isShown)
    #expect(shown() == [url.absoluteString])
    // One under a line that has its link already takes no room until its picture starts to come.
    let under = ImageAttachment(url: URL(string: "https://example.com/\(UUID().uuidString)/dog.png")!)
    #expect(!under.showsLink && !under.isShown)
  }

  /// A "picture" that never ends, nor says how big it is, sent half a megabyte at a time.
  final class EndlessPicture: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var sent = 0
    nonisolated(unsafe) static var stopped = false
    nonisolated(unsafe) private var timer: Timer?

    override class func canInit(with request: URLRequest) -> Bool {
      true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      request
    }

    override func startLoading() {
      let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "image/jpeg"])!
      self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      let part = Data(repeating: 0xFF, count: 512 * 1024)
      let timer = Timer(timeInterval: 0.005, repeats: true) { [weak self] _ in
        guard let self else {
          return
        }
        Self.sent += part.count
        self.client?.urlProtocol(self, didLoad: part)
      }
      RunLoop.current.add(timer, forMode: .common)
      self.timer = timer
    }

    override func stopLoading() {
      Self.stopped = true
      self.timer?.invalidate()
    }
  }

  /// The link of the last picture said to have started to come.
  private final class Started: @unchecked Sendable {
    var url: URL?
  }

  /// The start of a picture, and then nothing more, as from a host slow to send the rest.
  final class PictureStart: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var start = Data()

    override class func canInit(with request: URLRequest) -> Bool {
      true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
      request
    }

    override func startLoading() {
      let response = HTTPURLResponse(url: self.request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                     headerFields: ["Content-Type": "image/gif", "Content-Length": "1000000"])!
      self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      self.client?.urlProtocol(self, didLoad: Self.start)
    }

    override func stopLoading() {}
  }

  /// The link and size of the last picture whose first bytes said how big it is.
  private final class Sized: @unchecked Sendable {
    var url: URL?
    var size: CGSize?
  }

  @Test func pictureSaysItsSizeBeforeItsHere() async throws {
    // Through a downloader set up as previews' is, to a GIF said to be a megabyte, whose first
    // kilobyte is all that comes. URLSession holds a response's first 512 bytes back, to tell what
    // it is, so it's more than that, as the first of any picture to come over a network is.
    let downloader = ImageDownloader(name: "Picture Starts for Tests")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [PictureStart.self]
    downloader.sessionConfiguration = configuration
    downloader.sessionDelegate = ImageDownloadLimit()
    PictureStart.start = Self.gif(delays: Array(repeating: 0.1, count: 6)).prefix(1024)
    let url = URL(string: "https://slow.example/\(UUID().uuidString)/dance.gif")!
    let sized = Sized()
    let observer = NotificationCenter.default.addObserver(forName: ImagePreview.pictureSizeDidArrive, object: nil, queue: .main) { notification in
      sized.url = notification.object as? URL
      sized.size = (notification.userInfo?["size"] as? NSValue)?.sizeValue
    }
    let download = Task {
      try? await downloader.downloadImage(with: url)
    }
    defer {
      download.cancel()
      NotificationCenter.default.removeObserver(observer)
    }
    #expect(try await Self.until { sized.url == url })
    #expect(sized.size == CGSize(width: 480, height: 270))
  }

  @Test func newPreviewTakesItsPicturesShapeBeforeItsHere() throws {
    let url = URL(string: "https://example.com/\(UUID().uuidString)/tall.jpg")!
    let attachment = ImageAttachment(url: url, standsForLink: true, link: url, linkText: NSAttributedString(string: url.absoluteString))
    #expect(attachment.previewSize == ImagePreview.placeholderSize)
    let storage = NSTextContentStorage()
    storage.attributedString = NSAttributedString(attachment: attachment)
    let provider = ImagePreviewProvider(textAttachment: attachment, parentView: nil, textLayoutManager: nil, location: storage.documentRange.location)
    provider.loadView()
    let preview = try #require(provider.view as? ImagePreviewView)
    // A tall photo, by its first bytes: its shape, before the rest of it's here.
    preview.onSize?(CGSize(width: 700, height: 1200))
    #expect(attachment.imageSize == CGSize(width: 700, height: 1200))
    #expect(attachment.previewSize == CGSize(width: 117, height: 200))
    withExtendedLifetime(provider) {}
  }

  @Test func pictureThatDoesntSayHowBigItIsStopsAtTheLimit() async throws {
    // Through a downloader of its own, set up as previews' is, to a picture that never ends.
    let downloader = ImageDownloader(name: "Endless Pictures for Tests")
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [EndlessPicture.self]
    downloader.sessionConfiguration = configuration
    downloader.sessionDelegate = ImageDownloadLimit()
    let url = URL(string: "https://endless.example/\(UUID().uuidString)/photo.jpg")!
    let started = Started()
    let observer = NotificationCenter.default.addObserver(forName: ImagePreview.pictureDidStart, object: nil, queue: .main) { notification in
      started.url = notification.object as? URL
    }
    defer {
      NotificationCenter.default.removeObserver(observer)
    }
    EndlessPicture.sent = 0
    EndlessPicture.stopped = false

    var stoppedFor: (any Error)?
    do {
      _ = try await downloader.downloadImage(with: url)
    }
    catch KingfisherError.responseError(reason: .URLSessionError(error: let error)) {
      stoppedFor = error
    }
    // Stopped as too big, once a preview's worth had come, having said it had started to.
    #expect(stoppedFor is ImagePreview.TooBig)
    #expect(try await Self.until { EndlessPicture.stopped })
    #expect(Int64(EndlessPicture.sent) > ImagePreview.sizeLimit)
    #expect(Int64(EndlessPicture.sent) <= ImagePreview.sizeLimit + 4 * 512 * 1024)
    #expect(try await Self.until { started.url == url })
  }

  @Test func previewFollowsItsWindowToOtherColors() async throws {
    let (preview, window) = try await Self.preview(of: Self.picture(), named: "photo.jpg", colors: .sRGB)
    defer {
      Self.cleanUp(window)
    }
    #expect(try await Self.until { Self.still(of: preview) != nil })
    #expect(Self.still(of: preview)?.colorSpace == Self.sRGB)

    // Moved to a screen in Display P3, which tells its views their backing's changed.
    window.colorSpace = .displayP3
    preview.viewDidChangeBackingProperties()
    #expect(try await Self.until { Self.still(of: preview)?.colorSpace == Self.displayP3 })
  }
}
