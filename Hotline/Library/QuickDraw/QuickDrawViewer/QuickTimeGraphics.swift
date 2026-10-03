//
//  QuickTimeGraphics.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 08.03.2024.
//
// Decode the QuickTime Graphics codec (SMC).
// See https://wiki.multimedia.cx/index.php/Apple_SMC

import Foundation

enum QuickTimeGraphicsError : Error {
  case invalidBlockData(data: [UInt8]);
  case invalidCacheEntry(entry: [UInt8]);
  case unknownOpcode(opcode: UInt8);
}

class QuickTimeGraphicsColorCache {
  
  init(entrySize: Int) {
    self.entrySize = entrySize;
    let zeroEntry = [UInt8].init(repeating: 0, count: entrySize);
    self.entries = [[UInt8]].init(repeating: zeroEntry, count: 256);
  }
  
  func add(entry: [UInt8]) throws {
    guard entry.count == self.entrySize else {
      throw QuickTimeGraphicsError.invalidCacheEntry(entry: entry);
    }
    entries[pos] = entry;
    pos = (pos + 1) % 256;
  }
  
  func lookup(index: UInt8) -> [UInt8] {
    return entries[Int(index)];
  }
  
  var entries : [[UInt8]];
  
  let entrySize : Int;
  var pos : Int = 0;
}

/// QuickTime `Graphics` codec.
class QuickTimeGraphicsImage : BlockPixMap, @unchecked Sendable {
  
  init(dimensions: QDDelta, clut: QDColorTable) {
    super.init(dimensions: dimensions, blockSize: 4, pixelSize: 8, cmpSize: 8, clut: clut);
  }
  
  func toRange(blockNum: Int, lineNum: Int) throws -> Range<Int> {
    let start = try getOffset(block: blockNum, line: lineNum);
    let end = start + blockSize;
    return start..<end;
  }
  
  func readBlockLine(blockNum: Int, lineNum: Int) throws -> ArraySlice<UInt8> {
    let r = try toRange(blockNum: blockNum, lineNum: lineNum);
    return pixmap[r];
  }
  
  func readBlock(blockNum: Int) throws -> [UInt8] {
    var block : [UInt8] = [];
    for line in 0..<blockSize {
      block.append(contentsOf: try readBlockLine(blockNum: blockNum, lineNum: line))
    }
    return block;
  }
  
  func writeBlockLine(blockNum: Int, lineNum: Int, values: ArraySlice<UInt8>) throws {
    let r = try toRange(blockNum: blockNum, lineNum: lineNum);
    for (position, value) in zip(r, values) {
      pixmap[position] = value;
    }
  }
  
  func writeBlock(blockNum: Int, values: [UInt8]) throws {
    guard blockNum < totalBlocks else {
      return;
    }
    
    guard values.count == 16 else {
      throw QuickTimeGraphicsError.invalidBlockData(data: values);
    }
    
    for line in 0..<blockSize {
      let start = line * blockSize;
      let end = start + blockSize;
      try writeBlockLine(blockNum: blockNum, lineNum: line, values: values[start..<end]);
    }
  }
  
  func write2ColorBlock(blockNum: Int, colorIndexes: [UInt8], data: UInt16) throws {
    var buffer = data;
    var values : [UInt8] = [];
    for _ in 0..<16 {
      let index = Int((buffer & 0xa000) >> 15);
      assert(index < 2);
      buffer = buffer >> 1;
      values.append(colorIndexes[index]);
    }
    try writeBlock(blockNum: blockNum, values: values);
  }

  func write4ColorBlock(blockNum: Int, colorIndexes: [UInt8], data: UInt32) throws {
    var buffer = data;
    var values : [UInt8] = [];
    for _ in 0..<16 {
      let index = Int((buffer & 0xC000) >> 30);
      assert(index < 4);
      buffer = buffer >> 2;
      values.append(colorIndexes[index]);
    }
    try writeBlock(blockNum: blockNum, values: values);
  }
  
  func convert8ColorBlockWord(bytes: (UInt8, UInt8, UInt8), colorIndexes: [UInt8]) -> [UInt8]{
    var word = makeUInt24(bytes: bytes);
    var values : [UInt8] = [];
    for _ in 0..<8 {
      let index = Int((0xe00000 & word) >> 21);
      let color = colorIndexes[index];
      values.append(color);
      word = word << 3;
    }
    return values;
  }

  func write8ColorBlock(blockNum: Int, colorIndexes: [UInt8], data: [UInt8]) throws {
    let av = (
        data[0],
        data[1] & 0xf0 | data[2] & 0x0f,
        (data[2] & 0x0f) << 4 | data[3] >> 4);
    let bv = (
        data[4],
        data[5] & 0xf0 | data[1] & 0x0f,
        (data[3] & 0xf0) << 4 | (data[5] & 0xf0));
    var values : [UInt8] = convert8ColorBlockWord(bytes: av, colorIndexes: colorIndexes);
    values.append(contentsOf: convert8ColorBlockWord(bytes: bv, colorIndexes: colorIndexes));
    try writeBlock(blockNum: blockNum, values: values);
  }
  
