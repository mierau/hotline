import Foundation

/// What's on a Mac disc or disk in an image of it, as Toast, Disk Utility's CD and DVD masters, and
/// Disk Copy's and emulators' disks are, which is the disk as it is, byte for byte, or for a CD,
/// sometimes as it's written, sector by sector: from its file system's catalog, which lists every
/// file and folder on it. Its volume header says where the catalog is. That's near the start, or
/// in a partition further on, as on a CD for PCs too, whose part comes first. For HFS and HFS
/// Plus, and a catalog in at most four pieces the header says where all of are, as a disc's
/// usually is, in one, so it's read with a look at the start, maybe one at the header, and a read
/// of each piece of the catalog. A disc without one is read as a PC's is, and an image in Disk
/// Copy 6's chunks, from them, with their map, from the resource fork.
enum DiskImage {
  /// How much of the start is read, for the volume header, with room for a partition map before
  /// it, and how much from the start of a partition further on.
  static let startLength = 64 * 1024
  /// The most of a catalog that's read, which is many thousands of files' worth.
  static let catalogLimit = 32 * 1024 * 1024
  /// The most pieces a catalog's read in, each a read of its own.
  static let catalogPieceLimit = 4

  /// What's on the disc in an image `size` long, read through `read`, which gives the `length`
  /// bytes of it from `offset`, and `resourceFork`, which gives its resource fork, for an image
  /// in Disk Copy 6's chunks.
  static func entries(size: Int, read: (_ offset: Int, _ length: Int) async throws -> Data, resourceFork: (() async throws -> Data)? = nil) async throws -> [ArchiveEntry] {
    let start = Data(try await read(0, min(size, self.startLength)))
    do {
      return try await self.storedEntries(size: size, start: start, read: read)
    }
    catch ArchiveReadError.notAnArchive {
      // In chunks, mapped in its resource fork, if it has one.
      guard let resourceFork, let image = DiskCopyImage(resourceFork: try await resourceFork(), dataSize: size) else {
        throw ArchiveReadError.notAnArchive
      }
      func disk(_ offset: Int, _ length: Int) async throws -> Data {
        try await image.read(offset, length, from: read)
      }
      // Only as much of its start as a volume at the disk's start needs, which is in the first
      // chunk, usually kept as it is, and already read. More's read for a volume further on.
      return try await self.diskEntries(size: image.size, start: try await disk(0, min(image.size, 1536)), read: disk)
    }
  }

  /// What's on the disc in an image of it as it is, or as it's written.
  private static func storedEntries(size: Int, start: Data, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    // A disc saved as it's written, in 2352-byte sectors, each with its 2048 bytes of data between
    // a sync, a header, and in Mode 2, a subheader, and its error correction.
    guard start.hasSignature([0x00] + Array(repeating: 0xFF, count: 10) + [0x00], at: 0), size % 2352 == 0 else {
      return try await self.diskEntries(size: size, start: start, read: read)
    }
    func data(_ offset: Int, _ length: Int) async throws -> Data {
      guard length > 0 else {
        return Data()
      }
      let first = offset / 2048
      let last = (offset + length - 1) / 2048
      let sectors = Data(try await read(first * 2352, (last - first + 1) * 2352))
      var data = Data()
      for sector in stride(from: 0, to: sectors.count - 2351, by: 2352) {
        let dataStart = sector + (sectors.byte(at: sector + 15) == 2 ? 24 : 16)
        data += sectors.subdata(in: dataStart..<(dataStart + 2048))
      }
      let skip = offset - first * 2048
      return data.subdata(in: min(skip, data.count)..<min(data.count, skip + length))
    }
    // What's been read of the start, as data, which is fewer sectors than bytes.
    let dataStart = try await data(0, start.count / 2352 * 2048)
    return try await self.diskEntries(size: size / 2352 * 2048, start: dataStart, read: data)
  }

