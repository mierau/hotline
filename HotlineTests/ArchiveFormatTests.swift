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
