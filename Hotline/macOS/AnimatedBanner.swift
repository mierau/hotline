#if os(macOS)
import Accessibility
import SwiftUI
import ImageIO

/// A server's animated GIF banner, played by Core Animation, as `AnimationPlayer` plays it, only
/// while the banner can be seen, and only while the system's Animated Images setting lets it.
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
  private lazy var player = AnimationPlayer(layer: self.framesLayer, in: self)
  private var frames: AnimationFrames?
  /// The GIF that's been opened, or is being, and the pixels to a point of the screen it was for.
  private var openedFileURL: URL?
  private var openedScale: CGFloat?
  private var opening: Task<Void, Never>?

  init() {
    super.init(frame: .zero)
    self.wantsLayer = true
    self.clipsToBounds = true
    // Placed and played without animations of its own. SwiftUI fades banners in and out.
    self.framesLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
    self.framesLayer.contentsGravity = .resize
    self.layer?.addSublayer(self.framesLayer)
    self.setAccessibilityElement(false)
    // Still, while the system's Animated Images setting has animations stop, or the Mac's in Low
    // Power Mode, and played again once it isn't.
    NotificationCenter.default.addObserver(self, selector: #selector(self.animatedImagesDidChange), name: AccessibilitySettings.animatedImagesEnabledDidChangeNotification, object: nil)
    LowPowerMode.watch()
    NotificationCenter.default.addObserver(self, selector: #selector(self.animatedImagesDidChange), name: LowPowerMode.didChange, object: nil)
  }

  /// Whether it plays, or shows its first frame alone, still.
  private var animates: Bool {
    AccessibilitySettings.animatedImagesEnabled && !LowPowerMode.isOn
  }

  @objc private func animatedImagesDidChange() {
    if let frames = self.frames {
      self.player.play(frames, animates: self.animates)
    }
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
    self.player.windowDidChange()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    // On a screen with other colors, or pixels to a point, the frames are decoded again for it.
    let scale = self.window?.backingScaleFactor
    if self.player.needsDecodingAgain || (scale != nil && self.openedScale != nil && scale != self.openedScale) {
      self.reset()
    }
  }

  private func reset() {
    self.opening?.cancel()
    self.opening = nil
    self.openedFileURL = nil
    self.frames = nil
    self.player.stop()
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
    let scale = self.window?.backingScaleFactor ?? 2
    self.openedScale = scale
    self.opening = Task { [weak self] in
      let opened = await Task.detached(priority: .userInitiated) {
        AnimationFrames(contentsOf: fileURL, filling: size, scale: scale)
      }.value
      guard let frames = opened, let self, !Task.isCancelled, self.fileURL == fileURL else {
        return
      }
      self.frames = frames
      self.placeFrames()
      self.player.play(frames, animates: self.animates)
    }
  }

  /// Fills the banner, cropping what's outside it, but not past the GIF's own size, centered.
  private func placeFrames() {
    guard let size = self.frames?.size else {
      return
    }
    let bounds = self.bounds
    let scale = min(1, max(bounds.width / size.width, bounds.height / size.height))
    let drawn = CGSize(width: size.width * scale, height: size.height * scale)
    self.framesLayer.frame = CGRect(x: bounds.midX - drawn.width / 2, y: bounds.midY - drawn.height / 2, width: drawn.width, height: drawn.height)
  }
}

/// Low Power Mode, which animations don't play by themselves in, to save power.
enum LowPowerMode {
  /// Posted on the main thread as it's turned on or off.
  static let didChange = Notification.Name("LowPowerModeDidChange")

  static var isOn: Bool {
    ProcessInfo.processInfo.isLowPowerModeEnabled
  }

  nonisolated(unsafe) private static let observer = NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { _ in
    NotificationCenter.default.post(name: LowPowerMode.didChange, object: nil)
  }

  /// Tells of it turning on or off from now on.
  static func watch() {
    _ = self.observer
  }
}

/// Plays an animation's frames on a layer, by Core Animation, at the animation's own timings.
///
/// Its frames are decoded off the main thread and handed to Core Animation as an animation, which
/// the window server plays. So the app does nothing from one frame to the next, and nothing's drawn
/// while its view can't be seen. An animation whose frames fit in 16 MB is decoded once and loops by
/// itself, after playing as it's decoded the first time round. A longer one is decoded a part at a
/// time, each queued while the one before it plays, and only while its view's in a window that can
/// be seen. Stopped, it stops decoding, partway.
@MainActor
final class AnimationPlayer {
  private let layer: CALayer
  private weak var view: NSView?
  private var frames: AnimationFrames?
  /// Whether it plays them, or shows the first alone, still.
  private var animates = true
  private var playing: Task<Void, Never>?
  /// The colors the frames playing were decoded in.
  private var decodedColorSpace: CGColorSpace?
  /// Called once its first frame's showing.
  var onShow: (() -> Void)?

  init(layer: CALayer, in view: NSView) {
    self.layer = layer
    self.view = view
  }

  /// Plays frames from the start, in place of any it was, or shows the first alone, still.
  func play(_ frames: AnimationFrames, animates: Bool = true) {
    self.stop()
    self.frames = frames
    self.animates = animates
    self.playing = Task { [weak self] in
      guard let self else {
        return
      }
      if !animates {
        await self.showFirst(frames)
      }
      else if frames.isWhole {
        await self.playWhole(frames)
      }
      else if self.view?.window != nil {
        await self.playInParts(frames)
      }
    }
  }

  /// Stops, and shows nothing.
  func stop() {
    self.playing?.cancel()
    self.playing = nil
    self.frames = nil
    self.decodedColorSpace = nil
    self.layer.removeAllAnimations()
    self.layer.contents = nil
  }

  /// For when its view's moved into a window, or out of one, which takes its animation away, and the
  /// frames it holds with it. It's played again from the start once it's back, with what showed as
  /// it left showing until then. Parts aren't decoded while it's out of one.
  func windowDidChange() {
    guard let frames = self.frames, self.animates else {
      return
    }
    self.playing?.cancel()
    self.playing = nil
    self.layer.removeAllAnimations()
    guard self.view?.window != nil else {
      return
    }
    self.playing = Task { [weak self] in
      if frames.isWhole {
        await self?.playWhole(frames)
      }
      else {
        await self?.playInParts(frames)
      }
    }
  }

  /// Whether the frames playing were decoded in other colors than the screen's it's on now.
  var needsDecodingAgain: Bool {
    guard self.frames != nil, let colorSpace = self.windowColorSpace else {
      return false
    }
    return colorSpace != self.decodedColorSpace
  }

  /// The first frame alone, still.
  private func showFirst(_ frames: AnimationFrames) async {
    let colorSpace = self.windowColorSpace
    let images = await Self.decode(frames, 0..<1, in: colorSpace)
    guard !Task.isCancelled else {
      return
    }
    self.decodedColorSpace = colorSpace
    self.layer.contents = images.first
    self.onShow?()
  }

  /// Every frame, looping by itself once they're all decoded. The first time round, they play as
  /// they're decoded, a part at a time, each decoded while the one before it plays, so it moves
  /// straight away, rather than once they're all here.
  private func playWhole(_ frames: AnimationFrames) async {
    let colorSpace = self.windowColorSpace
    let origin = self.layerTime
    var images: [CGImage] = []
    images.reserveCapacity(frames.count)
    var added: [String] = []
    while images.count < frames.count {
      let range = images.count..<min(images.count + frames.firstPartLength, frames.count)
      let part = await Self.decode(frames, range, in: colorSpace, priority: images.isEmpty ? .userInitiated : .utility)
      guard !Task.isCancelled else {
        return
      }
      if images.isEmpty {
        self.decodedColorSpace = colorSpace
        self.layer.contents = part.first
        self.onShow?()
      }
      images += part
      guard images.count < frames.count else {
        break
      }
      // In its place the first time round, its last frame staying until the next part covers it,
      // should that come late.
      let start = origin + frames.starts[range.lowerBound]
      let animation = Self.animation(part, durations: frames.durations[range])
      animation.beginTime = start
      animation.fillMode = .forwards
      animation.isRemovedOnCompletion = false
      let key = "first \(range.lowerBound)"
      self.layer.add(animation, forKey: key)
      added.append(key)
      // The next part's decoded once this one starts, while it plays.
      let wait = start - self.layerTime
      if wait > 0 {
        try? await Task.sleep(for: .seconds(wait), tolerance: .seconds(min(0.1, wait / 4)), clock: .suspending)
        guard !Task.isCancelled else {
          return
        }
      }
    }
    guard images.count > 1 else {
      return
    }
    // All of them, from the start of the first time round, so it goes on from where it is.
    let animation = Self.animation(images, durations: frames.durations[...])
    animation.beginTime = origin
    animation.repeatCount = .infinity
    self.layer.add(animation, forKey: "frames")
    for key in added {
      self.layer.removeAnimation(forKey: key)
    }
  }

  /// A part at a time, from now on, each queued to start as the one before it ends. While its view
  /// can't be seen, nothing's decoded, and once it can, it goes on from where the time is.
  private func playInParts(_ frames: AnimationFrames) async {
    let origin = self.layerTime
    // Where the next part starts.
    var loop = 0
    var next = 0
    var added: [String] = []
    var serial = 0

    while !Task.isCancelled, self.view?.window != nil {
      let range = next..<min(next + frames.partLength, frames.count)
      let start = origin + Double(loop) * frames.loopDuration + frames.starts[range.lowerBound]
      let end = start + frames.starts[range.upperBound] - frames.starts[range.lowerBound]
      let colorSpace = self.windowColorSpace
      let images = await Self.decode(frames, range, in: colorSpace, priority: added.isEmpty ? .userInitiated : .utility)
      guard !Task.isCancelled else {
        return
      }
      self.decodedColorSpace = colorSpace

      let animation = Self.animation(images, durations: frames.durations[range])
      animation.beginTime = start
      // Its last frame stays until the next part covers it, should that start late.
      animation.fillMode = .forwards
      animation.isRemovedOnCompletion = false
      if added.isEmpty {
        self.layer.contents = images.first
        self.onShow?()
      }
      serial += 1
      self.layer.add(animation, forKey: "part \(serial)")
      added.append("part \(serial)")
      if range.upperBound == frames.count {
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
        self.layer.removeAnimation(forKey: key)
      }
      added.removeFirst(added.count - 1)

      if !self.isShown {
        await self.untilShown()
        let now = self.layerTime
        if now > end {
          // The parts queued have run out. Go on from the frame showing now.
          let elapsed = now - origin
          loop = Int(elapsed / frames.loopDuration)
          next = frames.frame(at: elapsed - Double(loop) * frames.loopDuration)
        }
      }
    }
  }

  /// Frames decoded off the main thread, which stops partway should what's waiting for them be
  /// cancelled, as it is when it's stopped.
  private static func decode(_ frames: AnimationFrames, _ range: Range<Int>, in colorSpace: CGColorSpace?, priority: TaskPriority = .userInitiated) async -> [CGImage] {
    let decoding = Task.detached(priority: priority) {
      frames.frames(range, in: colorSpace)
    }
    return await withTaskCancellationHandler {
      await decoding.value
    } onCancel: {
      decoding.cancel()
    }
  }

  /// The time in the layer's clock, which animations begin by.
  private var layerTime: CFTimeInterval {
    self.layer.convertTime(CACurrentMediaTime(), from: nil)
  }

  /// The window's colors, which frames are decoded in, so Core Animation doesn't convert each one
  /// on the main thread as it's handed over.
  private var windowColorSpace: CGColorSpace? {
    self.view?.window?.colorSpace?.cgColorSpace
  }

  /// Whether any of the window can be seen.
  private var isShown: Bool {
    self.view?.window?.occlusionState.contains(.visible) == true
  }

  /// Waits until some of the window can be seen, or its view's left the window.
  private func untilShown() async {
    guard let window = self.view?.window else {
      return
    }
    let changes = NotificationCenter.default.notifications(named: NSWindow.didChangeOcclusionStateNotification, object: window)
    guard !self.isShown else {
      return
    }
    for await _ in changes {
      if self.isShown || self.view?.window !== window {
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

/// An animation, a GIF, an animated WebP, or an animated PNG, opened to play: how long each frame
/// shows, and its frames, decoded when they're asked for, one call at a time.
///
/// One decoded whole costs nothing as it plays, but its memory. One decoded in parts costs as much
/// as decoding each frame as it shows, as a part is decoded again each time round.
final class AnimationFrames: @unchecked Sendable {
  /// The most memory the frames of a banner that's decoded once can take.
  static let wholeLimit = 16 * 1024 * 1024
  /// The most memory a preview's can, as there are few on screen at once, and they're small, so
  /// most are decoded whole, which a longer one can be at fewer pixels.
  static let previewWholeLimit = 32 * 1024 * 1024
  /// The most memory each part of a longer one takes. The part playing and the next are kept.
  static let partLimit = 4 * 1024 * 1024

  /// The animation's own size, in pixels, which it's drawn at in points.
  let size: CGSize
  /// How long each frame shows, in seconds.
  let durations: [TimeInterval]
  /// When each frame starts in a loop, and then when the loop ends.
  let starts: [TimeInterval]
  /// How many frames are decoded at a time.
  let partLength: Int
  /// How many frames are decoded at a time the first time round, for one decoded whole, which plays
  /// as they are.
  let firstPartLength: Int

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

  /// The animation at `fileURL`, decoded with no more pixels than it needs to fill `bounds` on a
  /// screen with `scale` pixels to a point, as a banner is, cropped. Nil if it isn't an image.
  convenience init?(contentsOf fileURL: URL, filling bounds: CGSize, scale: CGFloat = 2) {
    guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
      return nil
    }
    self.init(source: source, wholeLimit: Self.wholeLimit) { size in
      [min(1, scale * min(1, max(bounds.width / size.width, bounds.height / size.height)))]
    }
  }

  /// An animation, as it came, decoded with no more pixels than it needs to fit in `bounds` on a
  /// screen with `scale` pixels to a point, as a preview is, or a pixel for each point, if that lets
  /// it be decoded whole. Nil if it isn't an image, or has only one frame, which isn't an animation.
  convenience init?(data: Data, fitting bounds: CGSize, scale: CGFloat = 2) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 1 else {
      return nil
    }
    self.init(source: source, wholeLimit: Self.previewWholeLimit) { size in
      let fit = min(bounds.width / size.width, bounds.height / size.height)
      return [min(1, scale * fit), min(1, fit)]
    }
  }

  /// An animation's frames, and how long each shows, scaled from the animation's size by the first
  /// of `scales` its frames fit whole at, or else the first, in parts.
  private init?(source: CGImageSource, wholeLimit: Int, scales: (CGSize) -> [CGFloat]) {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
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

    let size = CGSize(width: width, height: height)
    let pixels = { (scale: CGFloat) in
      (width: max(1, Int((size.width * scale).rounded())), height: max(1, Int((size.height * scale).rounded())))
    }
    let candidates = scales(size).map(pixels)
    let whole = candidates.first { $0.width * $0.height * 4 * indexes.count <= wholeLimit }
    let chosen = whole ?? candidates.first ?? pixels(1)
    self.pixelWidth = chosen.width
    self.pixelHeight = chosen.height

    let frameBytes = self.pixelWidth * self.pixelHeight * 4
    let partLength = max(1, Self.partLimit / frameBytes)
    self.partLength = whole != nil ? indexes.count : partLength
    self.firstPartLength = min(indexes.count, partLength)

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
  /// that can't be decoded shows the one before it. Fewer, should the task decoding them be
  /// cancelled.
  func frames(_ range: Range<Int>, in colorSpace: CGColorSpace?) -> [CGImage] {
    self.lock.withLock {
      var images: [CGImage] = []
      images.reserveCapacity(range.count)
      for index in range {
        guard !Task.isCancelled else {
          break
        }
        if let image = self.decode(self.indexes[index], in: colorSpace) ?? images.last ?? self.blank(in: colorSpace) {
          images.append(image)
        }
      }
      return images
    }
  }

  /// How long a frame shows: its delay, as a GIF, a WebP, or a PNG has it, or a tenth of a second
  /// for none or next to none, as browsers and Kingfisher do.
  private static func duration(of source: CGImageSource, at index: Int) -> TimeInterval {
    let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
    let delays: [(dictionary: CFString, unclamped: CFString, clamped: CFString)] = [
      (kCGImagePropertyGIFDictionary, kCGImagePropertyGIFUnclampedDelayTime, kCGImagePropertyGIFDelayTime),
      (kCGImagePropertyWebPDictionary, kCGImagePropertyWebPUnclampedDelayTime, kCGImagePropertyWebPDelayTime),
      (kCGImagePropertyPNGDictionary, kCGImagePropertyAPNGUnclampedDelayTime, kCGImagePropertyAPNGDelayTime),
    ]
    var delay: Double = 0
    for keys in delays {
      if let frame = properties?[keys.dictionary] as? [CFString: Any] {
        delay = (frame[keys.unclamped] as? Double) ?? (frame[keys.clamped] as? Double) ?? 0
        break
      }
    }
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