  func load(data : consuming Data) throws {
    let reader = try QuickDrawDataReader(data: data, position: 4);
    var currentBlock = 0;
    while reader.remaining > 2 && currentBlock < totalBlocks {
      let v = try reader.readUInt8();
      let opcode = v & 0xf0;
      let n = Int(v & 0x0f) + 1;
      switch opcode {
      case 0x00:
        currentBlock += n;
      case 0x10:
        let skip = try reader.readUInt8();
        currentBlock += Int(skip);
      case 0x20:
        let last = try readBlock(blockNum: currentBlock - 1);
        for _ in 0..<n {
          try writeBlock(blockNum: currentBlock, values: last);
          currentBlock+=1;
        }
      case 0x30:
        let last = try readBlock(blockNum: currentBlock - 1);
        let nn = try Int(reader.readUInt8()) + 1;
        for _ in 0..<nn {
          try writeBlock(blockNum: currentBlock, values: last);
          currentBlock+=1;
        }
      case 0x40:
        let last1 = try readBlock(blockNum: currentBlock - 2);
        let last2 = try readBlock(blockNum: currentBlock - 1);
        for _ in 0..<n {
          try writeBlock(blockNum: currentBlock, values: last1);
          currentBlock+=1;
          try writeBlock(blockNum: currentBlock, values: last2);
          currentBlock+=1;
        }
      case 0x50:
        let last1 = try readBlock(blockNum: currentBlock - 2);
        let last2 = try readBlock(blockNum: currentBlock - 1);
        let nn = try Int(reader.readUInt8()) + 1;
        for _ in 0..<nn {
          try writeBlock(blockNum: currentBlock, values: last1);
          currentBlock+=1;
          try writeBlock(blockNum: currentBlock, values: last2);
          currentBlock+=1;
        }
      case 0x60:
        let index = try reader.readUInt8();
        let block = [UInt8].init(repeating: index, count: 16);
        for _ in 0..<n {
          try writeBlock(blockNum: currentBlock, values: block);
          currentBlock+=1;
        }
      case 0x70:
        let nn = try Int(reader.readUInt8()) + 1;
        let index = try reader.readUInt8();
        let block = [UInt8].init(repeating: index, count: 16);
        for _ in 0..<nn {
          try writeBlock(blockNum: currentBlock, values: block);
          currentBlock+=1;
        }
      /// 2 Colors / block
      case 0x80:
        let colorIndexes = try reader.readUInt8(bytes: 2);
        for _ in 0..<n {
          let data = try reader.readUInt16();
          try write2ColorBlock(blockNum: currentBlock, colorIndexes: colorIndexes, data: data);
          currentBlock+=1;
        }
        try color2Cache.add(entry: colorIndexes);
      case 0x90:
        let cacheIndex = try reader.readUInt8();
        let colorIndexes = color2Cache.lookup(index: cacheIndex);
        for _ in 0..<n {
          let data = try reader.readUInt16();
          try write2ColorBlock(blockNum: currentBlock, colorIndexes: colorIndexes, data: data);
          currentBlock+=1;
        }
      /// 4 Color / block
      case 0xA0:
        let colorIndexes = try reader.readUInt8(bytes: 4);
        for _ in 0..<n {
          let data = try reader.readUInt32();
          try write4ColorBlock(blockNum: currentBlock, colorIndexes: colorIndexes, data: data);
          currentBlock+=1;
        }
        try color4Cache.add(entry: colorIndexes);
      case 0xB0:
        let cacheIndex = try reader.readUInt8();
        let colorIndexes = color4Cache.lookup(index: cacheIndex);
        for _ in 0..<n {
          let data = try reader.readUInt32();
          try write4ColorBlock(blockNum: currentBlock, colorIndexes: colorIndexes, data: data);
          currentBlock+=1;
        }
      /// 8 Color / block
      case 0xC0:
        let colorIndexes = try reader.readUInt8(bytes: 8);
        for _ in 0..<n {
          let data = try reader.readUInt8(bytes: 6);
          try write8ColorBlock(blockNum: currentBlock, colorIndexes: colorIndexes, data: data);
          currentBlock+=1;
        }
        try color8Cache.add(entry: colorIndexes);
      case 0xD0:
        let cacheIndex = try reader.readUInt8();
        let colorIndexes = color8Cache.lookup(index: cacheIndex);
        for _ in 0..<n {
          let data = try reader.readUInt8(bytes: 6);
          try write8ColorBlock(blockNum: currentBlock, colorIndexes: colorIndexes, data: data);
          currentBlock+=1;
        }
      case 0xE0, 0xF0:
        for _ in 0..<n {
          let data = try reader.readUInt8(bytes: 16);
          try writeBlock(blockNum: currentBlock, values: data);
          currentBlock+=1;
        }
      default:
        throw QuickTimeGraphicsError.unknownOpcode(opcode: opcode);
      }
    }
  }
  
  let color2Cache = QuickTimeGraphicsColorCache(entrySize: 2);
  let color4Cache = QuickTimeGraphicsColorCache(entrySize: 4);
  let color8Cache = QuickTimeGraphicsColorCache(entrySize: 8);
  
  override var  description: String {
    return "QuickTimeGraphicsImage " + super.description;
  }
}
