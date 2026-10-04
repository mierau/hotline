import Foundation

/// A Mac file in BinHex, which carries both its forks, and its type and creator, as text. Its name
/// and what it is come first, after a line saying what it is, so the start of it is enough.
enum BinHex {
  /// How much of the start is read: room for whatever's written before the line saying what it is,
  /// and the encoded header after it.
  static let startLength = 16 * 1024

  /// The file in one `size` long, read through `read`, which gives the `length` bytes of it from
  /// `offset`.
  static func entries(size: Int, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    guard let file = self.file(in: Data(try await read(0, min(size, self.startLength)))) else {
      throw ArchiveReadError.notAnArchive
    }
    return [file]
  }

  /// The file the start of a BinHex file is for: after "(This file must be converted with BinHex
  /// 4.0)", from a colon, six bits to a letter, with repeated bytes run together, then the name's
  /// length, the name, a version, its type and creator, Finder flags, its forks' lengths, and a
  /// check of all that.
  static func file(in text: Data) -> ArchiveEntry? {
    guard let line = text.range(of: Data("(This file must be converted with BinHex".utf8)),
          let colon = text[line.upperBound...].firstIndex(of: UInt8(ascii: ":")) else {
      return nil
    }

    var encoded: [UInt8] = []
    var bits: UInt32 = 0
    var bitCount = 0
    for letter in text[(colon + 1)...] {
      if letter == UInt8(ascii: ":") {
        break
      }
      if letter == 0x0D || letter == 0x0A || letter == 0x20 || letter == 0x09 {
        continue
      }
      guard let value = self.values[letter] else {
        return nil
      }
      bits = bits << 6 | UInt32(value)
      bitCount += 6
      if bitCount >= 8 {
        bitCount -= 8
        encoded.append(UInt8(truncatingIfNeeded: bits >> bitCount))
      }
    }

    // 0x90 then a count repeats the byte before it, to that many in all. 0x90 0 is 0x90 itself.
    var bytes: [UInt8] = []
    var index = 0
    while index < encoded.count {
      let byte = encoded[index]
      guard byte == 0x90, index + 1 < encoded.count else {
        bytes.append(byte)
        index += 1
        continue
      }
      let count = Int(encoded[index + 1])
      if count == 0 {
        bytes.append(0x90)
      }
      else if let repeated = bytes.last {
        bytes += repeatElement(repeated, count: count - 1)
      }
      index += 2
    }

    let header = Data(bytes)
    guard let nameLength = header.byte(at: 0).map(Int.init), (1...63).contains(nameLength),
          let name = header.macName(at: 1, length: nameLength) else {
      return nil
    }
    let end = 1 + nameLength + 1 + 4 + 4 + 2 + 4 + 4
    guard let dataLength = header.bigEndian(UInt32.self, at: end - 8),
          let resourceLength = header.bigEndian(UInt32.self, at: end - 4),
          let check = header.bigEndian(UInt16.self, at: end),
          check == CRC16.xmodem(header.prefix(end)) else {
      return nil
    }
    return ArchiveEntry(path: name, isFolder: false, size: UInt64(dataLength) + UInt64(resourceLength), type: header.fourCharCode(at: nameLength + 2))
  }

  /// What each letter BinHex writes with stands for.
  private static let values: [UInt8: UInt8] = {
    let letters = Array("!\"#$%&'()*+,-012345689@ABCDEFGHIJKLMNPQRSTUVXYZ[`abcdefhijklmpqr".utf8)
    return Dictionary(uniqueKeysWithValues: letters.enumerated().map { ($0.element, UInt8($0.offset)) })
  }()
}
