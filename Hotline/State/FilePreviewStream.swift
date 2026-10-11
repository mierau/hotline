import Foundation
import AVFoundation
import UniformTypeIdentifiers

/// A transfer of a file, from somewhere in its data fork on.
protocol FilePreviewTransfer: Sendable {
  /// Connects, and says how long the data fork is, if the transfer says, as one from the start of
  /// it does.
  func open() async throws -> Int?
  /// The next of its bytes, as soon as any have come, or nil once it's sent all it will.
  func read() async throws -> Data?
  func close() async
}

enum FilePreviewStreamError: Error {
  /// The first transfer didn't say how long the file is.
  case unknownLength
  /// A transfer stopped before it got to where it was to.
  case endedEarly
}

/// Audio or video that plays while it downloads. The player reads it through this, as it needs it,
/// from a file it's downloaded into as it comes, which is the whole file once all of it has.
///
/// One transfer at a time brings it, from the start on. When the player wants a part a way off, as
/// it does for a movie whose index is at its end, or one skipped ahead in, the transfer starts again
/// from there, and what it skipped comes after.
@MainActor
final class FilePreviewStream: NSObject {
  /// A transfer of the file from `offset` in its data fork.
  typealias Transfers = @MainActor (_ offset: Int) async throws -> any FilePreviewTransfer

  /// Where it's downloaded to.
  let fileURL: URL
  /// What the player's told it is.
  let contentType: UTType
  /// The file, as the player reads it, through this.
  let asset: AVURLAsset

  /// How long it is, once the first transfer says.
  private(set) var length: Int?
  /// Which of its bytes have come.
  private(set) var downloaded = IndexSet()
  /// How fast it's coming lately, in bytes a second, once there's been enough to tell.
  private(set) var bytesPerSecond: Double?
  /// Why it stopped before all of it came, if it did.
  private(set) var error: Error?

  /// Told as more of it comes, once all of it has, and if it stops short.
  var changed: (() -> Void)?

  var isComplete: Bool {
    self.length.map { self.downloaded.count == $0 } ?? false
  }

  private let transfers: Transfers
  /// What the player's asked for that it hasn't been given all of yet, oldest first.
  private var requests: [AVAssetResourceLoadingRequest] = []
  /// What the player asked for last, which is what it's playing, or about to: only that moves the
  /// transfer, as it asks for more besides, such as what's before where it skipped to, as it plays.
  private weak var newest: AVAssetResourceLoadingRequest?
  /// Where what the player's asked for, and is waiting for, is next, the newest first.
  private var waiting: [Int] = []
  /// The transfer that's coming, if one is.
  private var reader: Reader?
  /// For giving the player what's come.
  private var file: FileHandle?
  /// Transfers that failed in a row without bringing anything.
  private var failures = 0
  private var retry: Task<Void, Never>?
  /// A turn to give the player more, or to start a transfer, after a moment.
  private var later: Task<Void, Never>?
  private var stopped = false
  /// When it was last told that more came, and a turn to tell it after a moment, for telling it no
  /// more than every so often.
  private var lastChanged: ContinuousClock.Instant?
  private var changing: Task<Void, Never>?

  /// Bytes that came in each tenth of a second lately, the newest last, for how fast they're coming.
  private var arrivals: [(tick: Int, bytes: Int)] = []
  private let began = ContinuousClock.now

  /// The made-up scheme the player's given the file by, so it asks for it here.
  nonisolated static let scheme = "hotline-stream"
  /// How long a transfer has before another starts in its place, so one isn't started after
  /// another as the player skips about.
  private static let restartInterval: Duration = .milliseconds(250)
  /// The most of what's come to give the player at once, and before others get a turn.
  private static let chunkSize = 512 * 1024
  private static let servingLimit = 4 * 1024 * 1024
  /// How long a transfer's given to get to what's wanted, at the speed it's coming, before another
  /// starts from there, as starting one again takes about that long, and the least ahead it's
  /// waited for.
  private static let lookaheadTime = 2.0
  private static let minimumLookahead = 256 * 1024
  private static let retries = 4
  private static let changeInterval: Duration = .milliseconds(100)

  init(fileURL: URL, contentType: UTType, transfers: @escaping Transfers) {
    self.fileURL = fileURL
    self.contentType = contentType
    self.transfers = transfers
    var components = URLComponents()
    components.scheme = Self.scheme
    components.host = "preview"
    components.path = "/\(UUID().uuidString)/\(fileURL.lastPathComponent)"
    self.asset = AVURLAsset(url: components.url ?? fileURL)
    super.init()
    self.asset.resourceLoader.setDelegate(self, queue: .main)
  }

