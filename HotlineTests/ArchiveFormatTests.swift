// ArchiveFormatTests

import Testing
import Foundation
@testable import Hotline

struct ArchiveFormatTests {

  // MARK: - CRC

  @Test func checksLikeXMODEM() {
    #expect(CRC16.xmodem(Array("123456789".utf8)) == 0x31C3)
  }

  // MARK: - Compact Pro

  @Test func readsACompactProArchive() async throws {
    let archive = CompactProArchive.test([
      .folder("My Game", inside: 3),
      .file("Read Me", type: "TEXT", data: 100),
      .folder("Data", inside: 1),
      .file("Level 1", type: "LEVL", data: 300, resource: 50),
      .file("Notes/Ideas", type: "TEXT", data: 20),
    ])
    let server = TestServer(archive)
    let entries = try await ArchiveKind.compactPro.entries(size: archive.count, read: server.read)
    #expect(entries == [
      ArchiveEntry(path: "My Game", isFolder: true, size: 0),
      ArchiveEntry(path: "My Game/Read Me", isFolder: false, size: 100, type: "TEXT"),
      ArchiveEntry(path: "My Game/Data", isFolder: true, size: 0),
      ArchiveEntry(path: "My Game/Data/Level 1", isFolder: false, size: 350, type: "LEVL"),
      ArchiveEntry(path: "Notes:Ideas", isFolder: false, size: 20, type: "TEXT"),
    ])
    // Its first bytes, then its list, after its header and files.
    #expect(server.reads.map(\.offset) == [0, 8 + 2000])
  }

  @Test func turnsDownWhatIsNotCompactPro() async throws {
    let data = Data(repeating: 7, count: 1000)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.compactPro.entries(size: data.count, read: TestServer(data).read)
    }
  }

  // MARK: - XAR

  @Test func readsAXARArchive() async throws {
    let archive = try XARArchive.test(toc: """
      <?xml version="1.0" encoding="UTF-8"?>
      <xar><toc><checksum style="sha1"><offset>0</offset><size>20</size></checksum>
      <file id="1"><name>Resources</name><type>directory</type>
        <file id="2"><name>Welcome.rtf</name><type>file</type>
          <data><length>500</length><size>1200</size><offset>20</offset></data>
          <ea><name>com.apple.quarantine</name><size>57</size></ea>
        </file>
      </file>
      <file id="3"><name>Distribution</name><type>file</type><data><size>3400</size></data></file>
      </toc></xar>
      """)
    let entries = try await ArchiveKind.installerPackage.entries(size: archive.count, read: TestServer(archive).read)
    #expect(entries == [
      ArchiveEntry(path: "Resources", isFolder: true, size: 0),
      ArchiveEntry(path: "Resources/Welcome.rtf", isFolder: false, size: 1200),
      ArchiveEntry(path: "Distribution", isFolder: false, size: 3400),
    ])
  }

  @Test func turnsDownWhatIsNotXAR() async throws {
    let data = Data(repeating: 7, count: 1000)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.xar.entries(size: data.count, read: TestServer(data).read)
    }
  }

  // MARK: - MacBinary

  @Test func readsMacBinaryII() async throws {
    let file = MacBinary.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200)
    let entries = try await ArchiveKind.macBinary.entries(size: file.count, read: TestServer(file).read)
    #expect(entries == [ArchiveEntry(path: "Read Me", isFolder: false, size: 1200, type: "TEXT")])
  }

  @Test func readsMacBinaryIIIByItsSignature() async throws {
    var file = MacBinary.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200)
    file.replaceSubrange(102..<106, with: Array("mBIN".utf8))
    file.replaceSubrange(124..<126, with: [0, 0])
    let entries = try await ArchiveKind.macBinary.entries(size: file.count, read: TestServer(file).read)
    #expect(entries.map(\.path) == ["Read Me"])
  }

  @Test func readsMacBinaryI() async throws {
    var file = MacBinary.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200)
    file.replaceSubrange(122..<126, with: [0, 0, 0, 0])
    let entries = try await ArchiveKind.macBinary.entries(size: file.count, read: TestServer(file).read)
    #expect(entries.map(\.path) == ["Read Me"])
  }

  @Test func turnsDownABinFileThatIsNotMacBinary() async throws {
    var file = MacBinary.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200)
    file[100] = 1
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.macBinary.entries(size: file.count, read: TestServer(file).read)
    }
  }

  @Test func turnsDownForksTooBigForTheFile() async throws {
    let file = MacBinary.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200).prefix(600)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.macBinary.entries(size: file.count, read: TestServer(Data(file)).read)
    }
  }

  // MARK: - BinHex

  @Test func readsBinHex() async throws {
    let file = BinHex.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200)
    let entries = try await ArchiveKind.binHex.entries(size: file.count, read: TestServer(file).read)
    #expect(entries == [ArchiveEntry(path: "Read Me", isFolder: false, size: 1200, type: "TEXT")])
  }

  @Test func readsBinHexAfterAMessage() async throws {
    let file = Data("From the Info-Mac archive.\r\r".utf8) + BinHex.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200)
    let entries = try await ArchiveKind.binHex.entries(size: file.count, read: TestServer(file).read)
    #expect(entries.map(\.path) == ["Read Me"])
  }

  @Test func turnsDownBinHexThatDoesNotCheckOut() async throws {
    let file = BinHex.test(name: "Read Me", type: "TEXT", data: 1000, resource: 200, check: 0x1234)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.binHex.entries(size: file.count, read: TestServer(file).read)
    }
  }

  // MARK: - Disc images

  @Test func readsAnHFSDisc() async throws {
    // Small nodes, so it takes a few leaves, each linked to the next.
    let disc = TestDisc.hfs([
      .file("Read Me", in: 2, type: "TEXT", data: 100, resource: 20),
      .folder("Data", id: 16, in: 2),
      .file("Level 1", in: 16, type: "LEVL", data: 300),
      .file("Level 2", in: 16, type: "LEVL", data: 310),
      .file("Level 3", in: 16, type: "LEVL", data: 320),
      .file("Notes/Ideas", in: 2, type: "TEXT", data: 20),
    ])
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(Set(entries) == [
      ArchiveEntry(path: "Read Me", isFolder: false, size: 120, type: "TEXT"),
      ArchiveEntry(path: "Data", isFolder: true, size: 0),
      ArchiveEntry(path: "Data/Level 1", isFolder: false, size: 300, type: "LEVL"),
      ArchiveEntry(path: "Data/Level 2", isFolder: false, size: 310, type: "LEVL"),
      ArchiveEntry(path: "Data/Level 3", isFolder: false, size: 320, type: "LEVL"),
      ArchiveEntry(path: "Notes:Ideas", isFolder: false, size: 20, type: "TEXT"),
    ])
  }

  @Test func readsAnHFSPlusDiscInAPartitionMap() async throws {
    let disc = TestDisc.inPartitionMap(TestDisc.hfsPlus([
      .folder("Café ☕", id: 16, in: 2),
      .file("Menu", in: 16, type: "TEXT", data: 5_000_000_000, resource: 10),
    ]))
    let server = TestServer(disc)
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: server.read)
    #expect(Set(entries) == [
      ArchiveEntry(path: "Café ☕", isFolder: true, size: 0),
      ArchiveEntry(path: "Café ☕/Menu", isFolder: false, size: 5_000_000_010, type: "TEXT"),
    ])
    // Its start, then its catalog, and nothing else.
    #expect(server.reads.count == 2)
    #expect(server.reads[0].offset == 0)
  }

  @Test func readsADiskCopyImage() async throws {
    // Disk Copy 4.2's header: the disk's name, its sizes and checks, its format, and 0x0100.
    var header = Data([10]) + macRoman("Read Me 1") + Data(count: 54) + Data(count: 16) + Data([0x22, 0x24])
    header += bytes(UInt16(0x0100))
    let disc = header + TestDisc.hfs([.file("Read Me", in: 2, type: "TEXT", data: 100)])
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(entries.map(\.path) == ["Read Me"])
  }

  @Test func leavesOutWhatTheFinderHides() async throws {
    let disc = TestDisc.hfsPlus([
      .file("Read Me", in: 2, type: "TEXT", data: 10),
      .file("Desktop DB", in: 2, type: "BTFL", data: 10, hidden: true),
      .file(".DS_Store", in: 2, type: "", data: 10),
      .folder("Hidden", id: 16, in: 2, hidden: true),
      .file("Inside", in: 16, type: "TEXT", data: 10),
      .folder("Trash", id: 17, in: 2),
      .file("Old Draft", in: 17, type: "TEXT", data: 10),
    ])
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(entries.map(\.path) == ["Read Me"])
  }

  @Test func readsACatalogInPieces() async throws {
    let disc = TestDisc.hfsPlus([.folder("Data", id: 16, in: 2), .file("Read Me", in: 16, type: "TEXT", data: 10)], pieces: 3)
    let server = TestServer(disc)
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: server.read)
    #expect(Set(entries) == [
      ArchiveEntry(path: "Data", isFolder: true, size: 0),
      ArchiveEntry(path: "Data/Read Me", isFolder: false, size: 10, type: "TEXT"),
    ])
    // Its start, then each piece of its catalog.
    #expect(server.reads.count == 4)
  }

  @Test func turnsDownACatalogInTooManyPieces() async throws {
    let disc = TestDisc.hfsPlus([.file("Read Me", in: 2, type: "TEXT", data: 10)], pieces: 5)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    }
  }

  @Test func turnsDownACatalogWithPiecesItsHeaderDoesNotList() async throws {
    let disc = TestDisc.hfsPlus([.file("Read Me", in: 2, type: "TEXT", data: 10)], pieces: 3, listedPieces: 2)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    }
  }

  @Test func readsAPCDiscByItsJolietNames() async throws {
    let disc = TestISO.disc(TestISO.mixes, joliet: true)
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(Set(entries) == TestISO.mixesEntries)
  }

  @Test func readsAPCDiscWithoutLongNames() async throws {
    let disc = TestISO.disc([.folder("DATA"), .file("README.TXT;1", size: 100), .file("DATA/LEVEL1.MAP;1", size: 300), .file("NOTES.;1", size: 20)], joliet: false)
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(Set(entries) == [
      ArchiveEntry(path: "DATA", isFolder: true, size: 0),
      ArchiveEntry(path: "README.TXT", isFolder: false, size: 100),
      ArchiveEntry(path: "DATA/LEVEL1.MAP", isFolder: false, size: 300),
      ArchiveEntry(path: "NOTES", isFolder: false, size: 20),
    ])
  }

  @Test func readsADiscSavedInRawSectors() async throws {
    let disc = TestISO.raw(TestISO.disc(TestISO.mixes, joliet: true))
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(Set(entries) == TestISO.mixesEntries)
  }

  @Test func readsAMacDiscSavedInRawSectors() async throws {
    var volume = TestDisc.hfs([.file("Read Me", in: 2, type: "TEXT", data: 100)])
    volume += Data(count: (2048 - volume.count % 2048) % 2048)
    let disc = TestISO.raw(volume)
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(entries == [ArchiveEntry(path: "Read Me", isFolder: false, size: 100, type: "TEXT")])
  }

  @Test func turnsDownAPCDiscWhoseFolderIsElsewhere() async throws {
    // The path table's second folder, after the disc's own, 10 bytes in, said to be past the end.
    var disc = TestISO.disc(TestISO.mixes, joliet: true)
    disc.replaceSubrange((20 * 2048 + 12)..<(20 * 2048 + 16), with: withUnsafeBytes(of: UInt32(50_000).littleEndian) { Data($0) })
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    }
  }

  @Test func leavesOutHiddenFilesOnAPCDisc() async throws {
    let disc = TestISO.disc([.file("Read Me.txt", size: 10), .file("Autorun.inf", size: 10, hidden: true)], joliet: true)
    let entries = try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    #expect(entries.map(\.path) == ["Read Me.txt"])
  }

  // MARK: - Disk Copy 6

  @Test func expandsApplesDataCompression() {
    // "ABC" as it is, three bytes from three back, then five of the byte just before.
    let compressed = Data([0x82, 0x41, 0x42, 0x43, 0x00, 0x02, 0x41, 0x00, 0x00])
    #expect(DiskCopyImage.expand(compressed, to: 11) == Data("ABCABCCCCCC".utf8))
    // From further back than there is.
    #expect(DiskCopyImage.expand(Data([0x80, 0x41, 0x00, 0x05]), to: 4) == nil)
  }

  @Test func expandsStuffItAsShrinkWrapCompressesAChunk() {
    #expect(DiskCopyImage.expandStuffIt(TestDiskCopy.stuffItChunk, to: 1024) == TestDiskCopy.stuffItText)
    // Cut short, or not as long as it's meant to be.
    #expect(DiskCopyImage.expandStuffIt(TestDiskCopy.stuffItChunk.dropLast(8), to: 1024) == nil)
    #expect(DiskCopyImage.expandStuffIt(TestDiskCopy.stuffItChunk, to: 512) == nil)
    // Four bytes copied from one back, before there's anything to copy.
    let copyFirst = Data([
      0x36, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
      0x05, 0xFE, 0xED, 0xDF, 0xFE, 0xED, 0xAF, 0xE0, 0xDF, 0xFE, 0xED, 0xDF, 0xFE, 0xED, 0xDF, 0xFE,
      0xED, 0xDF, 0xFE, 0xED, 0xDF, 0xFE, 0xED, 0xDF, 0xEE, 0x0E, 0xFE, 0xED, 0x0E, 0x43, 0x05, 0xE2,
      0xE2, 0x1E, 0x11, 0x33, 0xEC, 0x01,
    ])
    #expect(DiskCopyImage.expandStuffIt(copyFirst, to: 5) == nil)
  }

  @Test func readsAChunkCompressedWithStuffIt() async throws {
    let chunk = TestDiskCopy.stuffItChunk
    let resourceFork = TestDiskCopy.resourceFork([(0, 0xF0, 0, chunk.count), (2, 0xFF, chunk.count, 0)])
    let image = try #require(DiskCopyImage(resourceFork: resourceFork, dataSize: chunk.count))
    #expect(try await image.read(0, 1024, from: TestServer(chunk).read) == TestDiskCopy.stuffItText)
    #expect(try await image.read(1000, 24, from: TestServer(chunk).read) == TestDiskCopy.stuffItText.suffix(24))
  }

  @Test func expandsKenCodeAsDiskCopyCompressesAChunk() {
    #expect(DiskCopyImage.expandKenCode(TestDiskCopy.kenCodeChunk, to: 2048) == TestDiskCopy.kenCodeText)
    // Cut short.
    #expect(DiskCopyImage.expandKenCode(TestDiskCopy.kenCodeChunk.dropLast(2), to: 2048) == nil)
    // A run of two zeros, which is longer than one.
    #expect(DiskCopyImage.expandKenCode(Data([0x20, 0x00, 0x00]), to: 2) == Data(count: 2))
    #expect(DiskCopyImage.expandKenCode(Data([0x20, 0x00, 0x00]), to: 1) == nil)
    // Three bytes copied from one back, before there's anything to copy.
    #expect(DiskCopyImage.expandKenCode(Data([0x40]), to: 3) == nil)
  }

  @Test func readsAChunkCompressedWithKenCode() async throws {
    let chunk = TestDiskCopy.kenCodeChunk
    let resourceFork = TestDiskCopy.resourceFork([(0, 0x80, 0, chunk.count), (4, 0xFF, chunk.count, 0)])
    let image = try #require(DiskCopyImage(resourceFork: resourceFork, dataSize: chunk.count))
    #expect(try await image.read(0, 2048, from: TestServer(chunk).read) == TestDiskCopy.kenCodeText)
    #expect(try await image.read(1662, 16, from: TestServer(chunk).read) == Data("end of the chunk".utf8))
  }

  @Test func readsChunksFromWhereTheMapSaysTheyStart() async throws {
    let data = Data(repeating: 0xEE, count: 100) + TestDiskCopy.stuffItChunk
    let chunk = TestDiskCopy.stuffItChunk
    let resourceFork = TestDiskCopy.resourceFork([(0, 0xF0, 0, chunk.count), (2, 0xFF, chunk.count, 0)], dataOffset: 100)
    let image = try #require(DiskCopyImage(resourceFork: resourceFork, dataSize: data.count))
    #expect(try await image.read(0, 1024, from: TestServer(data).read) == TestDiskCopy.stuffItText)
  }

  @Test func readsADiskCopyImageInChunks() async throws {
    let image = TestDiskCopy.image(TestDisc.hfs([
      .file("Install ShrinkWrap™ 3.5.1", in: 2, type: "APPL", data: 1_243_290),
      .folder("Extras", id: 16, in: 2),
      .file("serial", in: 16, type: "TEXT", data: 388),
    ]))
    let entries = try await ArchiveKind.diskImage.entries(size: image.data.count, read: TestServer(image.data).read) {
      image.resourceFork
    }
    #expect(Set(entries) == [
      ArchiveEntry(path: "Install ShrinkWrap™ 3.5.1", isFolder: false, size: 1_243_290, type: "APPL"),
      ArchiveEntry(path: "Extras", isFolder: true, size: 0),
      ArchiveEntry(path: "Extras/serial", isFolder: false, size: 388, type: "TEXT"),
    ])
  }

  @Test func turnsDownAChunkedImageWithoutItsMap() async throws {
    let image = TestDiskCopy.image(TestDisc.hfs([.file("Read Me", in: 2, type: "TEXT", data: 100)]))
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.diskImage.entries(size: image.data.count, read: TestServer(image.data).read) {
        Data()
      }
    }
  }

  @Test func turnsDownChunksCompressedAnotherWay() async throws {
    let image = TestDiskCopy.image(TestDisc.hfs([.file("Read Me", in: 2, type: "TEXT", data: 100)]), compression: 0x81)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.diskImage.entries(size: image.data.count, read: TestServer(image.data).read) {
        image.resourceFork
      }
    }
  }

  @Test func turnsDownADiscWithoutAMacVolume() async throws {
    let disc = Data(count: 200_000)
    await #expect(throws: ArchiveReadError.self) {
      try await ArchiveKind.diskImage.entries(size: disc.count, read: TestServer(disc).read)
    }
  }
}

