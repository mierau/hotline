//
//  Cinepak.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 07.04.2024.
//

/// Cinepak codec, see https://multimedia.cx/mirror/cinepak.txt

import Foundation

enum CinepakError : Error {
  case inconsistentHeight(frame : QDDelta, height: UInt16);
  case inconsistentWidth(frame : QDDelta, width: UInt16);
  case inconsistentSize(container: Int, header: Int);
  case tooManyStrips(strips: UInt16);
  case tooManyCodebookEntries(number: Int);
  case invalidStripId(_ id: UInt16);
  case invalidChunkId(_ id: UInt16, strip: CinepakStripeDescriptor);
  case codeBookOutOfRange(_ index: UInt8, max: Int, name: String);
  case unsupportChunkType(_ type: CinepakChunk.ChunkType);
}

/// A cinepak is divided in stripes which describe a band of the picture.
class CinepakStripeDescriptor: CustomStringConvertible, @unchecked Sendable {
  enum StripeType : UInt16 {
    // Stripe that describes its own codebook entries.
    case intraCodedStrip = 0x1000;
    // Stripe that updates codebooks from the previous entries.
    case interCodedStrip = 0x1100;
  }
  
  init(stripeType : StripeType, stripeSize : UInt16, stripeFrame : QDRect) {
    self.stripeType = stripeType;
    self.stripeSize = stripeSize;
    self.stripeFrame = stripeFrame;
  }
  
  let stripeType : StripeType;
  let stripeSize : UInt16;
  let stripeFrame : QDRect;
  var chunks : [CinepakChunk] = [];
  
  var description: String {
    return "Strip[type: \(stripeType), size: \(stripeSize), frame: \(stripeFrame), chunks: \(chunks)";
  }
}

struct CinepakChunk : CustomStringConvertible  {

  // Instead of an enum, the chunk type is represented as a kind-of bitset.
  struct ChunkType : OptionSet, CustomStringConvertible {
    let rawValue: UInt16;
    static let codebook = ChunkType(rawValue:0x2000);
    static let vectors = ChunkType(rawValue: 0x1000);
    static let eightBpp = ChunkType(rawValue: 0x0400);
    static let v1 = ChunkType(rawValue: 0x0200);
    static let update = ChunkType(rawValue: 0x0100);
    
    var description: String {
      var result = String(format:"%X", arguments: [rawValue]);
      
      if contains(.vectors) {
        result += " Vectors";
        return result;
      }
      if contains(.codebook) {
        result += " Codebook";
      }
      
      if contains(.eightBpp) {
        result += " 8bpp";
      } else {
        result += " 12bpp";
      }
      if contains(.v1) {
        result += " v1";
      } else {
        result += " v4";
      }
      
      if contains(.update) {
        result += " Update";
      }
      return result;
      
    }
  }
  
  let chunkType : ChunkType;
  let chunkData : Data;
  
  var size : Int {
    return chunkData.count;
  }
  
  var description: String {
    return chunkType.description;
  }
  
}

/// Codebook entry, basically stores a 2×2 square of pixels.
/// The entry can either by just intensity/palette entry (8 bpp) or intensity + common chroma.
///  Intensities are stored in SIMD format, mostly because I wanted to play around.
struct CinepakCodeBookEntry {
  
  private enum CodeBookPayload {
    case eight(y: SIMD4<UInt8>);
    case twelve(y: SIMD4<UInt8>, u: Int8, v: Int8);
    case uninitialized(rgb: RGB8);  // Should never been seen, for debugging
  }
  
  /// Initialize an entry with four 4 8-bit values, either intensity, or palette entries.
  /// - Parameter y4: 4 8-bit values, either intensity, or palette entries.
  init(y4 : [UInt8]) {
    assert(y4.count == 4);
    self.payload = .eight(y: SIMD4<UInt8>(y4[0], y4[1], y4[2], y4[3]))
  }
  
  /// Initialize an entry with four 6, 8-bit values, four intensities and two chrominance bytes (u, v).
  /// - Parameters:
  ///   - y4: intensities (unsigned)
  ///   - u: u chrominance value (signed)
  ///   - v: v chrominance value (signed)
  init(y4 : [UInt8], u : Int8, v: Int8) {
    assert(y4.count == 4);
    let y = SIMD4<UInt8>(y4[0], y4[1], y4[2], y4[3]);
    self.payload = .twelve(y: y, u: u, v: v);
  }
  
  private init(y: UInt8, u: Int8, v: Int8) {
    self.init(y4: [UInt8](repeating: y, count: 4), u:u, v:v);
  }
  