  /// Whether a file of this type can play as it comes.
  nonisolated static func canPlay(_ type: UTType) -> Bool {
    self.playableTypes.contains(type.identifier)
  }

  nonisolated private static let playableTypes: Set<String> = {
    if #available(macOS 26.0, iOS 26.0, *) {
      return Set(AVURLAsset.audiovisualContentTypes.map(\.identifier))
    }
    return Set(AVURLAsset.audiovisualTypes().map(\.rawValue))
  }()

  // MARK: - API

  /// Starts bringing it, from the start, into a new file with `attributes`.
  func start(attributes: [FileAttributeKey: Any] = [:]) throws {
    let path = self.fileURL.path(percentEncoded: false)
    try FileManager.default.createDirectory(at: self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard FileManager.default.createFile(atPath: path, contents: nil, attributes: attributes) else {
      throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: path])
    }
    self.file = try FileHandle(forReadingFrom: self.fileURL)
    self.read(from: 0)
  }

  /// Stops the transfer, and the player reading any more. What's come stays where it is.
  func stop() {
    self.stopped = true
    let reader = self.reader
    self.reader = nil
    reader?.task?.cancel()
    self.retry?.cancel()
    self.later?.cancel()
    self.changing?.cancel()
    for request in self.requests {
      request.finishLoading(with: CancellationError())
    }
    self.requests.removeAll()
    try? self.file?.close()
    self.file = nil
  }

  // MARK: - Giving it to the player

  private func add(_ request: AVAssetResourceLoadingRequest) {
    guard !self.stopped else {
      request.finishLoading(with: CancellationError())
      return
    }
    self.requests.append(request)
    self.newest = request
    self.serve()
  }

  private func cancel(_ request: AVAssetResourceLoadingRequest) {
    self.requests.removeAll { $0 === request }
  }

  /// Gives the player what it's asked for, as much as has come, and has the transfer bring what
  /// it's waiting for.
  private func serve() {
    guard let length = self.length, !self.stopped else {
      return
    }
    var wanted: Int?
    var waiting: [Int] = []
    var more = false
    var answered: [AVAssetResourceLoadingRequest] = []
    // Not the list itself, which the player could change while it's told things.
    for request in self.requests {
      if let information = request.contentInformationRequest, information.contentType == nil {
        information.contentType = self.contentType.identifier
        information.contentLength = Int64(length)
        information.isByteRangeAccessSupported = true
      }
      guard let dataRequest = request.dataRequest else {
        request.finishLoading()
        answered.append(request)
        continue
      }
      let end = dataRequest.requestsAllDataToEndOfResource ? length : min(length, Int(dataRequest.requestedOffset) + dataRequest.requestedLength)
      var offset = Int(dataRequest.currentOffset)
      var given = 0
      var unreadable = false
      while offset < end, given < Self.servingLimit, let run = self.downloaded.run(from: offset) {
        let upTo = min(run.upperBound, end, offset + Self.chunkSize)
        guard let data = self.bytes(offset..<upTo), !data.isEmpty else {
          unreadable = true
          break
        }
        dataRequest.respond(with: data)
        offset += data.count
        given += data.count
      }
      // What's come can't be read back, as when the file's gone, so it's no use trying again.
      if unreadable {
        request.finishLoading(with: CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: self.fileURL]))
        answered.append(request)
      }
      else if offset >= end {
        request.finishLoading()
        answered.append(request)
      }
      else if self.downloaded.contains(offset) {
        more = true
      }
      else {
        waiting.insert(offset, at: 0)
        if request === self.newest {
          wanted = offset
        }
      }
    }
    self.requests.removeAll { request in
      answered.contains { $0 === request }
    }
    self.waiting = waiting
    if more {
      self.serve(after: .zero)
    }
    if let wanted {
      self.want(wanted)
    }
  }

  /// Another turn at giving the player what's come, after `delay`, unless one's coming.
  private func serve(after delay: Duration) {
    guard self.later == nil else {
      return
    }
    self.later = Task { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      else {
        await Task.yield()
      }
      guard let self, !Task.isCancelled else {
        return
      }
      self.later = nil
      self.serve()
    }
  }

  /// What's come of the file, there.
  private func bytes(_ range: Range<Int>) -> Data? {
    guard let file = self.file else {
      return nil
    }
    do {
      try file.seek(toOffset: UInt64(range.lowerBound))
      return try file.read(upToCount: range.count)
    }
    catch {
      print("FilePreviewStream: Couldn't read \(range) of \(self.fileURL.lastPathComponent): \(error)")
      return nil
    }
  }

  // MARK: - Transfers

  /// A transfer bringing what's from where it started until what's come after it, or the end.
  private final class Reader {
    let start: Int
    var end: Int
    /// How far it's brought it.
    var position: Int
    var task: Task<Void, Never>?
    let started = ContinuousClock.now

    init(start: Int, end: Int) {
      self.start = start
      self.end = end
      self.position = start
    }
  }

  /// How far ahead of the transfer what's wanted can be for it to get there before a new one could.
  private var lookahead: Int {
    max(Self.minimumLookahead, Int((self.bytesPerSecond ?? 0) * Self.lookaheadTime))
  }

  /// Has what's at `offset` brought: by the transfer that's coming, if it'll be there soon, or by
  /// one from there.
  private func want(_ offset: Int) {
    if let reader = self.reader {
      if offset >= reader.position, offset < reader.end, offset - reader.position <= self.lookahead {
        return
      }
      // Where the player's got to after a moment, when it's skipping about.
      let elapsed = ContinuousClock.now - reader.started
      if elapsed < Self.restartInterval {
        self.serve(after: Self.restartInterval - elapsed)
        return
      }
    }
    self.read(from: offset)
  }

  /// Starts a transfer from `offset`, in place of the one that's coming.
  private func read(from offset: Int) {
    guard !self.stopped else {
      return
    }
    self.retry?.cancel()
    self.retry = nil
    self.reader?.task?.cancel()
    let end = self.downloaded.integerGreaterThan(offset) ?? self.length ?? Int.max
    let reader = Reader(start: offset, end: end)
    self.reader = reader
    print("FilePreviewStream: Reading \(self.fileURL.lastPathComponent) from \(offset)\(end < Int.max ? " to \(end)" : "")")
    reader.task = Task { [weak self] in
      await self?.run(reader)
    }
  }

  private func run(_ reader: Reader) async {
    let transfer: any FilePreviewTransfer
    do {
      transfer = try await self.transfers(reader.start)
    }
    catch {
      self.ended(reader, error)
      return
    }
    var failure: Error?
    do {
      try Task.checkCancellation()
      let said = try await transfer.open()
      try Task.checkCancellation()
      if self.length == nil {
        guard let said else {
          throw FilePreviewStreamError.unknownLength
        }
        try self.learned(said)
      }
      if let length = self.length {
        reader.end = min(reader.end, length)
      }
      try await self.receive(transfer, for: reader)
    }
    catch {
      failure = error
    }
    await transfer.close()
    self.ended(reader, failure)
  }

  /// How long it is, from the first transfer, which the file's made, for the player to be told.
  private func learned(_ length: Int) throws {
    print("FilePreviewStream: \(self.fileURL.lastPathComponent) is \(length) bytes")
    let handle = try FileHandle(forWritingTo: self.fileURL)
    try handle.truncate(atOffset: UInt64(length))
    try handle.close()
    self.length = length
    self.serve()
  }

  /// Writes what the transfer brings into the file, from where it started till where it's to stop,
  /// off the main thread, giving the player each part as it comes.
  private func receive(_ transfer: any FilePreviewTransfer, for reader: Reader) async throws {
    let fileURL = self.fileURL
    let start = reader.start
    let end = reader.end
    let (positions, continuation) = AsyncStream.makeStream(of: Int.self, bufferingPolicy: .bufferingNewest(1))
    let writing = Task.detached(priority: .userInitiated) {
      defer {
        continuation.finish()
      }
      let handle = try FileHandle(forWritingTo: fileURL)
      defer {
        try? handle.close()
      }
      try handle.seek(toOffset: UInt64(start))
      var position = start
      while position < end {
        try Task.checkCancellation()
        guard let data = try await transfer.read() else {
          throw FilePreviewStreamError.endedEarly
        }
        let usable = data.prefix(end - position)
        try handle.write(contentsOf: usable)
        position += usable.count
        continuation.yield(position)
      }
    }
    continuation.onTermination = { _ in
      writing.cancel()
    }
    for await position in positions {
      self.received(reader, upTo: position)
    }
    try await writing.value
  }

  private func received(_ reader: Reader, upTo position: Int) {
    guard position > reader.position else {
      return
    }
    let range = reader.position..<position
    reader.position = position
    self.downloaded.insert(integersIn: range)
    self.failures = 0
    self.measure(range.count)
    self.serve()
    self.tellChanged()
  }

  /// Tells it more came, now, or if it was just told, in a moment.
  private func tellChanged() {
    guard self.changing == nil else {
      return
    }
    let now = ContinuousClock.now
    guard let last = self.lastChanged, now - last < Self.changeInterval else {
      self.lastChanged = now
      self.changed?()
      return
    }
    self.changing = Task { [weak self] in
      try? await Task.sleep(for: Self.changeInterval - (now - last))
      guard let self, !Task.isCancelled else {
        return
      }
      self.changing = nil
      self.lastChanged = ContinuousClock.now
      self.changed?()
    }
  }

  private func ended(_ reader: Reader, _ error: Error?) {
    guard self.reader === reader, !self.stopped else {
      return
    }
    self.reader = nil
    if self.isComplete {
      print("FilePreviewStream: All of \(self.fileURL.lastPathComponent) has come")
      self.changed?()
      return
    }
    if let error {
      self.failures += 1
      print("FilePreviewStream: Transfer from \(reader.start) stopped at \(reader.position): \(error)")
      guard self.failures <= Self.retries else {
        self.fail(error)
        return
      }
      // A moment, longer each time, then again from where it got to.
      let delay = Duration.milliseconds(500 * (1 << (self.failures - 1)))
      self.retry = Task { [weak self] in
        try? await Task.sleep(for: delay)
        guard let self, !Task.isCancelled else {
          return
        }
        self.retry = nil
        self.next(after: reader.position)
      }
      return
    }
    self.next(after: reader.position)
  }

  /// Starts the next transfer: from what the player last asked for, if it's waiting for it, or else
  /// from what's missing after where the last one stopped, which is where it's likely going, or
  /// whatever else it's waiting for, or what's missing before.
  private func next(after position: Int) {
    self.serve()
    guard self.reader == nil else {
      return
    }
    guard let length = self.length else {
      self.read(from: 0)
      return
    }
    if let missing = self.downloaded.firstMissing(from: position, below: length) ?? self.waiting.first ?? self.downloaded.firstMissing(from: 0, below: length) {
      self.read(from: missing)
    }
  }

  private func fail(_ error: Error) {
    print("FilePreviewStream: Gave up on \(self.fileURL.lastPathComponent): \(error)")
    self.error = error
    for request in self.requests {
      request.finishLoading(with: error)
    }
    self.requests.removeAll()
    self.changed?()
  }

  /// Counts what came, for how fast it's coming: what came in the last few seconds, over how long
  /// that was.
  private func measure(_ bytes: Int) {
    let now = ContinuousClock.now - self.began
    let tick = Int(now / .milliseconds(100))
    if let last = self.arrivals.last, last.tick == tick {
      self.arrivals[self.arrivals.count - 1].bytes += bytes
    }
    else {
      self.arrivals.append((tick, bytes))
    }
    self.arrivals.removeAll { $0.tick <= tick - 30 }
    guard let first = self.arrivals.first, tick - first.tick >= 5 else {
      return
    }
    let seconds = Double(tick - first.tick + 1) / 10
    self.bytesPerSecond = Double(self.arrivals.reduce(0) { $0 + $1.bytes }) / seconds
  }
}

extension FilePreviewStream: AVAssetResourceLoaderDelegate {
  nonisolated func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
    MainActor.assumeIsolated {
      self.add(loadingRequest)
    }
    return true
  }

  nonisolated func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
    MainActor.assumeIsolated {
      self.cancel(loadingRequest)
    }
  }
}

private extension IndexSet {
  /// From `index` to the end of the run of indexes it's in, if it's in one.
  func run(from index: Int) -> Range<Int>? {
    self.rangeView.first { $0.contains(index) }.map { index..<$0.upperBound }
  }

  /// The first index from `start` up to `end` that isn't in it.
  func firstMissing(from start: Int, below end: Int) -> Int? {
    guard start < end else {
      return nil
    }
    // A run's followed by one that isn't in it.
    let missing = self.run(from: start)?.upperBound ?? start
    return missing < end ? missing : nil
  }
}
