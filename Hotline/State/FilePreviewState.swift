import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

enum FilePreviewType: Equatable {
  case unknown
  case image
  case text
  case pict
}

/// Audio or video playing while it downloads, and what's said of it.
struct PlayingMedia {
  enum Kind {
    case audio
    case video
  }

  let kind: Kind
  let player: AVPlayer
  /// How big a video is, turned the way it plays.
  var size: CGSize = .zero
  var title: String? = nil
  var artist: String? = nil
  var album: String? = nil
  /// Its cover, when it has one the system can read.
  #if os(iOS)
  var cover: UIImage? = nil
  #elseif os(macOS)
  var cover: NSImage? = nil
  #endif
}

/// State for a file preview download
@MainActor
@Observable
final class FilePreviewState {
  enum LoadState: Equatable {
    case unloaded
    case loading
    case loaded
    case failed
  }
  
  let info: PreviewFileInfo

  var state: LoadState = .unloaded
  var progress: Double = 0.0
  /// How many bytes have come, of how many.
  var transferred: Int = 0
  var total: Int = 0
  /// About how long the rest will take, once the transfer can tell.
  var timeRemaining: TimeInterval? = nil

  var fileURL: URL? = nil

  #if os(iOS)
  var image: UIImage? = nil
  #elseif os(macOS)
  var image: NSImage? = nil
  #endif

  var text: String? = nil
  var styledText: NSAttributedString? = nil
  /// What's in an archive, which is shown in place of it.
  var archive: [ArchiveEntry]? = nil

  /// Whether it's audio or video playing as it comes.
  private(set) var isStreaming = false
  /// Audio or video playing as it comes, once the player's read enough of it to tell which.
  var playing: PlayingMedia? = nil
  /// Whether audio or video playing as it comes can't be played after all, once that's known, when
  /// it's shown once it's here, as any other file is.
  private(set) var isUnplayable = false
  /// Which parts of audio or video playing as it comes have, from 0 to 1, for showing where it can
  /// play from.
  private(set) var downloadedParts: [Range<Double>] = []

  @ObservationIgnored private var stream: FilePreviewStream?
  /// Whether the transfer the preview was opened with has been used, which can only be once.
  @ObservationIgnored private var usedTransfer = false
  @ObservationIgnored private var previewClient: HotlineFilePreviewClient?
  @ObservationIgnored private var previewTask: Task<Void, Never>?
  /// Where a picture from the web is kept while its window's open.
  @ObservationIgnored private var webDownloadFolder: URL?

  var previewType: FilePreviewType {
    self.info.previewType
  }

  init(info: PreviewFileInfo) {
    self.info = info
    self.total = info.size
  }

  // MARK: - API

