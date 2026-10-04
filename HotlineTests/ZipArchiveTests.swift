// ZipArchiveTests

import Testing
import Foundation
@testable import Hotline

struct ZipArchiveTests {

  // MARK: - What's in an archive

  @Test func readsFilesAndFolders() async throws {
    let archive = TestArchive(items: [
      .init("ReadMe.txt", size: 100),
      .init("Docs/", folder: true),
      .init("Docs/Guide.pdf", size: 2000),
      .init("Docs/Images/Cover.png", size: 50),
    ])
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries == [
      ArchiveEntry(path: "ReadMe.txt", isFolder: false, size: 100),
      ArchiveEntry(path: "Docs", isFolder: true, size: 0),
      ArchiveEntry(path: "Docs/Guide.pdf", isFolder: false, size: 2000),
      ArchiveEntry(path: "Docs/Images/Cover.png", isFolder: false, size: 50),
    ])
  }

  @Test func leavesOutFinderInformation() async throws {
    let archive = TestArchive(items: [
      .init("ReadMe.txt", size: 10),
      .init("__MACOSX/", folder: true),
      .init("__MACOSX/._ReadMe.txt", size: 82),
      .init(".DS_Store", size: 6148),
      .init("Docs/.DS_Store", size: 6148),
    ])
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries.map(\.path) == ["ReadMe.txt"])
  }

  @Test func readsNamesInUTF8() async throws {
    let archive = TestArchive(items: [.init("Café ☕/Menu.txt", size: 10)])
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries.map(\.path) == ["Café ☕/Menu.txt"])
  }

  @Test func readsOldDOSNames() async throws {
    // "Docs\Résumé.txt" in the DOS code page, with a backslash between folders, from Windows.
    let name: [UInt8] = Array("Docs\\R".utf8) + [0x82] + Array("sum".utf8) + [0x82] + Array(".txt".utf8)
    let archive = TestArchive(items: [.init(bytes: name, size: 10, madeBy: 0x0014, flags: 0)])
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries.map(\.path) == ["Docs/Résumé.txt"])
  }

  @Test func readsTheUnicodeNameAlongsideAnOldOne() async throws {
    let unicode = Array("Ünïcödé.txt".utf8)
    var item = TestArchive.Item(bytes: Array("Unicode.txt".utf8), size: 10, madeBy: 0x0014, flags: 0)
    item.extra = TestArchive.field(0x7075, [1, 0, 0, 0, 0] + unicode)
    let archive = TestArchive(items: [item])
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries.map(\.path) == ["Ünïcödé.txt"])
  }

  @Test func readsZIP64() async throws {
    var archive = TestArchive(items: [.init("Big.iso", size: 5_000_000_000), .init("Small.txt", size: 10)])
    archive.zip64 = true
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries == [
      ArchiveEntry(path: "Big.iso", isFolder: false, size: 5_000_000_000),
      ArchiveEntry(path: "Small.txt", isFolder: false, size: 10),
    ])
  }

  // MARK: - Reading as little of it as it can

  @Test func readsOnlyTheEnd() async throws {
    let archive = TestArchive(items: [.init("ReadMe.txt", size: 400_000)])
    let server = TestServer(archive.data)
    _ = try await ZipArchive.entries(size: archive.data.count, read: server.read)
    #expect(server.reads.count == 1)
    #expect(server.reads[0].offset == archive.data.count - ZipArchive.endLength)
    #expect(server.reads[0].length == ZipArchive.endLength)
  }

  @Test func readsAllOfASmallOne() async throws {
    let archive = TestArchive(items: [.init("ReadMe.txt", size: 1000)])
    let server = TestServer(archive.data)
    _ = try await ZipArchive.entries(size: archive.data.count, read: server.read)
    #expect(server.reads.count == 1)
    #expect(server.reads[0].offset == 0)
    #expect(server.reads[0].length == archive.data.count)
  }

  @Test func readsALongListOnItsOwn() async throws {
    // A list longer than the end that's read first.
    let names = (0..<3000).map { String(format: "Folder/A file with a name long enough to fill up a list quickly, number %04d.txt", $0) }
    let archive = TestArchive(items: names.map { .init($0, size: 1) })
    let server = TestServer(archive.data)
    let entries = try await ZipArchive.entries(size: archive.data.count, read: server.read)
    #expect(entries.count == 3000)
    #expect(server.reads.count == 2)
  }

  @Test func turnsDownTheStartOfAFileSentForItsEnd() async throws {
    // A server that can't resume a download sends the file from the start, wherever it's asked to.
    let archive = TestArchive(items: [.init("ReadMe.txt", size: 600_000)])
    let server = TestServer(archive.data)
    server.ignoresOffsets = true
    await #expect(throws: ArchiveReadError.self) {
      try await ZipArchive.entries(size: archive.data.count, read: server.read)
    }
  }

  @Test func readsAnArchiveAfterAProgramThatUnpacksIt() async throws {
    var archive = TestArchive(items: [.init("ReadMe.txt", size: 10)])
    archive.prefix = Data(repeating: 0x90, count: 5000)
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries.map(\.path) == ["ReadMe.txt"])
  }

  @Test func readsPastAComment() async throws {
    var archive = TestArchive(items: [.init("ReadMe.txt", size: 10)])
    archive.comment = Data("Thanks for downloading!".utf8)
    let entries = try await ZipArchive.entries(size: archive.data.count, read: TestServer(archive.data).read)
    #expect(entries.map(\.path) == ["ReadMe.txt"])
  }

  @Test func turnsDownWhatIsNotAnArchive() async throws {
    let data = Data((0..<10_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    await #expect(throws: ArchiveReadError.self) {
      try await ZipArchive.entries(size: data.count, read: TestServer(data).read)
    }
  }
}

