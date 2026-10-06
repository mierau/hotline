import SwiftUI
import UniformTypeIdentifiers

enum FilePreviewType: Equatable {
  case unknown
  case image
  case text
  case pict
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

    let task = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        if self.info.isArchive {
          try await self.readArchive()
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
  }

  func cleanup() {
    self.previewClient?.cleanup()
    self.previewClient = nil
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