  func download() {
    // Cancel any existing download
    self.previewTask?.cancel()
    self.previewClient?.cleanup()
    self.stopStreaming()

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        if self.info.isArchive {
          try await self.readArchive()
          return
        }

        if let type = self.info.playableType {
          try await self.stream(type)
          return
        }

        if let webURL = self.info.webURL {
          self.state = .loading
          self.progress = 0.0
          self.transferred = 0
          self.timeRemaining = nil
          let url = try await self.downloadFromWeb(webURL)
          self.state = .loaded
          self.progress = 1.0
          self.fileURL = url
          return
        }

        self.usedTransfer = true
        let client = HotlineFilePreviewClient(
          fileName: self.info.name,
          address: self.info.address,
          port: UInt16(self.info.port),
          reference: self.info.id,
          size: UInt32(self.info.size),
          fileType: self.info.type,
          fileCreator: self.info.creator
        )
        self.previewClient = client

        self.state = .loading
        self.progress = 0.0
        self.transferred = 0
        self.timeRemaining = nil

        let url = try await client.preview { [weak self] progress in
          guard let self else { return }

          Task { @MainActor in
            switch progress {
            case .transfer(name: _, size: let size, total: let total, progress: let p, speed: _, estimate: let estimate):
              self.progress = p
              self.transferred = size
              self.total = total
              self.timeRemaining = estimate
            default:
              break
            }
          }
        }

        // macOS can't draw most PICTs, so decode them ourselves before showing the preview.
        // Big pictures take a moment, so do it off the main thread.
        #if os(macOS)
        if self.previewType == .pict {
          let pdf = await Task.detached(priority: .userInitiated) {
            PICTImage.pdfData(fromFileAt: url)
          }.value
          try Task.checkCancellation()
          self.image = pdf.flatMap { PICTImage.image(fromPDF: $0) }
        }
        #endif

        self.state = .loaded
        self.progress = 1.0
        self.fileURL = url

      } catch is CancellationError {
        return
      } catch {
        self.state = .failed
        self.progress = 0.0
        print("FilePreviewState: Download error: \(error)")
      }
    }

    self.previewTask = task
  }

  /// Downloads a picture linked in chat into a folder of its own, under the name it's saved and
  /// shared with, showing its progress as it comes.
  private func downloadFromWeb(_ url: URL) async throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "Web Previews", directoryHint: .isDirectory)
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    // Before it starts, so a download that's stopped partway is cleaned up too.
    self.webDownloadFolder = folder
    let fileURL = folder.appending(path: self.info.name, directoryHint: .notDirectory)

    // Only the newest progress, shown here on the main actor, so the download doesn't hold on to
    // the window's state.
    let (updates, continuation) = AsyncStream.makeStream(of: (written: Int, expected: Int64).self, bufferingPolicy: .bufferingNewest(1))
    let download = Task.detached(priority: .userInitiated) {
      defer {
        continuation.finish()
      }
      try await Self.download(url, to: fileURL) { written, expected in
        continuation.yield((written, expected))
      }
    }
    let started = Date()
    for await update in updates {
      self.transferred = update.written
      // Unknown when the server doesn't say how big it is.
      guard update.expected > 0 else {
        continue
      }
      self.total = Int(update.expected)
      self.progress = Double(update.written) / Double(update.expected)
      let elapsed = Date().timeIntervalSince(started)
      if elapsed > 0.5, update.written > 0 {
        self.timeRemaining = Double(Int(update.expected) - update.written) / (Double(update.written) / elapsed)
      }
    }
    try await withTaskCancellationHandler {
      try await download.value
    } onCancel: {
      download.cancel()
    }
    return fileURL
  }

  /// How much of a picture from the web is written at a time, and so how often its progress shows.
  nonisolated private static let webChunkSize = 64 * 1024

  /// Streams a download into a file, a chunk at a time, saying how much has come of how much as it
  /// goes. Turns away an error page before any of it comes.
  nonisolated private static func download(_ url: URL, to fileURL: URL, progress: @escaping @Sendable (_ written: Int, _ expected: Int64) -> Void) async throws {
    let (bytes, response) = try await URLSession.shared.bytes(for: URLRequest(url: url))
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw URLError(.badServerResponse)
    }
    let expected = response.expectedContentLength
    FileManager.default.createFile(atPath: fileURL.path(percentEncoded: false), contents: nil)
    let handle = try FileHandle(forWritingTo: fileURL)
    defer {
      try? handle.close()
    }
    var chunk = Data()
    chunk.reserveCapacity(self.webChunkSize)
    var written = 0
    for try await byte in bytes {
      chunk.append(byte)
      if chunk.count == self.webChunkSize {
        try handle.write(contentsOf: chunk)
        written += chunk.count
        chunk.removeAll(keepingCapacity: true)
        progress(written, expected)
      }
    }
    try handle.write(contentsOf: chunk)
    written += chunk.count
    progress(written, expected)
  }

  /// Audio or video, played as it comes, from wherever it's skipped to, until all of it has, when
  /// it's the file, as any other preview's is.
  private func stream(_ type: UTType) async throws {
    guard let hotlineID = self.info.hotlineID, let path = self.info.path else {
      throw HotlineClientError.notConnected
    }
    let info = self.info
    // The transfer the preview was opened with, from the start, and then new ones, from wherever
    // the player wants.
    var first: (any FilePreviewTransfer)? = self.usedTransfer ? nil : HotlineFileStream(address: info.address, port: UInt16(info.port), reference: info.id, size: info.size, fromStart: true)
    self.usedTransfer = true
    let stream = FilePreviewStream(fileURL: HotlineFilePreviewClient.downloadURL(for: info.name, fileType: info.type), contentType: type) { offset in
      if offset == 0, let transfer = first {
        first = nil
        return transfer
      }
      first = nil
      guard let hotline = AppState.shared.hotline(id: hotlineID) else {
        throw HotlineClientError.notConnected
      }
      return try await hotline.streamFile(info.name, path: path, from: offset)
    }
    stream.changed = { [weak self] in
      self?.streamChanged()
    }
    self.stream = stream
    self.isStreaming = true
    self.state = .loading
    self.progress = 0.0
    self.transferred = 0
    self.timeRemaining = nil
    try stream.start(attributes: HotlineFilePreviewClient.attributes(fileType: info.type, fileCreator: info.creator))

    let player = AVPlayer(playerItem: AVPlayerItem(asset: stream.asset))
    player.actionAtItemEnd = .pause
    let playing = await Self.playing(stream.asset, with: player)
    // Shown once it's known, unless it's stopped, or can't play, when it's shown once it's here, as
    // any other file is.
    guard self.stream === stream, stream.error == nil else {
      return
    }
    self.playing = playing
    self.isUnplayable = playing == nil
    // As soon as it's shown, as it is when it can play.
    if playing != nil {
      player.play()
    }
  }

  /// How far audio or video playing as it comes has got, and once all of it has, the file.
  private func streamChanged() {
    guard let stream = self.stream else {
      return
    }
    if let length = stream.length, length > 0 {
      let transferred = stream.downloaded.count
      self.total = length
      self.transferred = transferred
      self.progress = Double(transferred) / Double(length)
      self.timeRemaining = stream.bytesPerSecond.map { Double(length - transferred) / $0 }
      self.downloadedParts = stream.downloaded.rangeView.map { Double($0.lowerBound) / Double(length)..<Double($0.upperBound) / Double(length) }
    }
    if stream.isComplete {
      if self.fileURL == nil {
        self.state = .loaded
        self.progress = 1.0
        self.timeRemaining = nil
        self.fileURL = stream.fileURL
      }
    }
    else if stream.error != nil {
      self.state = .failed
      self.progress = 0.0
    }
  }

  /// What's playing, once the player's read enough of it to tell: a video, and how big, or audio,
  /// and what's said of it, or nothing, when it can't play.
  private static func playing(_ asset: AVURLAsset, with player: AVPlayer) async -> PlayingMedia? {
    do {
      let (tracks, isPlayable) = try await asset.load(.tracks, .isPlayable)
      guard isPlayable else {
        return nil
      }
      if let video = tracks.first(where: { $0.mediaType == .video }) {
        let (size, transform) = try await video.load(.naturalSize, .preferredTransform)
        let turned = size.applying(transform)
        let shown = CGSize(width: abs(turned.width), height: abs(turned.height))
        if shown.width > 0, shown.height > 0 {
          return PlayingMedia(kind: .video, player: player, size: shown)
        }
      }
      guard tracks.contains(where: { $0.mediaType == .audio }) else {
        return nil
      }
      var playing = PlayingMedia(kind: .audio, player: player)
      let metadata = (try? await asset.load(.commonMetadata)) ?? []
      func item(_ identifier: AVMetadataIdentifier) -> AVMetadataItem? {
        AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first
      }
      playing.title = try? await item(.commonIdentifierTitle)?.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
      playing.artist = try? await item(.commonIdentifierArtist)?.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
      playing.album = try? await item(.commonIdentifierAlbumName)?.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines)
      if let artwork = try? await item(.commonIdentifierArtwork)?.load(.dataValue) {
        #if os(iOS)
        playing.cover = UIImage(data: artwork)
        #elseif os(macOS)
        playing.cover = NSImage(data: artwork).flatMap { $0.size.width > 0 && $0.size.height > 0 ? $0 : nil }
        #endif
      }
      return playing
    }
    catch {
      print("FilePreviewState: Can't play \(asset.url.lastPathComponent): \(error)")
      return nil
    }
  }

  /// Stops audio or video playing as it comes, and deletes what's come of it.
  private func stopStreaming() {
    self.playing?.player.pause()
    self.playing = nil
    if let stream = self.stream {
      stream.stop()
      HotlineFilePreviewClient.removeDownload(at: stream.fileURL)
      if self.fileURL == stream.fileURL {
        self.fileURL = nil
      }
    }
    self.stream = nil
    self.isStreaming = false
    self.isUnplayable = false
    self.downloadedParts = []
  }

  /// The most of a resource fork read, for the map of a disk image's chunks.
  private static let resourceForkLimit = 4 * 1024 * 1024

  /// What's in an archive, from the start of it on the server, or the end, where its list is.
  private func readArchive() async throws {
    guard let archiveKind = self.info.archiveKind, let hotlineID = self.info.hotlineID,
          let hotline = AppState.shared.hotline(id: hotlineID), let path = self.info.path else {
      throw HotlineClientError.notConnected
    }
    self.state = .loading
    let name = self.info.name
    // The start of it, which is where some archives have their list, with how long its data is,
    // which a download from the start says, unlike the list of files, and unlike a resumed one,
    // on some servers.
    let start = try await hotline.readFile(name, path: path, from: 0, length: archiveKind.startLength)
    do {
      self.archive = try await archiveKind.entries(size: start.size) { offset, length in
        if offset + length <= start.data.count {
          return start.data.subdata(in: offset..<(offset + length))
        }
        return try await hotline.readFile(name, path: path, from: offset, length: length).data
      } resourceFork: {
        try await hotline.readResourceFork(name, path: path, dataForkSize: start.size, limit: Self.resourceForkLimit)
      }
    }
    catch ArchiveReadError.notAnArchive {
      // Not the kind of archive its name says, as plenty of files named .bin aren't, so there's
      // nothing to show of it.
      self.archive = nil
    }
    self.state = .loaded
  }


  func cancel() {
    self.previewTask?.cancel()
    self.previewTask = nil
    self.previewClient?.cancel()
    self.stream?.stop()
    self.playing?.player.pause()
  }

  func cleanup() {
    self.previewClient?.cleanup()
    self.previewClient = nil
    self.stopStreaming()
    if let folder = self.webDownloadFolder {
      try? FileManager.default.removeItem(at: folder)
      self.webDownloadFolder = nil
    }
    self.fileURL = nil
    self.image = nil
    self.text = nil
    self.styledText = nil
    self.archive = nil
  }

  // MARK: - Utility

//  private func loadPreview(from url: URL) {
//    guard let data = try? Data(contentsOf: url) else {
//      self.state = .failed
//      print("FilePreviewState: Failed to read preview data from \(url.path)")
//      return
//    }
//
//    switch self.previewType {
//    case .image:
//      #if os(iOS)
//      self.image = UIImage(data: data)
//      #elseif os(macOS)
//      self.image = NSImage(data: data)
//      #endif
//
//      if self.image == nil {
//        self.state = .failed
//        print("FilePreviewState: Failed to create image from data")
//      }
//
//    case .text:
//      let encoding: UInt = NSString.stringEncoding(for: data, convertedString: nil, usedLossyConversion: nil)
//      if encoding != 0 {
//        self.text = String(data: data, encoding: String.Encoding(rawValue: encoding))
//      } else {
//        self.text = String(data: data, encoding: .utf8)
//      }
//
//      if self.text == nil {
//        self.state = .failed
//        print("FilePreviewState: Failed to decode text data")
//      }
//
//    case .unknown:
//      print("FilePreviewState: Unknown preview type for \(info.name)")
//      break
//    }
//  }
}