/// A server with a file on it, sending what's asked for as a download resumed at an offset does:
/// what's there from the offset, up to how much was asked for.
private final class TestServer: @unchecked Sendable {
  let file: Data
  /// As a server that can't resume downloads, which sends the file from its start.
  var ignoresOffsets = false
  private(set) var reads: [(offset: Int, length: Int)] = []

  init(_ file: Data) {
    self.file = file
  }

  func read(_ offset: Int, _ length: Int) async throws -> Data {
    self.reads.append((offset, length))
    let start = self.ignoresOffsets ? 0 : offset
    guard start < self.file.count else {
      return Data()
    }
    return self.file.subdata(in: start..<min(self.file.count, start + length))
  }
}

/// A ZIP archive, laid out as the zip tool lays one out, with each file stored as it is.
private struct TestArchive {
  struct Item {
    var name: [UInt8]
    var size: UInt64
    var isFolder = false
    /// Unix, and ZIP 3.0, as the zip tool on a Mac says.
    var madeBy: UInt16 = 0x031E
    /// Its name's in UTF-8.
    var flags: UInt16 = 0x0800
    var extra = Data()

    init(_ name: String, size: UInt64 = 0, folder: Bool = false) {
      self.name = Array(name.utf8)
      self.size = size
      self.isFolder = folder
    }

    init(bytes: [UInt8], size: UInt64, madeBy: UInt16, flags: UInt16) {
      self.name = bytes
      self.size = size
      self.madeBy = madeBy
      self.flags = flags
    }
  }

  var items: [Item]
  var prefix = Data()
  var comment = Data()
  var zip64 = false

  var data: Data {
    var archive = Data()
    var offsets: [Int] = []
    for item in self.items {
      // Only the beginning of a big one, which is all the list is read with.
      let contents = Data(count: Int(min(item.size, 1_000_000)))
      offsets.append(archive.count)
      archive += Self.bytes(UInt32(0x04034B50), UInt16(20), item.flags, UInt16(0), UInt32(0), UInt32(0))
      archive += Self.bytes(UInt32(contents.count), UInt32(contents.count), UInt16(item.name.count), UInt16(0))
      archive += Data(item.name) + contents
    }

    let listStart = archive.count
    for (item, offset) in zip(self.items, offsets) {
      let large = item.size >= 0xFFFFFFFF
      let extra = item.extra + (large ? Self.field(0x0001, Array(Self.bytes(item.size, item.size))) : Data())
      let attributes: UInt32 = item.isFolder ? 0o040755 << 16 : 0o100644 << 16
      archive += Self.bytes(UInt32(0x02014B50), item.madeBy, UInt16(20), item.flags, UInt16(0), UInt32(0), UInt32(0))
      archive += Self.bytes(large ? UInt32.max : UInt32(item.size), large ? UInt32.max : UInt32(item.size))
      archive += Self.bytes(UInt16(item.name.count), UInt16(extra.count), UInt16(0), UInt16(0), UInt16(0), attributes, UInt32(offset))
      archive += Data(item.name) + extra
    }
    let listSize = archive.count - listStart

    if self.zip64 {
      let record = archive.count
      archive += Self.bytes(UInt32(0x06064B50), UInt64(44), UInt16(45), UInt16(45), UInt32(0), UInt32(0))
      archive += Self.bytes(UInt64(self.items.count), UInt64(self.items.count), UInt64(listSize), UInt64(listStart))
      archive += Self.bytes(UInt32(0x07064B50), UInt32(0), UInt64(record), UInt32(1))
    }
    let count = self.zip64 ? UInt16.max : UInt16(self.items.count)
    archive += Self.bytes(UInt32(0x06054B50), UInt16(0), UInt16(0), count, count)
    archive += Self.bytes(self.zip64 ? UInt32.max : UInt32(listSize), self.zip64 ? UInt32.max : UInt32(listStart), UInt16(self.comment.count))
    return self.prefix + archive + self.comment
  }

  static func field(_ id: UInt16, _ contents: [UInt8]) -> Data {
    self.bytes(id, UInt16(contents.count)) + Data(contents)
  }

  /// Numbers, little end first, as a ZIP archive has them.
  static func bytes(_ numbers: any FixedWidthInteger...) -> Data {
    numbers.reduce(into: Data()) { $0 += self.bytes(of: $1) }
  }

  private static func bytes<Number: FixedWidthInteger>(of number: Number) -> Data {
    withUnsafeBytes(of: number.littleEndian) { Data($0) }
  }
}