  /// What's on a disc `size` long, with `start`, what's been read of its start: its Mac volume, or
  /// if it hasn't one, or one that can be read, its PC one.
  private static func diskEntries(size: Int, start: Data, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    var volume: Volume?
    for volumeStart in self.volumeStarts(in: start) where volumeStart < size {
      // Its header, in what's been read of the start, or read for it, if it's further on.
      let window = volumeStart + 1536 <= start.count
        ? start.subdata(in: volumeStart..<start.count)
        : Data(try await read(volumeStart, min(size - volumeStart, self.startLength)))
      volume = self.volume(in: window, at: volumeStart)
      if volume != nil {
        break
      }
    }
    // Not one that's bigger than the image, which can't be in it as it is.
    guard let volume, volume.end <= size + self.startLength,
          let pieces = volume.catalog, pieces.reduce(0, { $0 + $1.length }) <= self.catalogLimit,
          pieces.allSatisfy({ $0.offset + $0.length <= size }) else {
      return try await ISO9660.entries(size: size, start: start, read: read)
    }
    var data = Data()
    for piece in pieces {
      let pieceData = Data(try await read(piece.offset, piece.length))
      guard pieceData.count == piece.length else {
        throw ArchiveReadError.notAnArchive
      }
      data += pieceData
    }
    return try Catalog(data: data, isPlus: volume.isPlus).entries()
  }

  private struct Volume {
    let isPlus: Bool
    /// Where it ends in the image, from how big its header says it is.
    let end: Int
    /// Where its catalog's pieces are in the image, in order, if its header says where all of them
    /// are, and there aren't too many.
    let catalog: [(offset: Int, length: Int)]?
  }

  /// Where a Mac volume can start in an image: at its start, after Disk Copy 4.2's header, or at an
  /// Apple partition map's HFS partitions.
  private static func volumeStarts(in start: Data) -> [Int] {
    var starts = [0]
    // Disk Copy 4.2: the disk's name, sizes and checks, then the disk, from 84 bytes in.
    if start.bigEndian(UInt16.self, at: 82) == 0x0100 {
      starts.append(84)
    }
    // An Apple partition map: its block size, then a block for each partition, after the first.
    guard start.bigEndian(UInt16.self, at: 0) == 0x4552 else {
      return starts
    }
    let blockSize = Int(start.bigEndian(UInt16.self, at: 2) ?? 0)
    // Some say a block's bigger than the blocks the map's written in.
    for blockSize in Set([blockSize == 0 ? 512 : blockSize, 512]) {
      guard start.bigEndian(UInt16.self, at: blockSize) == 0x504D,
            let count = start.bigEndian(UInt32.self, at: blockSize + 4).map(Int.init), count > 0 else {
        continue
      }
      for index in 1...min(count, 64) {
        let entry = index * blockSize
        guard start.bigEndian(UInt16.self, at: entry) == 0x504D,
              let first = start.bigEndian(UInt32.self, at: entry + 8).map(Int.init),
              let type = start.macName(at: entry + 48, length: 32) else {
          break
        }
        if type.hasPrefix("Apple_HFS") {
          starts.append(first * blockSize)
        }
      }
    }
    return starts
  }