  private init(y: UInt8) {
    self.init(y4: [UInt8](repeating: y, count: 4));
  }
  
  /// Create an uninitialized entry, used for debugging.
  /// - Parameter uninitialized: rgb value to makr unitialized entry.
  private init(uninitialized: RGB8) {
    self.payload = .uninitialized(rgb: uninitialized);
  }
  
  /// The intensities (or palette indexes) of the entry.
  var y : [UInt8] {
    switch payload {
      case .eight(let y):
        return y.bytes;
      case .twelve(let y, _, _):
        return y.bytes;
      case .uninitialized:
        return [0, 0, 0, 0];
    }
  }
  
  /// The four pixels in RGB8 format.
  /// Note that cinepak uses a simplified version of yuv.
  var rgb : [RGB8] {
    switch payload {
      case .eight(let y):
        return y.bytes.map(){RGB8(r: $0, g: $0, b:$0)};
      case .twelve(let y, let u, let v):
        // Decode cinepak YUV
        let u4 = SIMD4<Int16>.init(repeating: Int16(u));
        let v4 = SIMD4<Int16>.init(repeating: Int16(v));
        let one = SIMD4<Int16>.one;
        let y4 = SIMD4<Int16>.init(clamping: y);
        let r = SIMD4<UInt8>(clamping: y4 &+ (v4 &<< one));
        let g = SIMD4<UInt8>(clamping: y4 &- (u4 &>> one) &- v4);
        let b = SIMD4<UInt8>(clamping: y4 &+ (u4 &<< one));
        return toRGB8(r: r, g: g, b: b);
      case .uninitialized(let rgb):
        return [RGB8].init(repeating: rgb, count: 4);
    }
  }
  
  /// Return 4 codebook entries corresponding to this one.
  var doubled : [CinepakCodeBookEntry] {
    switch payload {
      case .eight(let y):
        return y.bytes.map(){CinepakCodeBookEntry(y:$0)};
      case .twelve(let y, let u, let v):
        return y.bytes.map(){CinepakCodeBookEntry(y:$0, u: u, v: v)};
      case .uninitialized:
        return [CinepakCodeBookEntry](repeating: self, count: 4);
    }
  }

  private let payload: CodeBookPayload;
  static let uninitialized = CinepakCodeBookEntry(uninitialized: RGB8(r: 0xff, g: 0x00, b: 0xff));
}

/// A code-book is a collection of 2×2 pixel patterns, see the CinepakCodeBookEntry struct .
class CinepakCodeBook {
  init(name: String) {
    self.name = name;
    entries = [CinepakCodeBookEntry].init(repeating: CinepakCodeBookEntry.uninitialized, count: 256);
  }
  
  func readEntries(count: Int, chunkType: CinepakChunk.ChunkType, reader : QuickDrawDataReader) throws {
    for i in 0..<count {
      let entry = try reader.readCinepakCodeBookEntry(chunkType: chunkType);
      entries[i] = entry;
    }
  }
  
  func updateEntries(chunkType: CinepakChunk.ChunkType, reader : QuickDrawDataReader) throws {
    var pos = 0;
    while reader.remaining > 4 {
      for v in boolArray(try reader.readUInt32()) {
        if v {
          let entry = try reader.readCinepakCodeBookEntry(chunkType: chunkType);
          entries[pos] = entry;
        }
        pos += 1;
      }
    }
  }
  
  func lookup(_ index : UInt8) throws -> CinepakCodeBookEntry {
    guard index < entries.count else {
      throw CinepakError.codeBookOutOfRange(index, max: entries.count, name: name);
    }
    return entries[Int(index)]
  }
  
  let name : String;
  var entries : [CinepakCodeBookEntry];
}

extension QuickDrawDataReader {
  func readCinepakStripHeader(vOffset : FixedPoint) throws -> CinepakStripeDescriptor {
    let rawId = try readUInt16();
    guard let stripeType = CinepakStripeDescriptor.StripeType(rawValue: rawId) else {
      throw CinepakError.invalidStripId(rawId);
    }
    let size = try readUInt16() - 12;
    var frame = try readRect();
    frame = frame + QDDelta(dv: vOffset, dh: FixedPoint.zero);
    return CinepakStripeDescriptor(stripeType: stripeType, stripeSize: size, stripeFrame: frame);
  }

