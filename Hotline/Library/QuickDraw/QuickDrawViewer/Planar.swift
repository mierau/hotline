//
//  Planar.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 09.02.2024.
//
// Decoder for the QuickTime `8BPS` "Planar" codec.

import Foundation

enum PlanarImageError : Error {
  case badDepth(depth: Int);
  case packbitError(line: Int, packbitError: PackbitError);
}

class PlanarImage : PixMapMetadata, @unchecked Sendable {

  init(dimensions: QDDelta, depth: Int, clut: QDColorTable?) throws {
    self.dimensions = dimensions;
    self.depth = depth;
    self.clut = clut;
    let (channels, pixSize) =  try expandDepth(depth);
    self.channels = channels;
    if pixSize != 8 {
      throw PlanarImageError.badDepth(depth: depth);
    }
    self.pixmap = [];
  }
  
  func load(data : consuming Data) throws {
    let reader = try QuickDrawDataReader(data: data, position:0);
    let lines = (dimensions.dv.rounded * channels);
    var lineLengths : [Int] = [];
    for _ in 0..<lines {
      lineLengths.append(Int(try reader.readUInt16()));
    }
    // Read raw data
    let width = dimensions.dh.rounded;
    var raw : [UInt8] = [];
    for (number, length) in lineLengths.enumerated() {
      do {
        let compressed = try reader.readSlice(bytes: length);
        let decompressed = try decompressPackBit(data: compressed, unpackedSize: width);
        raw.append(contentsOf: decompressed);
      } catch let error as PackbitError {
        throw PlanarImageError.packbitError(line: number, packbitError: error);
      }
    }
    if channels == 1 {
      pixmap = raw;
      return;
    }
    // Reorganize memory
    let planeSize = raw.count / channels;
    for i in 0..<planeSize {
      for p in 0..<channels {
        pixmap.append(raw[i + planeSize * p]);
      }
    }
    assert(pixmap.count == raw.count);
  }
  
  var rowBytes : Int {
    return dimensions.dh.rounded * pixelSize / 8;
  }
  
  let cmpSize : Int = 8;
  var pixelSize : Int {
    return cmpSize * channels;
  }
  
  let dimensions: QDDelta;
  let depth: Int;
  let channels : Int;
  var pixmap : [UInt8];
  
  var clut: QDColorTable?;
  
  var description: String {
    let pm = describePixMap(self);
    return "Planar Image: \(pm), channels \(channels)";
  }
  
}

