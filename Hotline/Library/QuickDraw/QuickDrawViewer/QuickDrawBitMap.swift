//
//  QuickDrawBitMap.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 17.04.2024.
//

import Foundation

/// Packing format used in QuickDraw PixMaps
enum QDPackType : UInt16 {
  case defaultPack = 0;
  case noPack = 1;
  case removePadByte = 2;
  case pixelRunLength = 3;
  case componentRunLength = 4;
}

/// Add-on information for a BitMap that is actually a Pixmap.
/// Confusingly, this is called `PixMap` record in Inside Quickdraw,.
/// even though there is no actual pixel data.
class QDPixMapInfo : CustomStringConvertible {
  public var description: String {
    var result = "PixMapInfo version: \(version) pack-size: \(packSize) ";
    result += "pack-type: \(packType) ";
    if resolution != nil {
      result += "resolution: \(resolution!) ";
    }
    result += "pixel type: \(pixelType) ";
    result += "pixel size: \(pixelSize) ";
    result += "composant count: \(cmpCount) ";
    result += "composant size: \(cmpSize) ";
    result += "plane byte: \(planeByte) ";
    result += "clutId: \(clutId) ";
    if clut != nil {
      result += "clut: \(clut!)";
    }
    return result;
  }
  
  var version : Int = 0;
  var packType : QDPackType = QDPackType.defaultPack;
  var packSize : Int = 0;
  var resolution : QDResolution?;
  var pixelType : Int = 0;
  var pixelSize : Int = 0;
  var cmpCount : Int = 0;
  var cmpSize : Int = 0;
  var planeByte : Int64 = 0;
  var clutId : Int32 = 0;
  var clutSeed : MacTypeCode = MacTypeCode.zero;
  var clut : QDColorTable?;
}


class QDBitMapInfo : CustomStringConvertible, PixMapMetadata, @unchecked Sendable {
  
  init(isPacked: Bool) {
    self.isPacked = isPacked;
  }
  
  var hasShortRows : Bool {
    return rowBytes < 250;
  }
  
  let isPacked : Bool;
  var rowBytes : Int = 0;
  var bounds : QDRect = QDRect.empty;
  var srcRect : QDRect?;
  var dstRect : QDRect?;
  var mode : QuickDrawMode = QuickDrawMode.defaultMode;
  var data : [UInt8] = [UInt8]();
  var pixMapInfo : QDPixMapInfo?;
  
  var destinationRect : QDRect {
    return dstRect!;
  }
  
  var dimensions: QDDelta {
    return bounds.dimensions;
  }
  
  var height : Int {
    return bounds.dimensions.dv.rounded;
  }
  
  var cmpSize : Int {
    if let pix_info = pixMapInfo {
      return pix_info.cmpSize;
    }
    return 1;
  }
  
  var pixelSize : Int {
    if let pix_info = pixMapInfo {
      return pix_info.pixelSize;
    }
    return 1;
  }
  
  var clut : QDColorTable? {
    if let pix_info = pixMapInfo {
      return pix_info.clut!;
    }
    // Should be colorised with foreground color.
    // return QDColorTable.palette1;
    return nil;
  }
  
  public var description : String {
    let pm = describePixMap(self);
    var result = "Bitmap info [\(pm) packed: \(isPacked) ";
    result += "Bounds \(bounds) "
    if srcRect != nil {
      result += "src: \(srcRect!) ";
    }
    if dstRect != nil {
      result += "dst: \(dstRect!) ";
    }
    result += " Mode: \(mode)]";
    if let pixmap = pixMapInfo {
      result += "Pixmap: \(pixmap)]";
    }
    result += " Data \(data.count) bytes";
    return result;
  }
}

extension QuickDrawDataReader {
  func readPixMapInfo() throws -> QDPixMapInfo  {
    let pixMapInfo = QDPixMapInfo();
    pixMapInfo.version = Int(try readUInt16());
    let rawPackType = try readUInt16();
    guard let packType = QDPackType(rawValue:rawPackType) else {
      throw QuickDrawError.invalidPackType(packtype:rawPackType);
    }
    pixMapInfo.packType = packType;
    pixMapInfo.packSize = Int(try readUInt32());
    pixMapInfo.resolution = try readResolution();
    pixMapInfo.pixelType = Int(try readUInt16());
    pixMapInfo.pixelSize = Int(try readUInt16());
    pixMapInfo.cmpCount = Int(try readUInt16());
    pixMapInfo.cmpSize = Int(try readUInt16());
    pixMapInfo.planeByte = Int64(try readUInt32());
    pixMapInfo.clutId = try readInt32();
    if let clut = QDColorTable.forClutId(clutId: Int(pixMapInfo.clutId)) {
      pixMapInfo.clut = clut;
    }
    pixMapInfo.clutSeed = try readType();
    return pixMapInfo;
  }
}