/// A server with a file on it, sending what's asked for as a download resumed at an offset does.
private final class TestServer: @unchecked Sendable {
  let file: Data
  private(set) var reads: [(offset: Int, length: Int)] = []

  init(_ file: Data) {
    self.file = file
  }

  func read(_ offset: Int, _ length: Int) async throws -> Data {
    self.reads.append((offset, length))
    guard offset < self.file.count else {
      return Data()
    }
    return self.file.subdata(in: offset..<min(self.file.count, offset + length))
  }
}

/// Numbers, big end first, as the Mac's formats have them.
private func bytes(_ numbers: any FixedWidthInteger...) -> Data {
  numbers.reduce(into: Data()) { $0 += bytes(of: $1) }
}

private func bytes<Number: FixedWidthInteger>(of number: Number) -> Data {
  withUnsafeBytes(of: number.bigEndian) { Data($0) }
}

private func macRoman(_ text: String) -> Data {
  text.data(using: .macOSRoman)!
}

private extension CompactProArchive {
  enum Entry {
    case folder(String, inside: Int)
    case file(String, type: String, data: UInt32, resource: UInt32 = 0)
  }

  /// An archive: its header, room where the files would be, and its list, at the end.
  static func test(_ entries: [Entry]) -> Data {
    var list = bytes(UInt32(0), UInt16(entries.count)) + Data([0])
    for entry in entries {
      switch entry {
      case .folder(let name, let inside):
        list += Data([0x80 | UInt8(name.count)]) + macRoman(name) + bytes(UInt16(inside))
      case .file(let name, let type, let data, let resource):
        list += Data([UInt8(name.count)]) + macRoman(name)
        list += Data([1]) + bytes(UInt32(8)) + macRoman(type) + macRoman("CPCT") + bytes(UInt32(0), UInt32(0), UInt16(0))
        list += bytes(UInt32(0), UInt16(0), resource, data, resource, data)
      }
    }
    let files = Data(repeating: 0x55, count: 2000)
    return Data([1, 1, 0, 0]) + bytes(UInt32(8 + files.count)) + files + list
  }
}

