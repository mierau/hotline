// FilePreviewStreamTests

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Hotline

/// A server's transfer of a file that's here, from where it's asked to start, a little at a time,
/// stopping short where it's told to, as one that's cut off does.
private actor FakeTransfer: FilePreviewTransfer {
  private let data: Data
  private let fromStart: Bool
  private var position: Int
  private let end: Int

  init(_ data: Data, from offset: Int, stoppingAt stop: Int? = nil) {
    self.data = data
    self.fromStart = offset == 0
    self.position = offset
    self.end = min(stop ?? data.count, data.count)
  }

  func open() async throws -> Int? {
    self.fromStart ? self.data.count : nil
  }

  func read() async throws -> Data? {
    guard self.position < self.end else {
      return nil
    }
    let size = min(4096 + self.position % 3000, self.end - self.position)
    defer {
      self.position += size
    }
    return self.data.subdata(in: self.position..<(self.position + size))
  }

  func close() async {
  }
}

@MainActor
struct FilePreviewStreamTests {
  private static let data = Data((0..<250_000).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ ($0 >> 8)) })

  private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
      .appending(path: "song.mp3", directoryHint: .notDirectory)
  }

  /// Waits for all of it to come, or for it to stop short, or a few seconds.
  private func waitForAll(of stream: FilePreviewStream) async {
    for _ in 0..<500 where !stream.isComplete && stream.error == nil {
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  @Test func downloadsAllOfTheFileFromTheStart() async throws {
    var offsets: [Int] = []
    let stream = FilePreviewStream(fileURL: self.temporaryURL(), contentType: .mp3) { offset in
      offsets.append(offset)
      return FakeTransfer(Self.data, from: offset)
    }
    defer {
      stream.stop()
      HotlineFilePreviewClient.removeDownload(at: stream.fileURL)
    }
    try stream.start()
    await self.waitForAll(of: stream)
    #expect(stream.isComplete)
    #expect(stream.length == Self.data.count)
    #expect(try Data(contentsOf: stream.fileURL) == Self.data)
    #expect(offsets == [0])
  }

  @Test func carriesOnFromWhereATransferWasCutOff() async throws {
    var offsets: [Int] = []
    let stream = FilePreviewStream(fileURL: self.temporaryURL(), contentType: .mp3) { offset in
      offsets.append(offset)
      // The first is cut off partway, as when a server hangs up.
      return FakeTransfer(Self.data, from: offset, stoppingAt: offsets.count == 1 ? 100_000 : nil)
    }
    defer {
      stream.stop()
      HotlineFilePreviewClient.removeDownload(at: stream.fileURL)
    }
    try stream.start()
    await self.waitForAll(of: stream)
    #expect(stream.isComplete)
    #expect(try Data(contentsOf: stream.fileURL) == Self.data)
    #expect(offsets == [0, 100_000])
  }
}
