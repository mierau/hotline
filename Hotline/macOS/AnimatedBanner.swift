#if os(macOS)
import SwiftUI
import ImageIO

/// A server's animated GIF banner, played by Core Animation.
///
/// Its frames are decoded off the main thread and handed to Core Animation as an animation at the
/// GIF's own frame timings, which the window server plays. So the app does nothing from one frame
/// to the next, and nothing's drawn while the banner toolbar's hidden. A GIF whose frames fit in
/// 16 MB is decoded once and loops by itself. A longer one is decoded a part at a time, each
/// queued while the one before it plays, and only while the banner can be seen.
///
/// It's placed the way Kingfisher's animated image view, which played them before, placed it:
/// filling the banner, cropped, but never scaled up, so a GIF smaller than the banner is centered
/// at its own size.
struct AnimatedBanner: NSViewRepresentable {
  let fileURL: URL

  func makeNSView(context: Context) -> AnimatedBannerView {
    AnimatedBannerView()
  }

  func updateNSView(_ nsView: AnimatedBannerView, context: Context) {
    nsView.fileURL = self.fileURL
  }

  static func dismantleNSView(_ nsView: AnimatedBannerView, coordinator: ()) {
    nsView.fileURL = nil
  }
}

final class AnimatedBannerView: NSView {
  /// The GIF to play.
  var fileURL: URL? {
    didSet {
      if self.fileURL != oldValue {
        self.reset()
      }
    }
  }

  private let framesLayer = CALayer()
  private var gif: BannerGIF?
  /// The GIF that's been opened, or is being.
  private var openedFileURL: URL?
  /// The colors the frames playing were decoded in.
  private var decodedColorSpace: CGColorSpace?
  private var playing: Task<Void, Never>?

  init() {
    super.init(frame: .zero)
    self.wantsLayer = true
    self.clipsToBounds = true
    // Placed and played without animations of its own. SwiftUI fades banners in and out.
    self.framesLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
    self.framesLayer.contentsGravity = .resize
    self.layer?.addSublayer(self.framesLayer)
    self.setAccessibilityElement(false)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Clicks go to the banner toolbar behind, which drags the window.
  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    self.needsLayout = true
  }

  override func layout() {
    super.layout()
    if self.openedFileURL != self.fileURL {
      self.open()
    }
    self.placeFrames()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    // A GIF played in parts plays them while it's in a window.
    guard let gif = self.gif, !gif.isWhole else {
      return
    }
    self.playing?.cancel()
    self.playing = nil
    if self.window != nil {
      self.playing = Task { [weak self] in
        await self?.playInParts(gif)
      }
    }
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    // On a screen with other colors, the frames are decoded again in them.
    if self.gif != nil, let colorSpace = self.windowColorSpace, colorSpace != self.decodedColorSpace {
      self.reset()
    }
  }

  private func reset() {
    self.playing?.cancel()
    self.playing = nil
    self.openedFileURL = nil
    self.decodedColorSpace = nil
    self.gif = nil
    self.framesLayer.removeAllAnimations()
    self.framesLayer.contents = nil
    self.needsLayout = true
  }

  /// Opens the GIF off the main thread, once the banner has a size to decode its frames for, and
  /// plays it.
  private func open() {
    guard let fileURL = self.fileURL, self.bounds.width > 0, self.bounds.height > 0 else {
      return
    }
    self.openedFileURL = fileURL
    let size = self.bounds.size
    self.playing = Task { [weak self] in
      let opened = await Task.detached(priority: .userInitiated) {
        BannerGIF(contentsOf: fileURL, shownIn: size)
      }.value
      guard let gif = opened, let self, !Task.isCancelled, self.fileURL == fileURL else {
        return
      }
      self.gif = gif
      self.placeFrames()
      if gif.isWhole {
        await self.playWhole(gif)
      }
      else if self.window != nil {
        await self.playInParts(gif)
      }
    }
  }