private extension XARArchive {
  /// An archive with that list, and nothing in it.
  static func test(toc: String) throws -> Data {
    let xml = Data(toc.utf8)
    let deflated = try (xml as NSData).compressed(using: .zlib) as Data
    let list = Data([0x78, 0x9C]) + deflated + Data([0, 0, 0, 0])
    return Data("xar!".utf8) + bytes(UInt16(28), UInt16(1), UInt64(list.count), UInt64(xml.count), UInt32(1)) + list
  }
}

private extension MacBinary {
  /// A file in MacBinary II, with its forks, padded to 128 bytes each.
  static func test(name: String, type: String, data: UInt32, resource: UInt32) -> Data {
    var header = Data(count: 128)
    header[1] = UInt8(name.count)
    header.replaceSubrange(2..<(2 + name.count), with: macRoman(name))
    header.replaceSubrange(65..<69, with: macRoman(type))
    header.replaceSubrange(69..<73, with: macRoman("ttxt"))
    header.replaceSubrange(83..<87, with: bytes(data))
    header.replaceSubrange(87..<91, with: bytes(resource))
    header[122] = 129
    header[123] = 129
    header.replaceSubrange(124..<126, with: bytes(CRC16.xmodem(header.prefix(124))))
    let padded = { (length: UInt32) in Int((length + 127) / 128 * 128) }
    return header + Data(count: padded(data) + padded(resource))
  }
}