  func readCinepakCodeBookEntry(chunkType: CinepakChunk.ChunkType) throws -> CinepakCodeBookEntry{
    let y4 = try readUInt8(bytes: 4);
    if chunkType.contains(.eightBpp) {
      return CinepakCodeBookEntry(y4: y4);
    }
    let u = try readInt8();
    let v = try readInt8();
    return CinepakCodeBookEntry(y4: y4, u: u, v: v);
  }
}


/// A cinepak image is composed of 4×4 blocks, which are filled either using
/// * one 2×2 codebook entries (doubled),
/// * four 2×2 code book entries, each block
class Cinepak : BlockPixMap, @unchecked Sendable{
  init(dimensions: QDDelta, clut: QDColorTable?) {
    components = clut != nil ? CinepakComponents.index : CinepakComponents.rgb;
    super.init(dimensions: dimensions, blockSize: 4, pixelSize: components.rawValue * 8, cmpSize: 8, clut: clut);
  }
  
  enum CinepakComponents : Int {
    case index = 1;
    case rgb = 3;
  }
  
  func apply(entry: CinepakCodeBookEntry, pos: Int, offset: Int) throws {
    let max = offset + self.components.rawValue;
    guard max <= pixmap.count else {
      throw BlittingError.badPixMapIndex(index: max, pixMapSize: pixmap.count);
    }
    switch components {
      case .index:
        pixmap[offset] = entry.y[pos];
      case .rgb:
        let rgb = entry.rgb[pos]
        pixmap[offset] = rgb.r;
        pixmap[offset + 1] = rgb.g;
        pixmap[offset + 2] = rgb.b;
    }
  }
  
  func applyEntries(block: Int, entries : [CinepakCodeBookEntry]) throws {
    let lines = [0, 1, 2, 3];
    let lineOffsets = try lines.map(){try getOffset(block: block, line: $0);}
    let pixOffset = components.rawValue;
    // First line, entries 0 and 1.
    try apply(entry: entries[0], pos: 0, offset: lineOffsets[0]);
    try apply(entry: entries[0], pos: 1, offset: lineOffsets[0] + pixOffset);
    try apply(entry: entries[1], pos: 0, offset: lineOffsets[0] + pixOffset * 2);
    try apply(entry: entries[1], pos: 1, offset: lineOffsets[0] + pixOffset * 3);
    // Second line, entries 0 and 1.
    try apply(entry: entries[0], pos: 2, offset: lineOffsets[1]);
    try apply(entry: entries[0], pos: 3, offset: lineOffsets[1] + pixOffset);
    try apply(entry: entries[1], pos: 2, offset: lineOffsets[1] + pixOffset * 2);
    try apply(entry: entries[1], pos: 3, offset: lineOffsets[1] + pixOffset * 3);
    // Third line, entries 2 and 3.
    try apply(entry: entries[2], pos: 0, offset: lineOffsets[2]);
    try apply(entry: entries[2], pos: 1, offset: lineOffsets[2] + pixOffset);
    try apply(entry: entries[3], pos: 0, offset: lineOffsets[2] + pixOffset * 2);
    try apply(entry: entries[3], pos: 1, offset: lineOffsets[2] + pixOffset * 3);
    // Fourth line, entries 2 and 3.
    try apply(entry: entries[2], pos: 2, offset: lineOffsets[3]);
    try apply(entry: entries[2], pos: 3, offset: lineOffsets[3] + pixOffset);
    try apply(entry: entries[3], pos: 2, offset: lineOffsets[3] + pixOffset * 2);
    try apply(entry: entries[3], pos: 3, offset: lineOffsets[3] + pixOffset * 3);
  }

  func applyV4(block: Int, v4: [UInt8]) throws {
    assert(v4.count == 4);
    guard block < totalBlocks else {
      return;
    }
    let entries = try v4.map(){try v4Codebook.lookup($0)};
    try applyEntries(block: block, entries: entries)
  }
  
  func applyV1(block: Int, v1: UInt8) throws {
    guard block < totalBlocks else {
      return;
    }
    let entry = try v1Codebook.lookup(v1);
    let entries = entry.doubled;
    try applyEntries(block: block, entries: entries)
  }
  
  func applyVectorBlock(reader : QuickDrawDataReader) throws -> Bool {
    let mask = try reader.readUInt32();
    for v in boolArray(mask) {
      if v {
        guard reader.remaining >= 4 else {
          return false;
        }
        let v4 = try reader.readUInt8(bytes: 4);
        try applyV4(block: self.block, v4: v4);
      } else {
        guard reader.remaining >= 1 else {
          return false;
        }
        let v1 = try reader.readUInt8();
        try applyV1(block: self.block, v1: v1);
      }
      self.block += 1;
    }
    return true;
  }
  
