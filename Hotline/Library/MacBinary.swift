import Foundation

/// A Mac file in MacBinary, which carries both its forks, and its type and creator, as one file.
/// Its name and what it is are in the 128 bytes at the start.
enum MacBinary {
  /// The file in one `size` long, read through `read`, which gives the `length` bytes of it from
  /// `offset`.
  static func entries(size: Int, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    let header = Data(try await read(0, min(size, 128)))
    guard let file = self.file(in: header, size: size) else {
      throw ArchiveReadError.notAnArchive
    }
    return [file]
  }

  /// The file a MacBinary header is for, in a file `size` long, if that's what it is, as plenty of
  /// files named .bin aren't: version 0, a name of 1 to 63 letters, zeros where there always are,
  /// forks that fit after it, and in MacBinary II, a check of the header, in III, its signature,
  /// or in I, zeros where they have those.
  static func file(in header: Data, size: Int) -> ArchiveEntry? {
    let header = Data(header)
    guard header.count == 128, header.byte(at: 0) == 0, header.byte(at: 74) == 0, header.byte(at: 82) == 0,
          let nameLength = header.byte(at: 1).map(Int.init), (1...63).contains(nameLength),
          let name = header.macName(at: 2, length: nameLength),
          let dataLength = header.bigEndian(UInt32.self, at: 83), dataLength < 0x80000000,
          let resourceLength = header.bigEndian(UInt32.self, at: 87), resourceLength < 0x80000000,
          128 + Int(dataLength) + Int(resourceLength) <= size,
          let check = header.bigEndian(UInt16.self, at: 124) else {
      return nil
    }
    let isMacBinaryII = check == CRC16.xmodem(header.prefix(124))
    let isMacBinaryIII = header.hasSignature(Array("mBIN".utf8), at: 102)
    let isMacBinaryI = header.subdata(in: 99..<126).allSatisfy { $0 == 0 }
    guard isMacBinaryII || isMacBinaryIII || isMacBinaryI else {
      return nil
    }
    return ArchiveEntry(path: name, isFolder: false, size: UInt64(dataLength) + UInt64(resourceLength), type: header.fourCharCode(at: 65))
  }
}