private extension BinHex {
  /// A file in BinHex: its header and forks, with runs of a byte run together, in letters, on
  /// lines of 64, after the line saying what it is.
  static func test(name: String, type: String, data: UInt32, resource: UInt32, check: UInt16? = nil) -> Data {
    var header = Data([UInt8(name.count)]) + macRoman(name) + Data([0]) + macRoman(type) + macRoman("ttxt")
    header += bytes(UInt16(0x0100), data, resource)
    header += bytes(check ?? CRC16.xmodem(header))
    let forks = Data(repeating: 0x41, count: Int(data)) + bytes(UInt16(0)) + Data(repeating: 0x90, count: Int(resource)) + bytes(UInt16(0))
    let plain = header + forks

    // A run of 3 to 255 of a byte is the byte, 0x90, and how many. 0x90 itself is 0x90 0.
    var runs: [UInt8] = []
    var index = plain.startIndex
    while index < plain.endIndex {
      let byte = plain[index]
      var length = 1
      while index + length < plain.endIndex && plain[index + length] == byte && length < 255 {
        length += 1
      }
      runs += byte == 0x90 ? [0x90, 0] : [byte]
      if length >= 3 {
        runs += [0x90, UInt8(length)]
      }
      else if length == 2 {
        runs += byte == 0x90 ? [0x90, 0] : [byte]
      }
      index += length
    }

    let letters = Array("!\"#$%&'()*+,-012345689@ABCDEFGHIJKLMNPQRSTUVXYZ[`abcdefhijklmpqr".utf8)
    var text: [UInt8] = []
    var bits: UInt32 = 0
    var bitCount = 0
    for byte in runs {
      bits = bits << 8 | UInt32(byte)
      bitCount += 8
      while bitCount >= 6 {
        bitCount -= 6
        text.append(letters[Int((bits >> bitCount) & 0x3F)])
      }
    }
    if bitCount > 0 {
      text.append(letters[Int((bits << (6 - bitCount)) & 0x3F)])
    }
    var lines = Data("(This file must be converted with BinHex 4.0)\r\r:".utf8)
    for (index, letter) in text.enumerated() {
      lines.append(letter)
      if (index + 2) % 64 == 0 {
        lines.append(0x0D)
      }
    }
    return lines + Data(":\r".utf8)
  }
}

