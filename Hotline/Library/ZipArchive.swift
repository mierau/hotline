import Foundation

/// Something in an archive, a file or a folder, by its place in it, as "Folder/File.txt".
struct ArchiveEntry: Hashable, Sendable {
  let path: String
  let isFolder: Bool
  /// How big it is once it's out of the archive.
  let size: UInt64
}

/// The list of what's in a ZIP archive, which comes after everything in it, at the end of the file.
/// So it can be read from a server with just the end of the file, rather than all of it.
enum ZipArchive {
  enum ReadError: Error {
    /// The end of the file isn't the end of a ZIP archive.
    case notAnArchive
  }

  /// How much of the end of a file is read first: enough for the record that ends an archive,
  /// with the longest comment it can have, and the list of a few thousand files before it.
  static let endLength = 256 * 1024

  /// What's in an archive `size` long, read through `read`, which gives the `length` bytes of it
  /// from `offset`.
  static func entries(size: Int, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    // Its end, where its list is.
    let offset = max(0, size - self.endLength)
    let tail = Data(try await read(offset, size - offset))
    guard tail.count == size - offset, let record = EndRecord(in: tail) else {
      throw ReadError.notAnArchive
    }
    // Back from the record, where the list ends, rather than where the record says the list
    // starts, which doesn't count anything before the archive, like a program that unpacks it.
    let listStart = offset + record.listEnd - record.listSize
    guard listStart >= 0 else {
      throw ReadError.notAnArchive
    }
    if listStart >= offset {
      return self.entries(in: tail.subdata(in: (listStart - offset)..<record.listEnd), count: record.entryCount)
    }
    // A list too long for the end that was read.
    let list = Data(try await read(listStart, record.listSize))
    guard list.count == record.listSize else {
      throw ReadError.notAnArchive
    }
    return self.entries(in: list, count: record.entryCount)
  }

  /// The record that ends an archive: how many things are in it, and how long its list is, which
  /// comes just before it.
  private struct EndRecord {
    let entryCount: Int
    let listSize: Int
    /// Where the list ends, in what the record was found in.
    let listEnd: Int

    init?(in data: Data) {
      // Looked for back from the end, past the comment it can have.
      let last = data.count - 22
      guard last >= 0 else {
        return nil
      }
      for start in stride(from: last, through: max(0, last - 0xFFFF), by: -1) {
        guard data.hasSignature([0x50, 0x4B, 0x05, 0x06], at: start),
              let entries = data.littleEndian(UInt16.self, at: start + 10),
              let listSize = data.littleEndian(UInt32.self, at: start + 12),
              let commentLength = data.littleEndian(UInt16.self, at: start + 20),
              start + 22 + Int(commentLength) <= data.count else {
          continue
        }
        if entries != 0xFFFF && listSize != 0xFFFFFFFF {
          self.entryCount = Int(entries)
          self.listSize = Int(listSize)
          self.listEnd = start
          return
        }
        // Too many, or too big, for this record, so they're in the ZIP64 one, which is just before
        // what says where it is, which is just before this.
        let record = start - 20 - 56
        guard data.hasSignature([0x50, 0x4B, 0x06, 0x07], at: start - 20),
              data.hasSignature([0x50, 0x4B, 0x06, 0x06], at: record),
              let entries = data.littleEndian(UInt64.self, at: record + 32),
              let listSize = data.littleEndian(UInt64.self, at: record + 40) else {
          return nil
        }
        self.entryCount = Int(clamping: entries)
        self.listSize = Int(clamping: listSize)
        self.listEnd = record
        return
      }
      return nil
    }
  }