  /// The volume whose header is 1024 bytes into `window`, which is the image from `volumeStart`.
  private static func volume(in window: Data, at volumeStart: Int) -> Volume? {
    let header = 1024
    switch window.bigEndian(UInt16.self, at: header) {
    case 0x4244:
      // HFS: its allocation blocks' size, where they start, in 512-byte blocks, and the
      // catalog's size and first three extents.
      guard let blockSize = window.bigEndian(UInt32.self, at: header + 0x14).map(Int.init), blockSize > 0,
            let firstBlock = window.bigEndian(UInt16.self, at: header + 0x1C).map(Int.init) else {
        return nil
      }
      let blocks = firstBlock * 512
      // Around an HFS Plus volume, which has the files, if its header's in the window too.
      if window.bigEndian(UInt16.self, at: header + 0x7C) == 0x482B {
        guard let embedded = window.bigEndian(UInt16.self, at: header + 0x7E).map(Int.init),
              blocks + embedded * blockSize + 1536 <= window.count else {
          return nil
        }
        let offset = blocks + embedded * blockSize
        return self.volume(in: window.subdata(in: offset..<window.count), at: volumeStart + offset)
      }
      guard let catalogSize = window.bigEndian(UInt32.self, at: header + 0x92).map(Int.init) else {
        return nil
      }
      let extents = (0..<3).compactMap { index -> (start: Int, count: Int)? in
        guard let start = window.bigEndian(UInt16.self, at: header + 0x96 + 4 * index),
              let count = window.bigEndian(UInt16.self, at: header + 0x98 + 4 * index) else {
          return nil
        }
        return (Int(start), Int(count))
      }
      let blockCount = Int(window.bigEndian(UInt16.self, at: header + 0x12) ?? 0)
      return Volume(isPlus: false, end: volumeStart + blocks + blockCount * blockSize, catalog: self.catalogPieces(extents, blockSize: blockSize, from: volumeStart + blocks, size: catalogSize))
    case 0x482B, 0x4858:
      // HFS Plus: its blocks' size, and the catalog's size and first eight extents.
      guard let blockSize = window.bigEndian(UInt32.self, at: header + 40).map(Int.init), blockSize > 0,
            let catalogSize = window.bigEndian(UInt64.self, at: header + 272).map({ Int(clamping: $0) }) else {
        return nil
      }
      let extents = (0..<8).compactMap { index -> (start: Int, count: Int)? in
        guard let start = window.bigEndian(UInt32.self, at: header + 288 + 8 * index),
              let count = window.bigEndian(UInt32.self, at: header + 292 + 8 * index) else {
          return nil
        }
        return (Int(start), Int(count))
      }
      let blockCount = Int(window.bigEndian(UInt32.self, at: header + 44) ?? 0)
      return Volume(isPlus: true, end: volumeStart + blockCount * blockSize, catalog: self.catalogPieces(extents, blockSize: blockSize, from: volumeStart, size: catalogSize))
    default:
      return nil
    }
  }

  /// Where a catalog `size` long is, from the runs of blocks its header lists for it, each where it
  /// starts and how many blocks long, in blocks of `blockSize` from `blocks`, if they're all of it,
  /// rather than the first of more, which another file lists, and there aren't too many.
  private static func catalogPieces(_ extents: [(start: Int, count: Int)], blockSize: Int, from blocks: Int, size: Int) -> [(offset: Int, length: Int)]? {
    var pieces: [(offset: Int, length: Int)] = []
    var remaining = size
    for extent in extents where extent.count > 0 && remaining > 0 {
      let length = min(extent.count * blockSize, remaining)
      pieces.append((blocks + extent.start * blockSize, length))
      remaining -= length
    }
    guard remaining == 0, !pieces.isEmpty, pieces.count <= self.catalogPieceLimit else {
      return nil
    }
    return pieces
  }

  /// A catalog: a B-tree, whose header node, first, says how big its nodes are and which leaf node
  /// is first. The leaves, each linked to the next, have a record for each file and folder, keyed
  /// by the ID of the folder it's in and its name.
  private struct Catalog {
    let data: Data
    let isPlus: Bool

    private struct Record {
      let name: String
      let folder: UInt32
      let isFolder: Bool
      let isHidden: Bool
      var size: UInt64 = 0
      var type: String? = nil
    }

    /// Finder's flag for something it doesn't show.
    private static let invisible: UInt16 = 0x4000
    /// The folders at the top of a volume the Finder kept for itself, and didn't show, without a
    /// flag to say so.
    private static let finderFolders: Set<String> = ["Trash", "Desktop Folder", "Temporary Items", "Network Trash Folder", "TheVolumeSettingsFolder", "TheFindByContentFolder"]
    /// The ID of the volume's own folder, which everything's in.
    private static let root: UInt32 = 2