/// A Mac disc, as it is in an image of it: a volume header, and a catalog, as a B-tree, with a
/// record for the volume's folder, one saying what's at its ID, and one for each thing on it.
private enum TestDisc {
  enum Item {
    case folder(String, id: UInt32, in: UInt32, hidden: Bool = false)
    case file(String, in: UInt32, type: String, data: UInt64, resource: UInt64 = 0, hidden: Bool = false)
  }

  static func hfs(_ items: [Item]) -> Data {
    let records = self.records(items) { name, parent in
      let name = macRoman(name)
      var key = Data([UInt8(6 + name.count), 0]) + bytes(parent) + Data([UInt8(name.count)]) + name
      key += Data(count: key.count % 2)
      return key
    } folder: { id, flags in
      Data([1, 0]) + bytes(UInt16(0), UInt16(0), id) + Data(count: 12) + Data(count: 8) + bytes(flags) + Data(count: 6 + 32)
    } file: { type, flags, data, resource in
      var record = Data([2, 0, 0, 0]) + self.code(type) + macRoman("ttxt") + bytes(flags) + Data(count: 6)
      record += bytes(UInt32(0), UInt16(0), UInt32(data), UInt32(0), UInt16(0), UInt32(resource), UInt32(0))
      return record + Data(count: 12 + 16 + 2 + 24 + 4)
    } thread: { parent in
      Data([3, 0]) + Data(count: 8) + bytes(parent) + Data(count: 32)
    }
    let catalog = self.catalog(records, nodeSize: 512)
    // Boot blocks, then the header: 512-byte allocation blocks, from the fourth 512-byte block,
    // where the catalog is, in one piece.
    var header = Data(count: 512)
    header.replaceSubrange(0..<2, with: bytes(UInt16(0x4244)))
    header.replaceSubrange(0x14..<0x18, with: bytes(UInt32(512)))
    header.replaceSubrange(0x1C..<0x1E, with: bytes(UInt16(4)))
    header.replaceSubrange(0x92..<0x96, with: bytes(UInt32(catalog.count)))
    header.replaceSubrange(0x96..<0x9A, with: bytes(UInt16(0), UInt16(catalog.count / 512)))
    return Data(count: 1024) + header + Data(count: 512) + catalog
  }

  /// In `pieces` pieces, of which its header lists `listedPieces`, the rest being listed, on a real
  /// disk, in another file.
  static func hfsPlus(_ items: [Item], pieces: Int = 1, listedPieces: Int? = nil) -> Data {
    let records = self.records(items) { name, parent in
      let name = name.data(using: .utf16BigEndian)!
      return bytes(UInt16(6 + name.count), parent, UInt16(name.count / 2)) + name
    } folder: { id, flags in
      bytes(UInt16(1), UInt16(0), UInt32(0), id) + Data(count: 20 + 16 + 8) + bytes(flags) + Data(count: 6 + 16 + 8)
    } file: { type, flags, data, resource in
      var record = bytes(UInt16(2), UInt16(0), UInt32(0), UInt32(100)) + Data(count: 20 + 16)
      record += self.code(type) + macRoman("ttxt") + bytes(flags) + Data(count: 6 + 16 + 8)
      record += bytes(data) + Data(count: 72) + bytes(resource) + Data(count: 72)
      return record
    } thread: { parent in
      bytes(UInt16(3), UInt16(0), parent, UInt16(0))
    }
    var catalog = self.catalog(records, nodeSize: 4096)
    // At least a node for each piece, the extra ones unused.
    catalog += Data(count: max(0, pieces - catalog.count / 4096) * 4096)
    let nodes = catalog.count / 4096

    // The first 4096-byte block, for the header, then each piece, after a block between them.
    var disc = Data(count: 4096)
    var extents = Data()
    var node = 0
    for piece in 0..<pieces {
      let count = nodes / pieces + (piece < nodes % pieces ? 1 : 0)
      disc += Data(count: 4096)
      if piece < (listedPieces ?? pieces) {
        extents += bytes(UInt32(disc.count / 4096), UInt32(count))
      }
      disc += catalog.subdata(in: (node * 4096)..<((node + count) * 4096))
      node += count
    }

    var header = Data(count: 512)
    header.replaceSubrange(0..<2, with: bytes(UInt16(0x482B)))
    header.replaceSubrange(40..<44, with: bytes(UInt32(4096)))
    header.replaceSubrange(272..<280, with: bytes(UInt64(catalog.count)))
    header.replaceSubrange(288..<(288 + extents.count), with: extents)
    disc.replaceSubrange(1024..<1536, with: header)
    return disc
  }