  /// Fills the banner, cropping what's outside it, but not past the GIF's own size, centered.
  private func placeFrames() {
    guard let size = self.gif?.size else {
      return
    }
    let bounds = self.bounds
    let scale = min(1, max(bounds.width / size.width, bounds.height / size.height))
    let drawn = CGSize(width: size.width * scale, height: size.height * scale)
    self.framesLayer.frame = CGRect(x: bounds.midX - drawn.width / 2, y: bounds.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
  }

  /// Every frame at once, looping by itself from now on.
  private func playWhole(_ gif: BannerGIF) async {
    let colorSpace = self.windowColorSpace
    let images = await Task.detached(priority: .userInitiated) {
      gif.frames(0..<gif.count, in: colorSpace)
    }.value
    guard !Task.isCancelled else {
      return
    }
    self.decodedColorSpace = colorSpace
    self.framesLayer.contents = images.first
    guard images.count > 1 else {
      return
    }
    let animation = Self.animation(images, durations: gif.durations[...])
    animation.repeatCount = .infinity
    self.framesLayer.add(animation, forKey: "frames")
  }

  /// A part at a time, from now on, each queued to start as the one before it ends. While the
  /// banner can't be seen, nothing's decoded, and once it can, it goes on from where the time is.
  private func playInParts(_ gif: BannerGIF) async {
    let origin = self.layerTime
    // Where the next part starts.
    var loop = 0
    var next = 0
    var added: [String] = []
    var serial = 0

    while !Task.isCancelled, self.window != nil {
      let range = next..<min(next + gif.partLength, gif.count)
      let start = origin + Double(loop) * gif.loopDuration + gif.starts[range.lowerBound]
      let end = start + gif.starts[range.upperBound] - gif.starts[range.lowerBound]
      let colorSpace = self.windowColorSpace
      let images = await Task.detached(priority: added.isEmpty ? .userInitiated : .utility) {
        gif.frames(range, in: colorSpace)
      }.value
      guard !Task.isCancelled else {
        return
      }
      self.decodedColorSpace = colorSpace

      let animation = Self.animation(images, durations: gif.durations[range])
      animation.beginTime = start
      // Its last frame stays until the next part covers it, should that start late.
      animation.fillMode = .forwards
      animation.isRemovedOnCompletion = false
      if added.isEmpty {
        self.framesLayer.contents = images.first
      }
      serial += 1
      self.framesLayer.add(animation, forKey: "part \(serial)")
      added.append("part \(serial)")
      if range.upperBound == gif.count {
        loop += 1
        next = 0
      }
      else {
        next = range.upperBound
      }

      // The next part's decoded while this one plays. The parts before this one have ended, and
      // it covers them.
      let wait = start - self.layerTime
      if wait > 0 {
        // Timed by a clock that stops while the Mac sleeps, as Core Animation's does, so a part
        // that's still playing after it wakes isn't taken away.
        try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(min(0.1, wait / 4)), clock: .suspending)
        guard !Task.isCancelled else {
          return
        }
      }
      for key in added.dropLast() {
        self.framesLayer.removeAnimation(forKey: key)
      }
      added.removeFirst(added.count - 1)

      if !self.isShown {
        await self.untilShown()
        let now = self.layerTime
        if now > end {
          // The parts queued have run out. Go on from the frame showing now.
          let elapsed = now - origin
          loop = Int(elapsed / gif.loopDuration)
          next = gif.frame(at: elapsed - Double(loop) * gif.loopDuration)
        }
      }
    }
  }

  /// The time in the frames layer's clock, which animations begin by.
  private var layerTime: CFTimeInterval {
    self.framesLayer.convertTime(CACurrentMediaTime(), from: nil)
  }

  /// The window's colors, which frames are decoded in, so Core Animation doesn't convert each one
  /// on the main thread as it's handed over.
  private var windowColorSpace: CGColorSpace? {
    self.window?.colorSpace?.cgColorSpace
  }

  /// Whether any of the window can be seen.
  private var isShown: Bool {
    self.window?.occlusionState.contains(.visible) == true
  }

  /// Waits until some of the window can be seen, or it's left the window.
  private func untilShown() async {
    guard let window = self.window else {
      return
    }
    let changes = NotificationCenter.default.notifications(named: NSWindow.didChangeOcclusionStateNotification, object: window)
    guard !self.isShown else {
      return
    }
    for await _ in changes {
      if self.isShown || self.window !== window {
        return
      }
    }
  }

  /// Each frame for as long as it shows, in turn.
  private static func animation(_ images: [CGImage], durations: ArraySlice<TimeInterval>) -> CAKeyframeAnimation {
    let duration = durations.reduce(0, +)
    // When each frame starts, as a fraction of the whole, and then the end.
    var keyTimes: [NSNumber] = []
    var start: TimeInterval = 0
    for frameDuration in durations {
      keyTimes.append(NSNumber(value: start / duration))
      start += frameDuration
    }
    keyTimes.append(1)

    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = images
    animation.keyTimes = keyTimes
    animation.calculationMode = .discrete
    animation.duration = duration
    return animation
  }
}

/// An animated GIF, opened to play: how long each frame shows, and its frames, decoded when
/// they're asked for, one call at a time.
private final class BannerGIF: @unchecked Sendable {
  /// The most memory the frames of a GIF that's decoded once can take.
  static let wholeLimit = 16 * 1024 * 1024
  /// The most memory each part of a longer GIF takes. The part playing and the next are kept.
  static let partLimit = 4 * 1024 * 1024

