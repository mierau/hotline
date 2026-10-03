//
//  RoadPizza.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 24.01.2024.
//

import Foundation

enum RoadPizzaError : Error {
  case badMagic(magic: UInt8);
  case unknownOpcode(opcode: UInt8);
  case badPixMapIndex(index: Int);
  case invalidPixelLineSize(count: Int);
  case invalidColorTableSize(count: Int);
  case invalidColorDirectSize(count: Int);
}

/// Image compressed with the RPZA (RoadPizza) compression.
/// Decode the sequence of opcodes into a ARGB555 buffer.
/// Skipped blocks will have transparent pixels.
class RoadPizzaImage : BlockPixMap, @unchecked Sendable {

  init(dimensions: QDDelta) {
    super.init(dimensions: dimensions, blockSize: 4, pixelSize: ARGB555.pixelSize, cmpSize: ARGB555.componentSize, clut: nil);
  }

  /// Creates a ARGB555 color that is ⅔ color a and ⅓ color b.
  /// - Parameters:
  ///   - a: color to mix ⅔ from
  ///   - b: color to mix ⅓ from
  /// - Returns: a color which is on the line in RGB space between a and b.
  private static func mix⅔(_ a: SIMD3<UInt8>, _ b: SIMD3<UInt8>) -> ARGB555 {
    let aa = SIMD3<UInt16>.init(clamping: a) &* RoadPizzaImage.m21;
    let bb = SIMD3<UInt16>.init(clamping: b) &* RoadPizzaImage.m11;
    let mix = SIMD3<UInt8>(clamping: (aa &+ bb) &>> RoadPizzaImage.m5);
    return ARGB555(simd: mix);
  }

  /// Function that writes a line of pixels from a block into the buffer.
  /// - Parameters:
  ///   - block: block number
  ///   - line: line number within the block
  ///   - color4: slice of 4 pixels
  private func writePixelLine(block: Int, line: Int, color4: ArraySlice<ARGB555>) throws {
    guard color4.count == blockSize else {
      throw RoadPizzaError.invalidPixelLineSize(count: color4.count);
    }
    let p = try getOffset(block: block, line: line);
    for (index, value) in color4.enumerated() {
      let rawValue = value.rawValue;
      pixmap[p + (index * 2)] =  UInt8(rawValue >> 8);
      pixmap[p + (index * 2) + 1] = UInt8(rawValue & 0xff);
    }
  }
  
  private static let m21 = SIMD3<UInt16>.init(repeating: 21);
  private static let m11 = SIMD3<UInt16>.init(repeating: 11);
  private static let m5 = SIMD3<UInt16>.init(repeating: 5);

  private func makeColorTable(colorA: ARGB555, colorB: ARGB555) -> [ARGB555] {
    let simda = colorA.simdValue;
    let simdb = colorB.simdValue;
    return  [
      colorB, RoadPizzaImage.mix⅔(simdb, simda), RoadPizzaImage.mix⅔(simda, simdb), colorA];
  }
  
  private func execute1Color(block: Int, color: ARGB555) throws {
    let color4 = [ARGB555].init(repeating: color, count: blockSize);
    for line in 0..<blockSize {
      try writePixelLine(block: block, line: line, color4: color4[0..<4]);
    }
  }
  
  private func executeIndexColor(block: Int, colorA: ARGB555, colorB: ARGB555, data: [UInt8]) throws {
    guard data.count == blockSize else {
      throw RoadPizzaError.invalidColorTableSize(count: data.count);
    }
    let colorTable : [ARGB555] = makeColorTable(colorA: colorA, colorB: colorB);
    for (line, value) in data.enumerated() {
      var color4 : [ARGB555] = [];
      var shiftedValue = Int(value);
      for _ in 0..<blockSize {
        let index = Int((shiftedValue & 0xc0) >> 6);
        color4.append(colorTable[index]);
        shiftedValue = shiftedValue << 2;
      }
      try writePixelLine(block: block, line: line, color4: color4[0..<4]);
    }
  }
  
  private func executeDirectColor(block: Int, data: [ARGB555]) throws {
    guard data.count == blockSize * blockSize else {
      throw RoadPizzaError.invalidColorDirectSize(count: data.count);
    }
    for line in 0..<blockSize {
      try writePixelLine(block: block, line: line, color4: data[line*4..<(line + 1)*4]);
    }
  }
  
  func load(data : consuming Data) throws {
    let reader = try QuickDrawDataReader(data: data, position: 0);
    let magic = try reader.readUInt8();
    guard magic == 0xe1 else {
      throw RoadPizzaError.badMagic(magic: magic);
    }
    reader.skip(bytes: 3);  // Length
    var block = 0;
    var colorA = ARGB555.zero;
    var colorB = ARGB555.zero;
    
    while reader.remaining > 1 {
      let rawOpcode = try reader.readUInt8();
      let opcode = rawOpcode & 0xe0;
      let blockCount = Int(rawOpcode & 0x1f) + 1;
      switch opcode {
      case let lowbit  where lowbit & 0x80 == 0:
        /// Special case: colorA is encoded in rawOpcode + 1 byte
        let v = UInt16(rawOpcode) << 8 | UInt16(try reader.readUInt8()) | 0x8000;
        colorA = ARGB555(rawValue: v);
        if (try reader.peekUInt8() & 0x80) != 0 {
          /// Special case of palette block
          colorB = try reader.ReadRGB555();
          let data = try reader.readUInt8(bytes: blockSize);
          try executeIndexColor(block: block, colorA: colorA, colorB: colorB, data: data);
          block += 1;
        } else {
          /// Direct AGRB data, colorA is the first.
          var data : [ARGB555] = [colorA];
          for _ in 0..<15 {
            data.append(try reader.ReadRGB555());
          }
          try executeDirectColor(block: block, data: data);
          block += 1;
        }
      case 0x80:  /// Skip the block
        block += blockCount;
      case 0xa0:  /// Single color block(s)
        colorA = try reader.ReadRGB555();
        for i in block..<block + blockCount {
          try execute1Color(block: i, color: colorA);
        }
        block += blockCount;
      case 0xc0:  /// Index color blocks
        colorA = try reader.ReadRGB555();
        colorB = try reader.ReadRGB555();
        for i in block..<block + blockCount {
          let data = try reader.readUInt8(bytes: 4);
          try executeIndexColor(block: i, colorA: colorA, colorB: colorB, data: data);
        }
        block += blockCount;
      default:
        throw RoadPizzaError.unknownOpcode(opcode: opcode);
      }
    }
  }
  
  override var description: String {
    return "RPZA: " + super.description;
  }
}