  /// In an Apple partition map, written as a CD's are: blocks of 2048 bytes, it says, but its
  /// entries 512 bytes apart, and the volume in 512-byte blocks, from the 64th.
  static func inPartitionMap(_ volume: Data) -> Data {
    func entry(start: UInt32, count: UInt32, name: String, type: String) -> Data {
      var entry = bytes(UInt16(0x504D), UInt16(0), UInt32(2), start, count)
      entry += macRoman(name) + Data(count: 32 - name.count) + macRoman(type) + Data(count: 32 - type.count)
      return entry + Data(count: 512 - entry.count)
    }
    var map = bytes(UInt16(0x4552), UInt16(2048)) + Data(count: 508)
    map += entry(start: 1, count: 63, name: "Apple", type: "Apple_partition_map")
    map += entry(start: 64, count: UInt32(volume.count / 512), name: "Disc", type: "Apple_HFS")
    return map + Data(count: 64 * 512 - map.count) + volume
  }

  private static func code(_ type: String) -> Data {
    type.isEmpty ? Data(count: 4) : macRoman(type)
  }

  /// The records, keyed, in the order the catalog has them: the volume's folder, what's at its
  /// ID, and then what's on it.
  private static func records(
    _ items: [Item],
    key: (String, UInt32) -> Data,
    folder: (UInt32, UInt16) -> Data,
    file: (String, UInt16, UInt64, UInt64) -> Data,
    thread: (UInt32) -> Data
  ) -> [Data] {
    var records = [key("Test CD", 1) + folder(2, 0), key("", 2) + thread(1)]
    for item in items {
      switch item {
      case .folder(let name, let id, let parent, let hidden):
        records.append(key(name, parent) + folder(id, hidden ? 0x4000 : 0))
      case .file(let name, let parent, let type, let data, let resource, let hidden):
        records.append(key(name, parent) + file(type, hidden ? 0x4000 : 0, data, resource))
      }
    }
    return records
  }

  /// A B-tree of them: a header node, then leaf nodes, as many as they take, each linked to the
  /// next, with where each record is at the end of its node.
  private static func catalog(_ records: [Data], nodeSize: Int) -> Data {
    var leaves: [[Data]] = [[]]
    for record in records {
      let used = 14 + leaves[leaves.count - 1].reduce(0) { $0 + $1.count } + 2 * (leaves[leaves.count - 1].count + 2)
      if used + record.count > nodeSize {
        leaves.append([])
      }
      leaves[leaves.count - 1].append(record)
    }
    var header = bytes(UInt32(0), UInt32(0)) + Data([1, 0]) + bytes(UInt16(3), UInt16(0))
    header += bytes(UInt16(1), UInt32(1), UInt32(records.count), UInt32(1), UInt32(leaves.count), UInt16(nodeSize))
    var catalog = header + Data(count: nodeSize - header.count)
    for (index, leaf) in leaves.enumerated() {
      let next = index + 1 < leaves.count ? UInt32(index + 2) : 0
      var node = bytes(next, UInt32(index)) + Data([0xFF, 1]) + bytes(UInt16(leaf.count), UInt16(0))
      var offsets: [UInt16] = []
      for record in leaf {
        offsets.append(UInt16(node.count))
        node += record
      }
      offsets.append(UInt16(node.count))
      node += Data(count: nodeSize - node.count - 2 * offsets.count)
      for offset in offsets.reversed() {
        node += bytes(offset)
      }
      catalog += node
    }
    return catalog
  }
}

/// A PC disc: its volume descriptors from the 16th sector, the primary one, maybe Joliet's, and the
/// last, then its path table, and each folder's list of what's in it, a sector each, one after
/// another.
private enum TestISO {
  enum Item {
    case folder(String)
    case file(String, size: UInt32, hidden: Bool = false)
  }

  static let mixes: [Item] = [
    .folder("mixes"),
    .folder("mixes/blue room"),
    .file("content.html", size: 3186),
    .file("mixes/blue room/1999.mp3", size: 7_216_313),
    .file("mixes/blue room/Richard Hinge Generate 2000.mp3", size: 5_710_426),
  ]

  static let mixesEntries: Set<ArchiveEntry> = [
    ArchiveEntry(path: "mixes", isFolder: true, size: 0),
    ArchiveEntry(path: "mixes/blue room", isFolder: true, size: 0),
    ArchiveEntry(path: "content.html", isFolder: false, size: 3186),
    ArchiveEntry(path: "mixes/blue room/1999.mp3", isFolder: false, size: 7_216_313),
    ArchiveEntry(path: "mixes/blue room/Richard Hinge Generate 2000.mp3", isFolder: false, size: 5_710_426),
  ]