  /// The GIF's own size, in pixels, which it's drawn at in points.
  let size: CGSize
  /// How long each frame shows, in seconds.
  let durations: [TimeInterval]
  /// When each frame starts in a loop, and then when the loop ends.
  let starts: [TimeInterval]
  /// How many frames are decoded at a time.
  let partLength: Int

  private let source: CGImageSource
  /// One decode at a time, should parts restart while one's still being decoded.
  private let lock = NSLock()
  /// The frames in the file that are whole, which are the ones played.
  private let indexes: [Int]
  private let pixelWidth: Int
  private let pixelHeight: Int

  var count: Int {
    self.durations.count
  }

  var loopDuration: TimeInterval {
    self.starts[self.count]
  }

  /// Whether all its frames are decoded at once.
  var isWhole: Bool {
    self.partLength >= self.count
  }

  /// The GIF at `fileURL`, decoded with no more pixels than it needs to fill `bounds` on a Retina
  /// screen. Nil if it isn't an image.
  init?(contentsOf fileURL: URL, shownIn bounds: CGSize) {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int,
          width > 0, height > 0 else {
      return nil
    }

    // A frame cut short, as at the end of a GIF that wasn't all sent, leaves the one before it
    // showing.
    var indexes: [Int] = []
    var durations: [TimeInterval] = []
    for index in 0..<CGImageSourceGetCount(source) {
      let duration = Self.duration(of: source, at: index)
      if CGImageSourceGetStatusAtIndex(source, index) == .statusComplete {
        indexes.append(index)
        durations.append(duration)
      }
      else if !durations.isEmpty {
        durations[durations.count - 1] += duration
      }
    }
    guard !indexes.isEmpty else {
      return nil
    }

    // Two pixels for each point it's drawn at, unless it has fewer of its own.
    let size = CGSize(width: width, height: height)
    let scale = min(1, 2 * min(1, max(bounds.width / size.width, bounds.height / size.height)))
    self.pixelWidth = max(1, Int((size.width * scale).rounded()))
    self.pixelHeight = max(1, Int((size.height * scale).rounded()))

    let frameBytes = self.pixelWidth * self.pixelHeight * 4
    let fitsWhole = frameBytes * indexes.count <= Self.wholeLimit
    self.partLength = fitsWhole ? indexes.count : max(1, Self.partLimit / frameBytes)

    var starts: [TimeInterval] = [0]
    for duration in durations {
      starts.append(starts[starts.count - 1] + duration)
    }

    self.source = source
    self.size = size
    self.indexes = indexes
    self.durations = durations
    self.starts = starts
  }

  /// The frame showing at a time in the loop.
  func frame(at time: TimeInterval) -> Int {
    let next = self.starts.firstIndex { $0 > time } ?? self.starts.count
    return min(max(next - 1, 0), self.count - 1)
  }

  /// Frames decoded, in the format and colors Core Animation shows without converting them. One
  /// that can't be decoded shows the one before it.
  func frames(_ range: Range<Int>, in colorSpace: CGColorSpace?) -> [CGImage] {
    self.lock.withLock {
      var images: [CGImage] = []
      images.reserveCapacity(range.count)
      for index in range {
        if let image = self.decode(self.indexes[index], in: colorSpace) ?? images.last ?? self.blank(in: colorSpace) {
          images.append(image)
        }
      }
      return images
    }
  }

  /// How long a frame shows: its delay, or a tenth of a second for none or next to none, as
  /// browsers and Kingfisher do.
  private static func duration(of source: CGImageSource, at index: Int) -> TimeInterval {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif?[kCGImagePropertyGIFDelayTime] as? Double) ?? 0
    return delay > 0.011 ? delay : 0.1
  }

  private func decode(_ index: Int, in colorSpace: CGColorSpace?) -> CGImage? {
    guard let frame = CGImageSourceCreateImageAtIndex(self.source, index, [kCGImageSourceShouldCache: false] as CFDictionary),
          let context = self.context(colorSpace: colorSpace ?? frame.colorSpace) else {
      return nil
    }
    context.interpolationQuality = .high
    context.draw(frame, in: CGRect(x: 0, y: 0, width: self.pixelWidth, height: self.pixelHeight))
    return context.makeImage()
  }

  /// Nothing, for a frame that can't be decoded with none before it.
  private func blank(in colorSpace: CGColorSpace?) -> CGImage? {
    self.context(colorSpace: colorSpace)?.makeImage()
  }

  /// Premultiplied BGRA, in those colors if they're RGB.
  private func context(colorSpace: CGColorSpace?) -> CGContext? {
    let space = colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    return CGContext(data: nil, width: self.pixelWidth, height: self.pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                     bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
  }
}
#endif
