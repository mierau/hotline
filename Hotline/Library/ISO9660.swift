import Foundation

/// What's on a PC disc, or the PC side of one for Macs too: an ISO 9660 file system, with Joliet's
/// long names, if it has them. Its volume descriptors, from the 16th sector, say where its path
/// table is, which lists every folder, and where each folder's own list of what's in it is. Those
/// are written one after another, before the files, so they're read all at once, and a disc
/// whose aren't isn't read.
enum ISO9660 {
  /// The most read for the folders' lists.
  static let listsLimit = 16 * 1024 * 1024

  /// What's on a disc `size` long, read through `read`, which gives the `length` bytes of it from
  /// `offset`, with `start`, what's been read of its start.
  static func entries(size: Int, start: Data, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    guard let volume = self.volume(in: start) else {
      throw ArchiveReadError.notAnArchive
    }

    // The path table: each folder's name, where its list is, and the folder it's in, by its
    // place in the table.
    let table = try await self.read(volume.pathTableOffset, volume.pathTableSize, start: start, read: read)
    var folders: [(name: String, extent: Int, parent: Int)] = []
    var at = 0
    while at + 8 <= table.count {
      guard let nameLength = table.byte(at: at).map(Int.init), nameLength > 0,
            let extent = table.littleEndian(UInt32.self, at: at + 2).map(Int.init),
            let parent = table.littleEndian(UInt16.self, at: at + 6).map(Int.init),
            at + 8 + nameLength <= table.count else {
        break
      }
      let name = volume.isJoliet ? self.jolietName(table.subdata(in: (at + 8)..<(at + 8 + nameLength))) : self.isoName(table.subdata(in: (at + 8)..<(at + 8 + nameLength)))
      folders.append((name, extent, parent))
      at += 8 + nameLength + nameLength % 2
    }
    guard let first = folders.map(\.extent).min(), let last = folders.map(\.extent).max() else {
      throw ArchiveReadError.notAnArchive
    }

    // Every folder's list, all at once, through the last one's, which is given room to be long.
    let blockSize = volume.blockSize
    let listsOffset = first * blockSize
    let listsLength = min((last - first) * blockSize + 64 * 1024, size - listsOffset)
    guard listsLength > 0, listsLength <= self.listsLimit else {
      throw ArchiveReadError.notAnArchive
    }
    let lists = Data(try await read(listsOffset, listsLength))

    // Each folder's place, from the names of the folders it's in, the first being the disc's own.
    func path(_ number: Int) -> String? {
      var components: [String] = []
      var number = number
      var depth = 0
      while number > 1 {
        guard number <= folders.count, depth < 100 else {
          return nil
        }
        components.insert(folders[number - 1].name, at: 0)
        number = folders[number - 1].parent
        depth += 1
      }
      return components.joined(separator: "/")
    }

    var entries: [ArchiveEntry] = []
    var hiddenFolders: Set<String> = []
    for (index, folder) in folders.enumerated() {
      guard let folderPath = path(index + 1) else {
        continue
      }
      let listStart = (folder.extent - first) * blockSize
      // How long its list is, which its own first record says.
      guard let listLength = lists.littleEndian(UInt32.self, at: listStart + 10).map(Int.init),
            listStart + listLength <= lists.count else {
        throw ArchiveReadError.notAnArchive
      }
      if index > 0 {
        entries.append(ArchiveEntry(path: folderPath, isFolder: true, size: 0))
      }
      // Its records, none across a block's end, after the ones for itself and the folder it's in.
      var at = listStart
      var sizes: [String: UInt64] = [:]
      var order: [String] = []
      while at < listStart + listLength {
        guard let length = lists.byte(at: at).map(Int.init), length > 0 else {
          at = (at / blockSize + 1) * blockSize
          continue
        }
        guard length >= 34, at + length <= lists.count,
              let fileSize = lists.littleEndian(UInt32.self, at: at + 10),
              let flags = lists.byte(at: at + 25),
              let nameLength = lists.byte(at: at + 32).map(Int.init), 33 + nameLength <= length else {
          throw ArchiveReadError.notAnArchive
        }
        let nameBytes = lists.subdata(in: (at + 33)..<(at + 33 + nameLength))
        at += length
        guard nameLength > 1 || (nameBytes.first ?? 0) > 1 else {
          continue
        }
        let name = volume.isJoliet ? self.jolietName(nameBytes) : self.isoName(nameBytes)
        let itemPath = folderPath.isEmpty ? name : "\(folderPath)/\(name)"
        if flags & 0x01 != 0 {
          // Hidden: a file, or a folder, and what's in it, which the path table lists.
          if flags & 0x02 != 0 {
            hiddenFolders.insert(itemPath)
          }
          continue
        }
        guard flags & 0x02 == 0 else {
          continue
        }
        // A file in parts, each with a record of its own, is all of them together.
        if sizes[itemPath] == nil {
          order.append(itemPath)
        }
        sizes[itemPath, default: 0] += UInt64(fileSize)
      }
      entries += order.map { ArchiveEntry(path: $0, isFolder: false, size: sizes[$0] ?? 0) }
    }
    return entries.filter { entry in
      !hiddenFolders.contains { entry.path == $0 || entry.path.hasPrefix("\($0)/") }
    }
  }

