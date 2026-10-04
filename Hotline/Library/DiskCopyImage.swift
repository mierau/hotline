import Foundation

/// A disk image in Disk Copy 6's format, as Disk Copy, ShrinkWrap and self-mounting images save
/// one: the disk in chunks, one after another in the data fork, each kept as it is, left out for
/// being empty, or compressed, with Apple's compression or KenCode, or StuffIt's, from ShrinkWrap,
/// and a map of them, in the resource fork. Any part of the disk is read from the chunks it's in,
/// which are together, so with one read.
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
  private static let kenCode: UInt8 = 0x80
  private static let adc: UInt8 = 0x83
  private static let stuffIt: UInt8 = 0xF0
  private static let end: UInt8 = 0xFF

  private let chunks: [Chunk]
  /// How big the disk is.
  let size: Int

  /// From the map in a resource fork, for a data fork `dataSize` long: its header, with the
  /// disk's name, how many sectors it has, where in the data fork the chunks are from, and how
  /// many there are, then for each, the sector it starts at, how it's kept, and where it is, and
  /// how long.
  init?(resourceFork: Data, dataSize: Int) {
    guard let map = ResourceFork.resource("bcem", in: resourceFork),
          let sectors = map.bigEndian(UInt32.self, at: 68).map(Int.init), sectors > 0,
          let dataOffset = map.bigEndian(UInt32.self, at: 76).map(Int.init),
          let count = map.bigEndian(UInt32.self, at: 124).map(Int.init), count > 1, 128 + 12 * count <= map.count else {
      return nil
    }
    var chunks: [Chunk] = []
    for index in 0..<(count - 1) {
      let entry = 128 + 12 * index
      guard let start = map.bigEndian(UInt32.self, at: entry).map({ Int($0 >> 8) }),
            let kind = map.byte(at: entry + 3),
            let offset = map.bigEndian(UInt32.self, at: entry + 4).map({ Int($0) + dataOffset }),
            let length = map.bigEndian(UInt32.self, at: entry + 8).map(Int.init),
            let next = map.bigEndian(UInt32.self, at: entry + 12).map({ Int($0 >> 8) }), next > start,
            [Self.empty, Self.asIs, Self.kenCode, Self.adc, Self.stuffIt].contains(kind), offset + length <= dataSize else {
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
      let expanded: Data?
      switch chunk.kind {
      case Self.adc: expanded = Self.expand(data, to: size)
      case Self.kenCode: expanded = Self.expandKenCode(data, to: size)
      case Self.stuffIt: expanded = Self.expandStuffIt(data, to: size)
      default: expanded = data
      }
      guard let expanded, expanded.count == size else {
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

  /// KenCode, as Disk Copy 6 compresses a chunk: runs of bytes as they are, and copies of what's
  /// just before, written high bit first. Each starts with a copy's length, less two, in fewer bits
  /// for shorter ones, where none means a run instead, with its own length after it. A run can't
  /// follow a run shorter than the longest, so after one, the length is a copy's less three. A copy
  /// then says how far back it's from: near, further or furthest, in more bits the further into the
  /// chunk it is.
  static func expandKenCode(_ data: Data, to size: Int) -> Data? {
    var bits = KenCodeBits(data)
    var output: [UInt8] = []
    output.reserveCapacity(size)
    var runCanFollow = true
    while output.count < size {
      let length = Self.kenCodeLength(&bits)
      if length == 0 && runCanFollow {
        let count = Self.kenCodeRunLength(&bits)
        guard output.count + count <= size else {
          return nil
        }
        for _ in 0..<count {
          output.append(UInt8(bits.read(8)))
        }
        runCanFollow = count == 63
      }
      else {
        let count = length + (runCanFollow ? 2 : 3)
        let distance = Self.kenCodeDistance(&bits, at: output.count)
        guard output.count + count <= size, distance <= output.count else {
          return nil
        }
        for _ in 0..<count {
          output.append(output[output.count - distance])
        }
        runCanFollow = true
      }
      guard !bits.isPastEnd else {
        return nil
      }
    }
    return Data(output)
  }

  /// Bits, and what's added to them, for a copy's length after three ones, and each more, to ten.
  private static let kenCodeLengths = [(3, 11), (3, 19), (5, 27), (6, 59), (7, 123), (8, 251), (9, 507), (10, 1019)]

  /// A copy's length, less two: ones, up to ten, before a zero, then bits for the rest.
  private static func kenCodeLength(_ bits: inout KenCodeBits) -> Int {
    switch bits.ones(upTo: 10) {
    case 0:
      return bits.read(1)
    case 1:
      return bits.read(1) == 0 ? 2 : 3 + bits.read(1)
    case 2:
      return bits.read(1) == 0 ? 5 + bits.read(1) : 7 + bits.read(2)
    case let ones:
      let (width, added) = Self.kenCodeLengths[ones - 3]
      return added + bits.read(width)
    }
  }

  /// A run's length, from one to 63.
  private static func kenCodeRunLength(_ bits: inout KenCodeBits) -> Int {
    guard bits.read(1) == 1 else {
      return 1
    }
    switch bits.read(2) {
    case 0:
      return 2
    case 1:
      return 3
    case 2:
      return 4 + bits.read(2)
    default:
      let high = bits.read(4)
      if high < 8 {
        return 8 + high
      }
      if high < 12 {
        return high * 4 - 16 + bits.read(2)
      }
      return high * 8 - 64 + bits.read(3)
    }
  }

  /// How far into the chunk a copy has to be for how far back it's from to take a bit more.
  private static let kenCodeReaches = [0xA, 0x14, 0x28, 0x50, 0xA0, 0x2A0, 0x3E8, 0xA80, 0x1500, 0x2A00]

  /// How far back a copy `position` into the chunk is from: near, in as many bits as for how far
  /// into the chunk it is, further, in two more, or furthest, in as many as there's room for back
  /// to the chunk's start, as Disk Copy works that out.
  private static func kenCodeDistance(_ bits: inout KenCodeBits, at position: Int) -> Int {
    let width = Self.kenCodeReaches.firstIndex { position <= $0 } ?? Self.kenCodeReaches.count
    let near = 1 << width
    if bits.read(1) == 0 {
      return 1 + bits.read(width)
    }
    if bits.read(1) == 0 {
      return near + 1 + bits.read(width + 2)
    }
    // Further ones go back as far as five times near ones do, and the furthest from there.
    let further = 5 * near
    if position <= further + 2 {
      return further + 1 + bits.read(1)
    }
    if position <= further + 4 {
      return further + 1 + bits.read(2)
    }
    var level = 3
    var step = 4
    var reach = further + 4
    while level < width + 4 {
      reach += step
      // As Disk Copy does, which checks against 0x66C where this reaches 0x680.
      if position <= (reach == 0x680 ? 0x66C : reach) {
        break
      }
      step <<= 1
      level += 1
    }
    return further + 1 + bits.read(level)
  }

  /// How long a copy is, for each of the codes for one, before the bits after it that add to it.
  private static let copyLengths = [4, 5, 6, 7, 8, 10, 12, 16, 20, 28, 36, 52, 68, 100, 132, 196, 260, 388, 516, 772]
  private static let copyLengthBits = [0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8]

  /// StuffIt's compression, as ShrinkWrap 3 compresses a chunk: after a header, with how long it
  /// expands to, little-endian, a table of codes for bytes and for copies of what's just before,
  /// then a table of codes for how far back, then the codes, written low bit first. A copy's code
  /// says how long it is, roughly, with bits after it for the rest, and a code for how far back
  /// follows, with as many bits after it for the rest as its number.
  static func expandStuffIt(_ data: Data, to size: Int) -> Data? {
    guard data.littleEndian(UInt32.self, at: 4).map(Int.init) == size else {
      return nil
    }
    var bits = StuffItBits(data.dropFirst(16))
    guard let codes = StuffItCode(from: &bits, count: 256 + Self.copyLengths.count),
          let distances = StuffItCode(from: &bits, count: 16) else {
      return nil
    }
    var output: [UInt8] = []
    output.reserveCapacity(size)
    while output.count < size {
      guard let code = codes.next(from: &bits), !bits.isPastEnd else {
        return nil
      }
      if code < 256 {
        output.append(UInt8(code))
        continue
      }
      let length = Self.copyLengths[code - 256] + bits.read(Self.copyLengthBits[code - 256])
      guard let distanceCode = distances.next(from: &bits) else {
        return nil
      }
      let distance = 1 << distanceCode + bits.read(distanceCode)
      guard distance <= output.count else {
        return nil
      }
      for _ in 0..<min(length, size - output.count) {
        output.append(output[output.count - distance])
      }
    }
    return bits.isPastEnd ? nil : Data(output)
  }
}

/// Bits, high bit first, as KenCode writes them.
private struct KenCodeBits {
  private let bytes: [UInt8]
  private var position = 0
  /// Whether more's been read than there is.
  private(set) var isPastEnd = false

  init(_ data: Data) {
    self.bytes = [UInt8](data)
  }

  /// The next `width` bits, the first of them the highest.
  mutating func read(_ width: Int) -> Int {
    var value = 0
    for _ in 0..<width {
      value = value << 1 | self.bit()
    }
    return value
  }

  /// How many ones come before a zero, up to `most`, with no zero after that many.
  mutating func ones(upTo most: Int) -> Int {
    var count = 0
    while count < most && self.bit() == 1 {
      count += 1
    }
    return count
  }

  private mutating func bit() -> Int {
    guard self.position < self.bytes.count * 8 else {
      self.isPastEnd = true
      return 0
    }
    defer { self.position += 1 }
    return Int(self.bytes[self.position / 8] >> (7 - self.position % 8)) & 1
  }
}

/// Bits, low bit first, from the low bit of each byte, as StuffIt writes them, and nothing but
/// zeros after the last.
private struct StuffItBits {
  private let bytes: [UInt8]
  private var index = 0
  private var buffer: UInt64 = 0
  private var count = 0

  init(_ data: Data) {
    self.bytes = [UInt8](data)
  }

  /// Whether more's been read than there is.
  var isPastEnd: Bool {
    self.index > self.bytes.count
  }

  /// The next `width` bits, the first of them the lowest.
  mutating func read(_ width: Int) -> Int {
    while self.count < width {
      self.buffer |= UInt64(self.index < self.bytes.count ? self.bytes[self.index] : 0) << self.count
      self.index += 1
      self.count += 8
    }
    let value = Int(self.buffer & (1 << width - 1))
    self.buffer >>= width
    self.count -= width
    return value
  }

  /// Whatever's left of the byte, as a table of codes ends with it.
  mutating func skipToByte() {
    self.buffer = 0
    self.count = 0
  }
}

/// A table of StuffIt's codes, numbered from how long each is: the shortest first, from zero, each
/// one after the one before, doubled for each bit longer. Those as long as each other are in the
/// order StuffIt's quicksort leaves them in.
private struct StuffItCode {
  /// How many codes there are of each length.
  private var counts = [Int](repeating: 0, count: 33)
  /// What each stands for, in the order they're numbered.
  private let values: [Int]

  /// From how long each of `count` codes is: whether one value of a length says there's no code,
  /// how many bits each is, what's added to each, and whether they're written with codes of their
  /// own, in a table before them. The last value repeats the length before it, three times and as
  /// many more as the next says.
  init?(from bits: inout StuffItBits, count: Int, depth: Int = 0) {
    let hasNone = bits.read(1) == 1
    let width = bits.read(2) + 2
    let added = bits.read(3) + 1
    let repeated = 1 << width - 1
    let none = hasNone ? repeated - 1 : -1
    var lengthCode: StuffItCode?
    if bits.read(2) & 1 == 1 {
      guard depth < 2, let code = StuffItCode(from: &bits, count: 1 << width, depth: depth + 1) else {
        return nil
      }
      lengthCode = code
    }
    func nextValue() -> Int? {
      if let lengthCode {
        return lengthCode.next(from: &bits)
      }
      return bits.read(width)
    }

    var lengths: [Int] = []
    lengths.reserveCapacity(count)
    while lengths.count < count {
      guard let value = nextValue() else {
        return nil
      }
      if value == none {
        lengths.append(0)
      }
      else if value == repeated {
        guard let last = lengths.last, let times = nextValue() else {
          return nil
        }
        lengths += repeatElement(last, count: min(times + 3, count - lengths.count))
      }
      else {
        lengths.append(value + added)
      }
    }
    bits.skipToByte()

    var order = lengths
    var symbols = Array(lengths.indices)
    Self.sort(&order, &symbols, first: 0, last: order.count)
    for length in lengths {
      guard length <= 32 else {
        return nil
      }
      self.counts[length] += 1
    }
    self.counts[0] = 0
    // No more codes of a length than there's room for.
    var room = 1
    for length in 1...32 {
      room = room << 1 - self.counts[length]
      guard room >= 0 else {
        return nil
      }
    }
    self.values = zip(order, symbols).filter { $0.0 > 0 }.map(\.1)
  }

  /// What the next code stands for, or nil for one that isn't in the table.
  func next(from bits: inout StuffItBits) -> Int? {
    var code = 0
    var first = 0
    var index = 0
    for length in 1...32 {
      code |= bits.read(1)
      let count = self.counts[length]
      if code - first < count {
        return self.values[index + code - first]
      }
      index += count
      first = (first + count) << 1
      code <<= 1
    }
    return nil
  }

  /// Codes by length, as StuffIt sorts them, which puts those as long as each other in an order of
  /// its own, and so numbers them in it.
  private static func sort(_ lengths: inout [Int], _ values: inout [Int], first: Int, last: Int) {
    var first = first
    var last = last
    while last - first > 1 {
      var i = first
      var j = last
      repeat {
        i += 1
        while i < last && lengths[first] > lengths[i] {
          i += 1
        }
        j -= 1
        while j > first && lengths[first] < lengths[j] {
          j -= 1
        }
        if j > i {
          lengths.swapAt(i, j)
          values.swapAt(i, j)
        }
      } while j > i
      guard first != j else {
        first += 1
        continue
      }
      lengths.swapAt(first, j)
      values.swapAt(first, j)
      i = j + 1
      // The shorter side first, and the longer side next, here.
      if last - i <= j - first {
        self.sort(&lengths, &values, first: i, last: last)
        last = j
      }
      else {
        self.sort(&lengths, &values, first: first, last: j)
        first = i
      }
    }
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
