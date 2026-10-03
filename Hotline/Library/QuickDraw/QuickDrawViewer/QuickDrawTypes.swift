//
//  QuickDrawTypes.swift
//  QuickDrawKit
//
//  Created by Matthias Wiesmann on 21.11.2023.
//

import Foundation

enum QDVerb : UInt16, CustomStringConvertible {
  var description: String {
    switch self {
      case .frame: return "frame";
      case .paint: return "paint";
      case .erase: return "erase";
      case .fill: return "fill";
      case .clip: return "clip";
      case .ignore: return "ignore";
      case .invert: return "invert";
    }
  }
  
  case frame = 0;
  case paint = 1;
  case erase = 2;
  case invert = 3;
  case fill = 4;
  case clip = 50;
  case ignore = 0xFF;
}

enum QDColorSelection : UInt8 {
  case foreground = 0;
  case background = 1;
  case operations = 2;
  case highlight = 3;
}


// the 8 first transfer modes from QuickDraw.p
// Patterns operation is bit 5.
enum QuickDrawTransferMode : UInt16,  CustomStringConvertible {
  public var description: String {
    return QuickDrawTransferMode.describeRaw(rawValue);
  }
  
  private static func describeRaw(_ rawValue : UInt16) -> String {
    if rawValue & 0x4 > 0 {
      return "!" + describeRaw(rawValue & 0x3);
    }
    switch rawValue % 4 {
      case 0 : return "copy";
      case 1 : return "or";
      case 2 : return "xor";
      case 3 : return "bic";
      default:
        assert(false);
        return "never";
    }
  }
  
  case copyMode = 0;
  case orMode = 1;
  case xorMode = 2;
  case bicMode = 3;
  case notCopyMode = 4;
  case notOrMode = 5;
  case notXorMode = 6;
  case notBic = 7;
}

struct QuickDrawMode : RawRepresentable, CustomStringConvertible {
  
  let rawValue: UInt16;
  
  var mode : QuickDrawTransferMode {
    return QuickDrawTransferMode(rawValue: rawValue % 8)!;
  }
  
  var isPattern : Bool {
    rawValue & QuickDrawMode.patternMask  != 0
  }
  
  var isDither: Bool {
    rawValue & QuickDrawMode.ditherMask != 0;
  }
  
  var description: String {
    var result = "[\(mode)";
    if isPattern {
      result += " pattern";
    }
    if isDither {
      result += " dither";
    }
    result += "]";
    result += " (\(rawValue))";
    return result;
  }
  
  static private let patternMask : UInt16 = 0x08;
  static private let ditherMask : UInt16 = 0x40;
  static let defaultMode : QuickDrawMode  = QuickDrawMode(rawValue: 0);
}

/// Operator  ⨴ is used for non commutative product between a structured type and a scalar or vector.
precedencegroup ComparisonPrecedence {
  associativity: left
  higherThan: AdditionPrecedence
}
infix operator ⨴ : MultiplicationPrecedence


/// All the state associated with drawing
class QDPenState {
  var location : QDPoint = QDPoint.zero;
  var penSize: QDPoint = defaultPen;
  var mode: QuickDrawMode = QuickDrawMode.defaultMode;
  var fgColor : QDColor = QDColor.black;
  var bgColor : QDColor = QDColor.white;
  var opColor : QDColor = QDColor.black;
  var highlightColor : QDColor = .rgb(rgb: RGBColor(red: 0, green: 0, blue: 0xffff));
  var drawPattern: QDPixPattern = .bw(pattern: QDPattern.black);
  var fillPattern: QDPixPattern = .bw(pattern: QDPattern.black);
  var ovalSize : QDDelta = QDDelta.zero;
  
  var drawColor : QDColor  {
    get throws {
      return try drawPattern.blendColors(fg: fgColor, bg: bgColor);
    }
  }
  
  var fillColor : QDColor {
    get throws {
      return try fillPattern.blendColors(fg: fgColor, bg: bgColor);
    }
  }

  func colorTable() throws -> QDColorTable  {
    return QDColorTable(clut: [try bgColor.getRgb(), try fgColor.getRgb()], id: 0, clutFlags: 0);
  }

  /// Pen width, assuming a square pen (height = width).
  var penWidth : FixedPoint {
    get {
      return (penSize.horizontal + penSize.vertical) >> 1;
    }
    set(width) {
      penSize = QDPoint(vertical: width, horizontal: width);
    }
  }
  
  static let defautPenWidth = FixedPoint.one;
  static let defaultPen = QDPoint(vertical: defautPenWidth, horizontal: defautPenWidth);
}

// Fix the frame using the first clip operation.
public class QDPicture : CustomStringConvertible {

  init(size: Int, frame:QDRect, filename: String?) {
    self.size = size;
    self.frame = frame;
    self.filename = filename;
    self.srcRect = frame;
  }
  
  let size: Int;
  var srcRect : QDRect;
  var frame: QDRect;
  var resolution : QDResolution = QDResolution.defaultResolution;
  var version: Int = 1;
  var opcodes: [OpCode] = [];
  var filename : String?;
  
  public var description : String {
    var result = "Picture size: \(size) bytes, version: \(version) ";
    if let name = filename {
      result += "filename: \(name) ";
    }
    result += "frame: \(frame) src: \(srcRect) @ \(resolution)\n";
    result += "===========================\n";
    for (index, opcode) in opcodes.enumerated() {
      result += "\(index): \(opcode)\n";
    }
    result += "===========================\n";
    return result;
  }

  func firstClip() -> QDRect? {
    for opcode in opcodes {
      if let clip = opcode as? ClipOpcode {
        return clip.clipRect;
      }
    }
    return nil;
  }

  /// The frame of QuickDraw pictures is often wrong, if it is obviously broken (zero dimension),
  /// fall back to the first clip operation.
  func fixFrame() {
    if frame.isEmpty {
      if let clipRect = firstClip() {
        frame = clipRect;
      }
    }
  }
}