  func applyVectors(strip: CinepakStripeDescriptor, reader : QuickDrawDataReader) throws {
    while true {
      guard reader.remaining >= 4 else {
        return;
      }
      let fullRead = try applyVectorBlock(reader: reader);
      guard fullRead else {
        return;
      }
    }
  }
  
  /// Parse a single chunk
  func parseChunk(strip: CinepakStripeDescriptor, chunk: CinepakChunk) throws {
    let reader = try QuickDrawDataReader(data: chunk.chunkData, position: 0);
    switch chunk.chunkType {
      /// The chunk contains vectors, i.e. entry indexes, not exclusively for v1.
      case let c where c.contains(.vectors) && !c.contains(.v1):
        try applyVectors(strip: strip, reader: reader);
      /// The chunk contains a codebook definition (not update)
      case let c where c.contains(.codebook) && !c.contains(.update):
        let numEntries = c.contains(.eightBpp) ? (chunk.size / 4) : (chunk.size / 6);
        guard numEntries <= 256 else {
          throw CinepakError.tooManyCodebookEntries(number: numEntries);
        }
        if c.contains(.v1) {
          try v1Codebook.readEntries(count: numEntries, chunkType: chunk.chunkType, reader: reader);
        } else {
          try v4Codebook.readEntries(count: numEntries, chunkType: chunk.chunkType, reader: reader);
        }
      /// The chunk contains codebook updates.
      case let c where c.contains(.codebook) && c.contains(.update):
        if c.contains(.v1) {
          try v1Codebook.updateEntries(chunkType: chunk.chunkType, reader: reader);
        } else {
          try v4Codebook.updateEntries(chunkType: chunk.chunkType, reader: reader);
        }
      default:
        throw CinepakError.unsupportChunkType(chunk.chunkType);
    }
  }
    
  func loadStripe(stripe: CinepakStripeDescriptor, reader : QuickDrawDataReader) throws {
    assert (reader.data.count == stripe.stripeSize);
    while reader.remaining >= 16 {
      let rawId = try reader.readUInt16();
      let chunkType = CinepakChunk.ChunkType(rawValue: rawId);
      let chunkSize = Int(try reader.readUInt16() - 4);
      let data = try reader.readData(bytes: chunkSize);
      let chunk = CinepakChunk(chunkType: chunkType, chunkData: data);
      stripe.chunks.append(chunk);
      try parseChunk(strip: stripe, chunk: chunk);
    }
  }
  
  func load(data : consuming Data) throws {
    let reader = try QuickDrawDataReader(data: data, position: 0);
    self.flags = try reader.readUInt8();
    let sizeHigh = Int(try reader.readUInt8());
    let sizeLow = Int(try reader.readUInt16());
    let size = sizeLow & (sizeHigh << 16);
    guard size == 0 || size == reader.data.count else {
      throw CinepakError.inconsistentSize(container: reader.data.count, header: size);
    }
    let width = try reader.readUInt16();
    guard Int(width) == self.bufferDimensions.dh.rounded else {
      throw CinepakError.inconsistentWidth(frame:self.bufferDimensions, width:width);
    }
    let height = try reader.readUInt16();
    guard Int(height) == self.bufferDimensions.dv.rounded else {
      throw CinepakError.inconsistentHeight(frame:self.bufferDimensions, height:height);
    }
    let stripNumber = try reader.readUInt16();
    guard stripNumber <= 32 else {
      throw CinepakError.tooManyStrips(strips: stripNumber);
    }
    var y = FixedPoint.zero;
    for _ in 0..<stripNumber {
      // Re-sychronize the block numbers.
      block = (y.rounded / 4) * blocksPerLine;
      let stripeHeader = try reader.readCinepakStripHeader(vOffset: y);
      let stripReader = try reader.subReader(bytes: Int(stripeHeader.stripeSize));
      try loadStripe(stripe: stripeHeader, reader: stripReader);
      stripes.append(stripeHeader);
      y += stripeHeader.stripeFrame.dimensions.dv;
    }
  }
  
  override var description: String {
    let desc = describePixMap(self);
    return "Cinepack \(desc) \(blockSize)×\(blockSize), \(stripes) flags: \(flags)";
  }
  
  let components : CinepakComponents;
  var v1Codebook = CinepakCodeBook(name: "v1");
  var v4Codebook = CinepakCodeBook(name: "v4");
  var stripes : [CinepakStripeDescriptor] = [];
  var flags : UInt8 = 0;
  var block : Int = 0;
}
