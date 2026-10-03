//
//  QuickDrawPattern.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 10.03.2024.
//

import Foundation

// MARK: - Black and white pattern (8×8 pixels)
struct QDPattern : Equatable, PixMapMetadata, RawRepresentable, Sendable {
  
  init(rawValue: UInt64) {
    self.rawValue = rawValue;
  }
  
  init(bytes: [UInt8]) {
    var buffer : UInt64 = 0;
    for v in bytes {
      buffer = buffer << 8  | UInt64(v);
    }
    self.rawValue = buffer;
  }
  
  let rowBytes : Int = 1;
  let cmpSize: Int = 1;
  let pixelSize: Int = 1;
  let rawValue: UInt64;
  let dimensions =  QDDelta(dv: FixedPoint(8), dh: FixedPoint(8));
  let clut: QDColorTable? = nil; // Color table is only known at runtime.
  var description: String {
    return "Pat: \(bytes): \(isShade)";
  }
  
  var bytes : [UInt8] {
    return byteArrayBE(from: rawValue);
  }
  
  /// Should the pattern represent a shade of color, i.e. the pattern was  used for dither.
  public var isShade : Bool {
    return [
      QDPattern.black, QDPattern.white,
      QDPattern.gray, QDPattern.darkGray,
      QDPattern.lightGray, QDPattern.batmanGray
    ].contains(where: {$0 == self} );
  }
  
  /// Scalar intensity of the pattern, going from 0 (white) to 1.0 (black).
  var intensity : Double {
    let total = rawValue.nonzeroBitCount;
    return Double(total) / Double(UInt64.bitWidth);
  }
  
  // Blend fgColor and bgColor using the intensity of this pattern.
  func blendColors(fg: QDColor, bg: QDColor) throws -> QDColor {
    if intensity == 1.0 {
      return fg;
    }
    if intensity == 0.0 {
      return bg;
    }
    return .blend(colorA: fg, colorB: bg, weight: intensity);
  }

  static let black = QDPattern(bytes:[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff]);
  static let white = QDPattern(bytes:[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]);
  static let gray = QDPattern(bytes:[0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55, 0xaa, 0x55]);
  static let darkGray =  QDPattern(bytes:[0x88, 0x00, 0x22, 0x00, 0x88, 0x00, 0x22, 0x00]);
  static let lightGray = QDPattern(bytes:[0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77, 0xdd, 0x77]);
  static let batmanGray = QDPattern(bytes: [0x88, 0x00, 0x22, 0x88, 0x00, 0x22]);
}

extension QuickDrawDataReader {
  func readPattern() throws -> QDPattern {
    return QDPattern(bytes:try readUInt8(bytes: 8));
  }
}

// MARK: - Union type with patterns
enum QDPixPattern  {
  case bw(pattern: QDPattern);
  case color(pattern: QDPattern, color: QDColor);
  case pattern(pattern: QDPattern, bitmap: QDBitMapInfo);

  func blendColors(fg: QDColor, bg: QDColor) throws -> QDColor {
    switch self {
      case .bw(pattern: let p): return try p.blendColors(fg: fg, bg: bg);
      case .color(pattern: _, color: let c): return c;
      case .pattern(pattern: _, bitmap: _):
        throw QuickDrawError.cannotBlend(message: "blend Color called with pixpattern");
    }
  }

  public var isShade : Bool {
    switch self {
      case .bw(pattern: let p): return p.isShade;
      case .color: return true;
      case .pattern: return false;
    }
  }

  public var intensity : Double? {
    switch self {
      case .bw(pattern: let p): return p.intensity;
      default: return nil;
    }
  }

}


