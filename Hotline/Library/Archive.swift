import Foundation

/// Something in an archive, a file or a folder, by its place in it, as "Folder/File.txt".
struct ArchiveEntry: Hashable, Sendable {
  let path: String
  let isFolder: Bool
  /// How big it is once it's out of the archive, both forks of it, for a Mac file.
  let size: UInt64
  /// The type code of a Mac file, which says what it is when its name doesn't.
  var type: String? = nil
}

/// The kinds of archive whose contents can be shown from part of the file, rather than all of it,
/// as they list what's in them at their start, or at their end.
enum ArchiveKind: String, Codable, Sendable {
  case zip
  case compactPro
  case xar
  case installerPackage
  case macBinary
  case binHex
  case diskImage

  /// The kind of archive a file with that extension is, if it's one of these.
  init?(fileExtension: String) {
    switch fileExtension.lowercased() {
    case "zip":
      self = .zip
    case "cpt":
      self = .compactPro
    case "xar":
      self = .xar
    case "pkg":
      self = .installerPackage
    case "bin":
      self = .macBinary
    case "hqx":
      self = .binHex
    case "toast", "cdr", "dsk", "img", "smi":
      self = .diskImage
    default:
      return nil
    }
  }

  /// What one's called, as in "Previewing ZIP file contents".
  var name: String {
    switch self {
    case .zip:
      return "ZIP file"
    case .compactPro:
      return "Compact Pro archive"
    case .xar:
      return "XAR archive"
    case .installerPackage:
      return "installer package"
    case .macBinary:
      return "MacBinary file"
    case .binHex:
      return "BinHex file"
    case .diskImage:
      return "disc image"
    }
  }

  /// How much of the start of one's read first, with how long it is, which is all some need.
  var startLength: Int {
    self == .diskImage ? DiskImage.startLength : 16 * 1024
  }

  /// What's in one `size` long, read through `read`, which gives the `length` bytes of it from
  /// `offset`, and for a disk image, `resourceFork`, which gives its resource fork.
  func entries(size: Int, read: (_ offset: Int, _ length: Int) async throws -> Data, resourceFork: (() async throws -> Data)? = nil) async throws -> [ArchiveEntry] {
    switch self {
    case .zip:
      return try await ZipArchive.entries(size: size, read: read)
    case .compactPro:
      return try await CompactProArchive.entries(size: size, read: read)
    case .xar, .installerPackage:
      return try await XARArchive.entries(size: size, read: read)
    case .macBinary:
      return try await MacBinary.entries(size: size, read: read)
    case .binHex:
      return try await BinHex.entries(size: size, read: read)
    case .diskImage:
      return try await DiskImage.entries(size: size, read: read, resourceFork: resourceFork)
    }
  }
}

enum ArchiveReadError: Error {
  /// It isn't the kind of archive it was taken for.
  case notAnArchive
}

/// The CCITT check XMODEM uses, as MacBinary and BinHex do.
enum CRC16 {
  static func xmodem<Bytes: Sequence>(_ bytes: Bytes) -> UInt16 where Bytes.Element == UInt8 {
    var crc: UInt16 = 0
    for byte in bytes {
      crc ^= UInt16(byte) << 8
      for _ in 0..<8 {
        crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1
      }
    }
    return crc
  }
}

extension Data {
  /// A little-endian number at an offset from the start, or nil if it runs past the end.
  func littleEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
    self.number(type, at: offset, bigEndian: false)
  }

  /// A big-endian number at an offset from the start, or nil if it runs past the end.
  func bigEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
    self.number(type, at: offset, bigEndian: true)
  }

  /// The byte at an offset from the start, or nil if it's past the end.
  func byte(at offset: Int) -> UInt8? {
    guard offset >= 0, offset < self.count else {
      return nil
    }
    return self[self.startIndex + offset]
  }

  func hasSignature(_ signature: [UInt8], at offset: Int) -> Bool {
    guard offset >= 0, offset + signature.count <= self.count else {
      return false
    }
    return self[(self.startIndex + offset)..<(self.startIndex + offset + signature.count)].elementsEqual(signature)
  }

  /// A classic Mac name, in Mac Roman, with any slash in it shown as a colon, as the Mac shows
  /// one, as a slash is what separates folders here.
  func macName(at offset: Int, length: Int) -> String? {
    guard offset >= 0, length >= 0, offset + length <= self.count else {
      return nil
    }
    let name = String(data: self.subdata(in: (self.startIndex + offset)..<(self.startIndex + offset + length)), encoding: .macOSRoman)
    return name?.replacingOccurrences(of: "/", with: ":")
  }

  /// A Mac type or creator code, as four letters, or nil for none, which is four zeros.
  func fourCharCode(at offset: Int) -> String? {
    guard offset >= 0, offset + 4 <= self.count, self.bigEndian(UInt32.self, at: offset) != 0 else {
      return nil
    }
    return String(data: self.subdata(in: (self.startIndex + offset)..<(self.startIndex + offset + 4)), encoding: .macOSRoman)
  }

  private func number<T: FixedWidthInteger>(_ type: T.Type, at offset: Int, bigEndian: Bool) -> T? {
    let size = MemoryLayout<T>.size
    guard offset >= 0, offset + size <= self.count else {
      return nil
    }
    var value: T = 0
    for index in 0..<size {
      let byte = T(self[self.startIndex + offset + index])
      value |= byte << (8 * (bigEndian ? size - 1 - index : index))
    }
    return value
  }
}
