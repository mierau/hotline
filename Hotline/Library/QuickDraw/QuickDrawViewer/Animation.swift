//
//  Animation.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 06.03.2024.
//
// Decoder for the `RLE ` "Animation" codec.
// See https://wiki.multimedia.cx/index.php/Apple_QuickTime_RLE

import Foundation

enum AnimationCodecError : Error {
  case unknownPackBitStride(depth: Int);
  case unknownPackBitOpcode(code: Int8);
  case invalidXCoordinate(x: Int, dimensions: QDDelta);
  case outOfBoundWrite(x: Int, y: Int, length: Int);
}


// TODO: depth = 1 bits per pixels does not work.
class AnimationImage : PixMapMetadata, @unchecked Sendable {
  init(dimensions: QDDelta, depth: Int, clut: QDColorTable?) throws {
    self.dimensions = dimensions;
    self.depth = depth;
    self.clut =  clut;
    self.pixmap = [];
    let (_, componentSize) = try expandDepth(depth);
    self.cmpSize = componentSize;
  }
  
  var pixelSize: Int {
    return depth;
  }
  
  func packBitStride() throws -> Int {
    switch depth {
    case 1: return 2;
    case 2: return 4;
    case 4: return 4;
    case 8: return 4;
    case 16: return 2;
    case 24: return 3;
    case 32: return 4;
    default:
      throw AnimationCodecError.unknownPackBitStride(depth: depth);
    }
  }
  
  func writeStride(x: Int, y: Int, data: ArraySlice<UInt8>) throws {
    guard x < dimensions.dh.rounded else {
      throw AnimationCodecError.invalidXCoordinate(x:x, dimensions: dimensions);
    }
    let offset = (y * rowBytes) + (x * depth / 8);
    for (i, v) in data.enumerated() {
      guard offset + i < pixmap.count else {
        throw AnimationCodecError.outOfBoundWrite(x:x, y:y,length:  i);
      }
      // In ARGB mode, the alpha is always 0, set it to 0xff
      if depth == 32 && i % 4 == 0 {
        pixmap[offset + i] = 0xff;
      } else {
        pixmap[offset + i] = v;
      }
    }
  }
  
  func parseRunLength(data : ArraySlice<UInt8>, x: inout Int, y: inout Int) throws -> Int {
    let stride = try packBitStride();
    var index = data.startIndex;
    while index < data.endIndex - 1 {
      var decompressed : [UInt8] = [];
      let code = Int8(bitPattern: data[index]);
      index += 1;
      switch code {
      case 0: return index - data.startIndex ;
      case -1:
        x = 0; y += 1; return index - data.startIndex;
      case let v where v > 0:
        let tail = data[index...];
        guard tail.count >= stride + 1 else {
          return index - data.startIndex;
        }
        index += try copyDiscrete(length: Int(code), src: tail, destination: &decompressed, byteNum: stride);
      case let v where v < -1:
        let tail = data[index...];
        guard tail.count >= stride + 1 else {
          return index - data.startIndex;
        }
        index += try copyRepeated(length: -Int(code) , src: tail, destination: &decompressed, byteNum: stride);
      default:
        throw AnimationCodecError.unknownPackBitOpcode(code: code);
      }
      try writeStride(x: x, y:y, data: decompressed[0...]);
      x += (decompressed.count * 8 / depth);
    }
    return index - data.startIndex;
  }
  
  func load(data : consuming Data) throws {
    let s = rowBytes * (dimensions.dv.rounded + 1);
    pixmap = Array<UInt8>(repeating: UInt8.zero, count: s);
    let reader = try QuickDrawDataReader(data: data, position:0);
    let _ = try reader.readUInt32();
    var x = 0;
    var y = 0;
    let head_flag = try reader.readUInt16();
    if (head_flag & 0x0008) != 0{
      y = Int(try reader.readInt16());
      reader.skip(bytes: 6);
    }
    let encoded = try reader.readSlice(bytes: reader.remaining);
    var index = encoded.startIndex;
    
    while (index < encoded.count - 1) {
      let skip = Int(encoded[index]);
      if skip == 0 {
        return;
      }
      
      index += 1;
      x += (skip - 1);
      index += try parseRunLength(data: encoded[index...], x: &x, y: &y);
    }
  }
  
  let dimensions: QDDelta;
  let depth: Int;
  let cmpSize : Int;
  let clut: QDColorTable?;
  var pixmap : [UInt8];
  
  var rowBytes: Int {
    return Int(ceil(dimensions.dh.value * Double(depth) / 8.0));
  }
  
  var description: String {
    let desc = describePixMap(self);
    return "Animation: \(desc)";
  }
}