  private struct Volume {
    let isJoliet: Bool
    let blockSize: Int
    let pathTableOffset: Int
    let pathTableSize: Int
  }

  /// The volume descriptor to read the disc by: Joliet's, if there is one, for its long names, or
  /// the primary one.
  private static func volume(in start: Data) -> Volume? {
    var primary: Volume?
    for sector in 16..<64 {
      let at = sector * 2048
      guard start.hasSignature(Array("CD001".utf8), at: at + 1), let type = start.byte(at: at) else {
        break
      }
      if type == 255 {
        break
      }
      guard type == 1 || type == 2,
            let blockSize = start.littleEndian(UInt16.self, at: at + 128).map(Int.init), blockSize > 0,
            let tableSize = start.littleEndian(UInt32.self, at: at + 132).map(Int.init), tableSize > 0,
            let tableBlock = start.littleEndian(UInt32.self, at: at + 140).map(Int.init) else {
        continue
      }
      // Joliet: a supplementary descriptor with one of the escape sequences for UCS-2.
      let isJoliet = type == 2 && start.hasSignature([0x25, 0x2F], at: at + 88) && [0x40, 0x43, 0x45].contains(start.byte(at: at + 90))
      let volume = Volume(isJoliet: isJoliet, blockSize: blockSize, pathTableOffset: tableBlock * blockSize, pathTableSize: tableSize)
      if isJoliet {
        return volume
      }
      if type == 1 {
        primary = volume
      }
    }
    return primary
  }

  /// From what's been read of the start, if it's in it, or read for it.
  private static func read(_ offset: Int, _ length: Int, start: Data, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> Data {
    if offset + length <= start.count {
      return start.subdata(in: offset..<(offset + length))
    }
    return Data(try await read(offset, length))
  }

  /// A name without the version after its semicolon, or the dot of a name without an extension.
  private static func trimmed(_ name: String) -> String {
    var name = name
    if let semicolon = name.lastIndex(of: ";") {
      name = String(name[..<semicolon])
    }
    if name.hasSuffix(".") {
      name.removeLast()
    }
    return name.replacingOccurrences(of: "/", with: ":")
  }

  private static func isoName(_ bytes: Data) -> String {
    self.trimmed(String(decoding: bytes, as: UTF8.self))
  }

  private static func jolietName(_ bytes: Data) -> String {
    self.trimmed(String(data: bytes, encoding: .utf16BigEndian) ?? String(decoding: bytes, as: UTF8.self))
  }
}
