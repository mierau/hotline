import Foundation

/// The list of what's in a Compact Pro archive, which comes after everything in it, from where the
/// first bytes of the archive say, to its end.
enum CompactProArchive {
  /// What's in an archive `size` long, read through `read`, which gives the `length` bytes of it
  /// from `offset`.
  static func entries(size: Int, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    // A 1, which volume of the archive it is, a check across volumes, and where the list is.
    let header = Data(try await read(0, min(size, 8)))
    guard header.count == 8, header.first == 1,
          let listOffset = header.bigEndian(UInt32.self, at: 4).map(Int.init), listOffset >= 8, listOffset < size else {
      throw ArchiveReadError.notAnArchive
    }
    let list = Data(try await read(listOffset, size - listOffset))

    // A check of the list, how many things are in the archive, and a comment.
    guard list.count == size - listOffset,
          let count = list.bigEndian(UInt16.self, at: 4).map(Int.init),
          let commentLength = list.byte(at: 6).map(Int.init) else {
      throw ArchiveReadError.notAnArchive
    }
    var reader = ListReader(list: list, at: 7 + commentLength)
    return try reader.entries(count, in: "")
  }

  private struct ListReader {
    let list: Data
    var at: Int

    /// The next `count` things in the list, which are in `folder`. A folder's count includes all
    /// that's in it, and the folders in it, which follow it.
    mutating func entries(_ count: Int, in folder: String) throws -> [ArchiveEntry] {
      var entries: [ArchiveEntry] = []
      var remaining = count
      while remaining > 0 {
        // How long its name is, and whether it's a folder, then its name.
        guard let nameByte = self.list.byte(at: self.at),
              let name = self.list.macName(at: self.at + 1, length: Int(nameByte & 0x7F)) else {
          throw ArchiveReadError.notAnArchive
        }
        self.at += 1 + Int(nameByte & 0x7F)
        let path = folder.isEmpty ? name : "\(folder)/\(name)"

        if nameByte & 0x80 != 0 {
          guard let inside = self.list.bigEndian(UInt16.self, at: self.at).map(Int.init), inside < remaining else {
            throw ArchiveReadError.notAnArchive
          }
          self.at += 2
          entries.append(ArchiveEntry(path: path, isFolder: true, size: 0))
          entries += try self.entries(inside, in: path)
          remaining -= inside + 1
        }
        else {
          // Which volume it's in, where it is, its type and creator, when it was made and changed,
          // its Finder flags, a check, flags, and how long its forks are, and were, compressed.
          guard self.at + 45 <= self.list.count,
                let resourceLength = self.list.bigEndian(UInt32.self, at: self.at + 29),
                let dataLength = self.list.bigEndian(UInt32.self, at: self.at + 33) else {
            throw ArchiveReadError.notAnArchive
          }
          let type = self.list.fourCharCode(at: self.at + 5)
          self.at += 45
          entries.append(ArchiveEntry(path: path, isFolder: false, size: UInt64(resourceLength) + UInt64(dataLength), type: type))
          remaining -= 1
        }
      }
      return entries
    }
  }
}