  static func disc(_ items: [Item], joliet: Bool) -> Data {
    let name = { (text: String) in joliet ? text.data(using: .utf16BigEndian)! : Data(text.utf8) }
    // Folders: the disc's own, then each, after the one it's in, a sector each from the 22nd.
    var folders = [""]
    for case .folder(let path) in items {
      folders.append(path)
    }
    let extent = { (folder: String) in UInt32(22 + folders.firstIndex(of: folder)!) }
    let parentOf = { (path: String) in (path as NSString).deletingLastPathComponent }

    var table = Data()
    for (index, folder) in folders.enumerated() {
      let folderName = index == 0 ? Data([0]) : name((folder as NSString).lastPathComponent)
      let parent = index == 0 ? 1 : folders.firstIndex(of: parentOf(folder))! + 1
      table += Data([UInt8(folderName.count), 0]) + le(extent(folder)) + le(UInt16(parent)) + folderName
      table += Data(count: folderName.count % 2)
    }

    var lists = Data()
    for folder in folders {
      var list = self.record(Data([0]), extent: extent(folder), size: 2048, flags: 0x02)
      list += self.record(Data([1]), extent: extent(folder.isEmpty ? "" : parentOf(folder)), size: 2048, flags: 0x02)
      for item in items {
        switch item {
        case .folder(let path) where parentOf(path) == folder:
          list += self.record(name((path as NSString).lastPathComponent), extent: extent(path), size: 2048, flags: 0x02)
        case .file(let path, let size, let hidden) where parentOf(path) == folder:
          list += self.record(name((path as NSString).lastPathComponent), extent: 100, size: size, flags: hidden ? 0x01 : 0)
        default:
          break
        }
      }
      lists += list + Data(count: 2048 - list.count)
    }

    func descriptor(_ type: UInt8, escape: [UInt8] = []) -> Data {
      var sector = Data([type]) + Data("CD001".utf8) + Data([1]) + Data(count: 2041)
      sector.replaceSubrange(88..<(88 + escape.count), with: escape)
      sector.replaceSubrange(128..<136, with: le(UInt16(2048)) + Data([0x08, 0x00]) + le(UInt32(table.count)))
      sector.replaceSubrange(140..<144, with: le(UInt32(20)))
      sector.replaceSubrange(156..<190, with: self.record(Data([0]), extent: 22, size: 2048, flags: 0x02))
      return sector
    }
    var disc = Data(count: 16 * 2048) + descriptor(1)
    disc += joliet ? descriptor(2, escape: [0x25, 0x2F, 0x45]) : Data([0]) + Data("CD001".utf8) + Data([1]) + Data(count: 2041)
    disc += Data([255]) + Data("CD001".utf8) + Data([1]) + Data(count: 2041)
    disc += Data(count: 2048)
    disc += table + Data(count: 2 * 2048 - table.count)
    return disc + lists + Data(count: 100 * 2048)
  }

  /// The disc as it's written, in Mode 2: each sector's sync, its place, as minutes, seconds and
  /// frames, and its mode, a subheader, its data, and room for error correction.
  static func raw(_ disc: Data) -> Data {
    var raw = Data()
    for (index, start) in stride(from: 0, to: disc.count, by: 2048).enumerated() {
      let frame = index + 150
      let place = [frame / 4500, frame / 75 % 60, frame % 75].map { UInt8(($0 / 10) << 4 | $0 % 10) }
      raw += Data([0x00] + Array(repeating: 0xFF, count: 10) + [0x00]) + Data(place) + Data([2]) + Data(count: 8)
      raw += disc.subdata(in: start..<(start + 2048)) + Data(count: 280)
    }
    return raw
  }

  private static func record(_ name: Data, extent: UInt32, size: UInt32, flags: UInt8) -> Data {
    var record = Data([0, 0]) + le(extent) + bytes(extent) + le(size) + bytes(size) + Data(count: 7) + Data([flags, 0, 0])
    record += le(UInt16(1)) + bytes(UInt16(1)) + Data([UInt8(name.count)]) + name
    record += Data(count: record.count % 2)
    record[0] = UInt8(record.count)
    return record
  }

  private static func le<Number: FixedWidthInteger>(_ number: Number) -> Data {
    withUnsafeBytes(of: number.littleEndian) { Data($0) }
  }
}

/// A disk in Disk Copy 6's chunks: its first five sectors kept as they are, the rest compressed,
/// and an empty stretch after it left out, with their map in a resource fork.
private enum TestDiskCopy {
  static func image(_ disk: Data, compression: UInt8 = 0x83) -> (data: Data, resourceFork: Data) {
    var disk = disk
    disk += Data(count: (512 - disk.count % 512) % 512)
    let sectors = disk.count / 512
    let compressed = self.compress(disk.subdata(in: 2560..<disk.count))
    let data = disk.prefix(2560) + compressed

    return (data, self.resourceFork([
      (0, 0x02, 0, 2560),
      (5, compression, 2560, compressed.count),
      (sectors, 0x00, 0, 0),
      (sectors + 1000, 0xFF, data.count, 0),
    ]))
  }

  /// The map of a disk's chunks, in a resource fork: where each starts, how it's kept, and where it
  /// is in the data fork, after `dataOffset`, and how long, the last being the end.
  static func resourceFork(_ chunks: [(sector: Int, kind: UInt8, offset: Int, length: Int)], dataOffset: Int = 0) -> Data {
    var map = bytes(UInt16(11), UInt16(0)) + Data([10]) + macRoman("ShrinkWrap") + Data(count: 53)
    map += bytes(UInt32(chunks.last?.sector ?? 0), UInt32(0), UInt32(dataOffset)) + Data(count: 44)
    map += bytes(UInt32(chunks.count))
    for chunk in chunks {
      map += bytes(UInt32(chunk.sector << 8 | Int(chunk.kind)), UInt32(chunk.offset), UInt32(chunk.length))
    }

    // The resource fork: its header, room after it, the map's data, then its map, with one type,
    // 'bcem', and one of it, 128.
    let resourceData = bytes(UInt32(map.count)) + map
    let header = bytes(UInt32(256), UInt32(256 + resourceData.count), UInt32(resourceData.count), UInt32(50))
    var resourceMap = header + Data(count: 8) + bytes(UInt16(28), UInt16(50))
    resourceMap += bytes(UInt16(0)) + macRoman("bcem") + bytes(UInt16(0), UInt16(10))
    resourceMap += bytes(UInt16(128), UInt16(0xFFFF), UInt32(0), UInt32(0))
    return header + Data(count: 240) + resourceData + resourceMap
  }

