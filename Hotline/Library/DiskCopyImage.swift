import Foundation

/// A disk image in Disk Copy 6's format, as Disk Copy, ShrinkWrap and self-mounting images save
/// one: the disk in chunks, one after another in the data fork, each kept as it is, left out for
/// being empty, or compressed, and a map of them, in the resource fork. Any part of the disk is
/// read from the chunks it's in, which are together, so with one read.
struct DiskCopyImage {
  /// A run of the disk's 512-byte sectors, and how it's kept.
  private struct Chunk {
    let sector: Int
    let sectors: Int
    let kind: UInt8
    let offset: Int
    let length: Int
  }

  private static let empty: UInt8 = 0x00
  private static let asIs: UInt8 = 0x02
  private static let adc: UInt8 = 0x83
  private static let end: UInt8 = 0xFF

  private let chunks: [Chunk]
  /// How big the disk is.
  let size: Int

  /// From the map in a resource fork, for a data fork `dataSize` long: its header, with the
  /// disk's name, how many sectors it has, and how many chunks, then for each, the sector it
  /// starts at, how it's kept, and where it is in the data fork, and how long.
  init?(resourceFork: Data, dataSize: Int) {
    guard let map = ResourceFork.resource("bcem", in: resourceFork),
          let sectors = map.bigEndian(UInt32.self, at: 68).map(Int.init), sectors > 0,
          let count = map.bigEndian(UInt32.self, at: 124).map(Int.init), count > 1, 128 + 12 * count <= map.count else {
      return nil
    }
    var chunks: [Chunk] = []
    for index in 0..<(count - 1) {
      let entry = 128 + 12 * index
      guard let start = map.bigEndian(UInt32.self, at: entry).map({ Int($0 >> 8) }),
            let kind = map.byte(at: entry + 3),
            let offset = map.bigEndian(UInt32.self, at: entry + 4).map(Int.init),
            let length = map.bigEndian(UInt32.self, at: entry + 8).map(Int.init),
            let next = map.bigEndian(UInt32.self, at: entry + 12).map({ Int($0 >> 8) }), next > start,
            [Self.empty, Self.asIs, Self.adc].contains(kind), offset + length <= dataSize else {
        return nil
      }
      chunks.append(Chunk(sector: start, sectors: next - start, kind: kind, offset: offset, length: length))
    }
    self.chunks = chunks
    self.size = sectors * 512
  }

  /// `length` bytes of the disk from `offset`, from the chunks they're in, read through `read`,
  /// which gives the `length` bytes of the data fork from `offset`.
  func read(_ offset: Int, _ length: Int, from read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> Data {
    guard length > 0 else {
      return Data()
    }
    let firstSector = offset / 512
    let lastSector = (offset + length - 1) / 512
    let needed = self.chunks.filter { $0.sector <= lastSector && $0.sector + $0.sectors > firstSector }
    guard let first = needed.first else {
      throw ArchiveReadError.notAnArchive
    }

    // What's kept of them, together in the data fork, as they're kept in order.
    let kept = needed.filter { $0.kind != Self.empty }
    let keptStart = kept.first?.offset ?? 0
    let keptData = kept.isEmpty ? Data() : Data(try await read(keptStart, kept.last!.offset + kept.last!.length - keptStart))
    var disk = Data()
    for chunk in needed {
      let size = chunk.sectors * 512
      if chunk.kind == Self.empty {
        disk += Data(count: size)
        continue
      }
      let start = chunk.offset - keptStart
      guard start >= 0, start + chunk.length <= keptData.count else {
        throw ArchiveReadError.notAnArchive
      }
      let data = keptData.subdata(in: start..<(start + chunk.length))
      guard let expanded = chunk.kind == Self.adc ? Self.expand(data, to: size) : data, expanded.count == size else {
        throw ArchiveReadError.notAnArchive
      }
      disk += expanded
    }
    let skip = offset - first.sector * 512
    guard skip + length <= disk.count else {
      throw ArchiveReadError.notAnArchive
    }
    return disk.subdata(in: skip..<(skip + length))
  }

  /// Apple Data Compression, as Disk Copy compresses a chunk: runs of bytes as they are, after a
  /// byte with its high bit set, saying how many, and bytes copied from those just before, by
  /// how many and how far back, in two or three bytes.
  static func expand(_ data: Data, to size: Int) -> Data? {
    let input = [UInt8](data)
    var output: [UInt8] = []
    output.reserveCapacity(size)
    var at = 0
    while at < input.count && output.count < size {
      let code = input[at]
      if code & 0x80 != 0 {
        let count = Int(code & 0x7F) + 1
        guard at + 1 + count <= input.count else {
          return nil
        }
        output += input[(at + 1)..<(at + 1 + count)]
        at += 1 + count
        continue
      }
      let count: Int
      let distance: Int
      if code & 0x40 != 0 {
        guard at + 2 < input.count else {
          return nil
        }
        count = Int(code & 0x3F) + 4
        distance = (Int(input[at + 1]) << 8 | Int(input[at + 2])) + 1
        at += 3
      }
      else {
        guard at + 1 < input.count else {
          return nil
        }
        count = (Int(code & 0x3C) >> 2) + 3
        distance = (Int(code & 0x03) << 8 | Int(input[at + 1])) + 1
        at += 2
      }
      guard distance <= output.count else {
        return nil
      }
      for _ in 0..<count {
        output.append(output[output.count - distance])
      }
    }
    return output.count >= size ? Data(output.prefix(size)) : nil
  }
}

/// A Mac file's resource fork: its resources, by type, found through its map.
enum ResourceFork {
  /// The data of the first resource of a type: from the fork's header, where its resources' data
  /// is and its map, and the map's list of types, each with how many resources of it there are
  /// and where their references are, each with where its data is, after its length.
  static func resource(_ type: String, in fork: Data) -> Data? {
    guard let dataOffset = fork.bigEndian(UInt32.self, at: 0).map(Int.init),
          let mapOffset = fork.bigEndian(UInt32.self, at: 4).map(Int.init),
          let typeListOffset = fork.bigEndian(UInt16.self, at: mapOffset + 24).map(Int.init),
          let typeCount = fork.bigEndian(UInt16.self, at: mapOffset + typeListOffset).map({ Int($0) + 1 }) else {
      return nil
    }
    let typeList = mapOffset + typeListOffset
    for index in 0..<typeCount {
      let entry = typeList + 2 + 8 * index
      guard fork.fourCharCode(at: entry) == type,
            let references = fork.bigEndian(UInt16.self, at: entry + 6).map({ typeList + Int($0) }),
            let offset = fork.bigEndian(UInt32.self, at: references + 4).map({ Int($0 & 0x00FFFFFF) }),
            let length = fork.bigEndian(UInt32.self, at: dataOffset + offset).map(Int.init),
            dataOffset + offset + 4 + length <= fork.count else {
        continue
      }
      return fork.subdata(in: (dataOffset + offset + 4)..<(dataOffset + offset + 4 + length))
    }
    return nil
  }
}