  /// What's in a list, but the Finder information the Mac adds to archives it makes, which isn't
  /// anything in them.
  private static func entries(in list: Data, count: Int) -> [ArchiveEntry] {
    var entries: [ArchiveEntry] = []
    var at = 0
    for _ in 0..<count {
      guard list.hasSignature([0x50, 0x4B, 0x01, 0x02], at: at),
            let madeBy = list.littleEndian(UInt16.self, at: at + 4),
            let flags = list.littleEndian(UInt16.self, at: at + 8),
            let size = list.littleEndian(UInt32.self, at: at + 24),
            let nameLength = list.littleEndian(UInt16.self, at: at + 28).map(Int.init),
            let extraLength = list.littleEndian(UInt16.self, at: at + 30).map(Int.init),
            let commentLength = list.littleEndian(UInt16.self, at: at + 32).map(Int.init),
            let attributes = list.littleEndian(UInt32.self, at: at + 38),
            at + 46 + nameLength + extraLength <= list.count else {
        break
      }
      let name = list.subdata(in: (at + 46)..<(at + 46 + nameLength))
      let extra = list.subdata(in: (at + 46 + nameLength)..<(at + 46 + nameLength + extraLength))
      at += 46 + nameLength + extraLength + commentLength

      // Made on DOS or Windows, which could put backslashes between folders.
      let system = madeBy >> 8
      var path = self.name(name, flags: flags, extra: extra)
      if system == 0 || system == 11 || system == 14 {
        path = path.replacingOccurrences(of: "\\", with: "/")
      }
      let isFolder = path.hasSuffix("/")
        || (system == 0 && attributes & 0x10 != 0)
        || (system == 3 && (attributes >> 16) & 0o170000 == 0o040000)
      let components = path.split(separator: "/")
      guard let last = components.last, components.first != "__MACOSX", last != ".DS_Store" else {
        continue
      }

      // Too big for its place, so it's in the ZIP64 extra field, first.
      var fullSize = UInt64(size)
      if size == 0xFFFFFFFF, let zip64 = self.extraField(0x0001, in: extra), let size64 = zip64.littleEndian(UInt64.self, at: 0) {
        fullSize = size64
      }
      entries.append(ArchiveEntry(path: components.joined(separator: "/"), isFolder: isFolder, size: isFolder ? 0 : fullSize))
    }
    return entries
  }

  /// A name: from the UTF-8 copy it can have alongside it, in UTF-8 when it says it is, or reads
  /// as UTF-8, as many do without saying, or in the DOS code page ZIP began with.
  private static func name(_ bytes: Data, flags: UInt16, extra: Data) -> String {
    if let unicode = self.extraField(0x7075, in: extra), unicode.first == 1, unicode.count > 5,
       let name = String(data: unicode.subdata(in: 5..<unicode.count), encoding: .utf8) {
      return name
    }
    if let name = String(data: bytes, encoding: .utf8) {
      return name
    }
    if flags & 0x0800 == 0, let name = String(data: bytes, encoding: self.dosLatinUS) {
      return name
    }
    return String(decoding: bytes, as: UTF8.self)
  }

  private static let dosLatinUS = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosLatinUS.rawValue)))

  /// The data of one of an entry's extra fields, by its ID.
  private static func extraField(_ id: UInt16, in extra: Data) -> Data? {
    var at = 0
    while let fieldID = extra.littleEndian(UInt16.self, at: at), let size = extra.littleEndian(UInt16.self, at: at + 2) {
      let start = at + 4
      let end = start + Int(size)
      guard end <= extra.count else {
        return nil
      }
      if fieldID == id {
        return extra.subdata(in: start..<end)
      }
      at = end
    }
    return nil
  }
}

private extension Data {
  /// A little-endian number at an offset from the start, or nil if it runs past the end.
  func littleEndian<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T? {
    let size = MemoryLayout<T>.size
    guard offset >= 0, offset + size <= self.count else {
      return nil
    }
    var value: T = 0
    for index in 0..<size {
      value |= T(self[self.startIndex + offset + index]) << (8 * index)
    }
    return value
  }

  func hasSignature(_ signature: [UInt8], at offset: Int) -> Bool {
    guard offset >= 0, offset + signature.count <= self.count else {
      return false
    }
    return self[(self.startIndex + offset)..<(self.startIndex + offset + signature.count)].elementsEqual(signature)
  }
}