    func entries() throws -> [ArchiveEntry] {
      guard let nodeSize = self.data.bigEndian(UInt16.self, at: 32).map(Int.init), nodeSize >= 512,
            var node = self.data.bigEndian(UInt32.self, at: 24).map(Int.init) else {
        throw ArchiveReadError.notAnArchive
      }
      var records: [Record] = []
      var folders: [UInt32: Record] = [:]
      var visited: Set<Int> = []
      while node != 0, visited.insert(node).inserted {
        let start = node * nodeSize
        // A leaf: its descriptor says so, and how many records it has, where at its end.
        guard start + nodeSize <= self.data.count, self.data.byte(at: start + 8) == 0xFF,
              let count = self.data.bigEndian(UInt16.self, at: start + 10).map(Int.init) else {
          throw ArchiveReadError.notAnArchive
        }
        for index in 0..<count {
          guard let offset = self.data.bigEndian(UInt16.self, at: start + nodeSize - 2 * (index + 1)).map(Int.init),
                offset >= 14, offset < nodeSize else {
            throw ArchiveReadError.notAnArchive
          }
          if let (record, id) = self.record(at: start + offset) {
            records.append(record)
            if let id {
              folders[id] = record
            }
          }
        }
        node = self.data.bigEndian(UInt32.self, at: start).map(Int.init) ?? 0
      }

      return records.compactMap { record in
        // Its place, from the folders it's in, up to the volume's, but not if any of them is
        // hidden, and not the volume's folder itself.
        guard !record.isHidden, record.folder != 1 else {
          return nil
        }
        var path = record.name
        var folder = record.folder
        var depth = 0
        while folder != Self.root {
          guard let parent = folders[folder], !parent.isHidden, depth < 100 else {
            return nil
          }
          path = "\(parent.name)/\(path)"
          folder = parent.folder
          depth += 1
        }
        return ArchiveEntry(path: path, isFolder: record.isFolder, size: record.size, type: record.type)
      }
    }

    /// The file or folder a record's for, and a folder's own ID, or nil for the records that say
    /// what's at an ID.
    private func record(at offset: Int) -> (Record, UInt32?)? {
      // Its key: its length, the folder it's in, and its name.
      let name: String
      let folder: UInt32
      var at: Int
      if self.isPlus {
        guard let keyLength = self.data.bigEndian(UInt16.self, at: offset).map(Int.init),
              let parent = self.data.bigEndian(UInt32.self, at: offset + 2),
              let nameLength = self.data.bigEndian(UInt16.self, at: offset + 6).map(Int.init),
              offset + 8 + 2 * nameLength <= self.data.count,
              let unicode = String(data: self.data.subdata(in: (offset + 8)..<(offset + 8 + 2 * nameLength)), encoding: .utf16BigEndian) else {
          return nil
        }
        name = unicode.replacingOccurrences(of: "/", with: ":")
        folder = parent
        at = offset + 2 + keyLength
      }
      else {
        guard let keyLength = self.data.byte(at: offset).map(Int.init),
              let parent = self.data.bigEndian(UInt32.self, at: offset + 2),
              let nameLength = self.data.byte(at: offset + 6).map(Int.init),
              let macName = self.data.macName(at: offset + 7, length: nameLength) else {
          return nil
        }
        name = macName
        folder = parent
        at = offset + 1 + keyLength
      }
      at += at % 2

      // Then its data, by its kind: a folder, a file, or a thread record, which isn't either.
      let kind = self.isPlus ? self.data.bigEndian(UInt16.self, at: at).map(Int.init) : self.data.byte(at: at).map(Int.init)
      let isDotted = name.hasPrefix(".")
      switch kind {
      case 1:
        guard let id = self.data.bigEndian(UInt32.self, at: at + (self.isPlus ? 8 : 6)),
              let flags = self.data.bigEndian(UInt16.self, at: at + (self.isPlus ? 56 : 30)) else {
          return nil
        }
        let isFinders = folder == Self.root && Self.finderFolders.contains(name)
        let record = Record(name: name, folder: folder, isFolder: true, isHidden: isDotted || isFinders || flags & Self.invisible != 0)
        return (record, id)
      case 2:
        let flags = self.data.bigEndian(UInt16.self, at: at + (self.isPlus ? 56 : 12)) ?? 0
        var record = Record(name: name, folder: folder, isFolder: false, isHidden: isDotted || flags & Self.invisible != 0)
        record.type = self.data.fourCharCode(at: at + (self.isPlus ? 48 : 4))
        if self.isPlus {
          record.size = (self.data.bigEndian(UInt64.self, at: at + 88) ?? 0) + (self.data.bigEndian(UInt64.self, at: at + 168) ?? 0)
        }
        else {
          record.size = UInt64(self.data.bigEndian(UInt32.self, at: at + 26) ?? 0) + UInt64(self.data.bigEndian(UInt32.self, at: at + 36) ?? 0)
        }
        return (record, nil)
      default:
        return nil
      }
    }
  }
}