  /// A kilobyte, as ShrinkWrap compresses a chunk with StuffIt: the codes for bytes and copies with
  /// their lengths as they are, the codes for how far back with codes of their own for theirs, and
  /// copies of 16 bytes from 9 back, 980 from 1 back, and 8 from 990 back.
  static let stuffItText = Data("Hotline, Hotline, Hotline!\r".utf8) + Data(count: 981) + Data("Hotline! ShrinkW".utf8)
  static let stuffItChunk = Data([
    0x54, 0x00, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0xFF,
    0x05, 0xE4, 0x8F, 0xE4, 0xDF, 0x3E, 0xE4, 0x6F, 0xE4, 0xDF, 0xFE, 0x46, 0xFE, 0x46, 0xEE, 0x4E,
    0xFE, 0x49, 0xEE, 0x34, 0x4E, 0xE3, 0x32, 0xEE, 0xE3, 0xE3, 0xDF, 0xFE, 0xED, 0xDF, 0xFE, 0xED,
    0xDF, 0xFE, 0xED, 0xDF, 0xFE, 0xED, 0x3F, 0xE3, 0x3E, 0xFE, 0x37, 0x43, 0x05, 0x13, 0xE3, 0xEE,
    0x20, 0x91, 0x75, 0xF6, 0x53, 0xD9, 0x02, 0xB7, 0x27, 0x71, 0xC6, 0x6A, 0x0E, 0x5D, 0xE1, 0x3D,
    0xDF, 0x91, 0xC0, 0xFE,
  ])

  /// Two kilobytes, as Disk Copy compresses a chunk with KenCode: runs of all sorts of lengths, the
  /// longest with another after it, copies after short runs, a copy of 1,100, and copies from near,
  /// further and furthest back, one of them 1,646 bytes in, where Disk Copy takes a bit more for
  /// how far back than it needs.
  static let kenCodeText: Data = {
    var text = Data("Hotline, Hotline, Hotline,!\r".utf8) + Data("Hot".utf8) + Data(0x80...0xBE) + Data(count: 1101)
    text += Data("ShrinkWrapHotline 3.5".utf8) + Data(count: 430) + Data("Hotline, Hotline".utf8)
    return text + Data("end of the chunk".utf8) + Data(count: 370)
  }()
  static let kenCodeChunk = Data([
    0x38, 0xA4, 0x37, 0xBA, 0x36, 0x34, 0xB7, 0x32, 0x96, 0x10, 0x73, 0xF2, 0x10, 0x86, 0x9F, 0x3F,
    0xF8, 0x08, 0x18, 0x28, 0x38, 0x48, 0x58, 0x68, 0x78, 0x88, 0x98, 0xA8, 0xB8, 0xC8, 0xD8, 0xE8,
    0xF9, 0x09, 0x19, 0x29, 0x39, 0x49, 0x59, 0x69, 0x79, 0x89, 0x99, 0xA9, 0xB9, 0xC9, 0xD9, 0xE9,
    0xFA, 0x0A, 0x1A, 0x2A, 0x3A, 0x4A, 0x5A, 0x6A, 0x7A, 0x8A, 0x9A, 0xAA, 0xBA, 0xCA, 0xDA, 0xEA,
    0xFB, 0x0B, 0x1B, 0x2B, 0x3B, 0x4B, 0x5B, 0x6B, 0x7B, 0x8B, 0x9B, 0xAB, 0xBB, 0xCB, 0xDB, 0xE0,
    0x01, 0xFF, 0x89, 0xC0, 0x39, 0x29, 0xB4, 0x39, 0x34, 0xB7, 0x35, 0xAB, 0xB9, 0x30, 0xB8, 0x5F,
    0x1A, 0x18, 0x20, 0x33, 0x2E, 0x35, 0xFF, 0x58, 0x6B, 0x3F, 0x3D, 0xF6, 0x9E, 0x06, 0x56, 0xE6,
    0x42, 0x06, 0xF6, 0x62, 0x07, 0x46, 0x86, 0x52, 0x06, 0x36, 0x87, 0x56, 0xE6, 0xBF, 0xF3, 0xA6,
    0xD6, 0xC0,
  ])

  /// Apple Data Compression: a run of a byte, after one like it, as copies of the byte before, and
  /// anything else as it is.
  private static func compress(_ data: Data) -> Data {
    let bytes = [UInt8](data)
    var output = Data()
    var literal: [UInt8] = []
    func flush() {
      for start in stride(from: 0, to: literal.count, by: 128) {
        let run = literal[start..<min(literal.count, start + 128)]
        output += Data([0x80 | UInt8(run.count - 1)]) + Data(run)
      }
      literal = []
    }
    var index = 0
    while index < bytes.count {
      var run = 1
      while index + run < bytes.count && bytes[index + run] == bytes[index] && run < 67 {
        run += 1
      }
      if run >= 4 && (index > 0 && bytes[index - 1] == bytes[index]) {
        flush()
        output += Data([0x40 | UInt8(run - 4), 0, 0])
        index += run
      }
      else {
        literal.append(bytes[index])
        index += 1
      }
    }
    flush()
    return output
  }
}
