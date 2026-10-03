//
//  QuickDrawParser.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 02.01.2024.
//

import os
import Foundation


/// Class that decodes a stream of QuickDraw opcodes.
class QDParser {
  
  /// Setup the parser with the content of the file.
  /// No parsing will occur until `parse`is called.
  /// - Parameter contentsOf: url from where the data will be retrieved.
  public init(contentsOf: URL) throws {
    let options = Data.ReadingOptions();
    let data = try Data(contentsOf: contentsOf, options: options);
    try dataReader = QuickDrawDataReader(data: data);
  }
  
  /// Setup the parser with some raw data.
  /// Note that the parser assumes the actual data starts at offset 512.
  /// - Parameter data: data containing the  QuickDraw opcodes.
  public init(data : Data ) throws {
    try dataReader = QuickDrawDataReader(data: data);
  }

  /// Decode a single opcode
  /// - Parameter opcode: numerical opcode identifier
  /// - Returns: an OpCode instance
  static func decode(opcode: UInt16) throws -> OpCode {
    switch opcode {
      case 0x00: return NoOp();
      case 0x01: return RegionOp(same: false, verb: QDVerb.clip);
      case 0x03: return FontOp(longOp: false);
      case 0x04: return FontStyleOp();
      case 0x05: return TextModeOp();
      case 0x06: return SpaceExtraOp()
      case 0x07: return PenSizeOp();
      case 0x08: return PenModeOp();
      case 0x09: return PatternOp(verb: QDVerb.frame);
      case 0x0A: return PatternOp(verb: QDVerb.fill);
      case 0x0B: return OvalSizeOp();
      case 0x0C: return OriginOp();
      case 0x0D: return FontSizeOp();
      case 0x0E: return ColorOp(rgb:false, selection: QDColorSelection.foreground);
      case 0x0F: return ColorOp(rgb:false, selection: QDColorSelection.background);
      case 0x10: return TextRatioOp();
      case 0x11, 0x02FF:
        return VersionOp();
      case 0x12: return PixPatternOp(verb: QDVerb.erase);
      case 0x13: return PixPatternOp(verb: QDVerb.frame);
      case 0x14: return PixPatternOp(verb: QDVerb.fill);
      // case 0x12: return ColorPattern op
      case 0x15: return PnLocHFracOp();
      case 0x16: return SpaceExtraOp();
      // $0017, $0018, $0019 are reserved with no defined arg size
      case 0x1A: return ColorOp(rgb: true, selection: QDColorSelection.foreground);
      case 0x1B: return ColorOp(rgb: true, selection: QDColorSelection.background);
      case 0x1D: return ColorOp(rgb: true, selection: QDColorSelection.highlight);
      case 0x1E: return DefHiliteOp();
      case 0x1F: return ColorOp(rgb: true, selection: QDColorSelection.operations);
      case 0x20: return LineOp(short: false, from:false);
      case 0x21: return LineOp(short: false, from:true);
      case 0x22: return LineOp(short: true, from: false);
      case 0x23: return LineOp(short: true, from: true);
      case 0x24...0x27: return ReservedOp(code: opcode, reservedType: .readLength(bytes: 2));
      case 0x28: return LongTextOp();
      case 0x29: return DHDVTextOp(readDh: true, readDv: false);
      case 0x2a: return DHDVTextOp(readDh: false, readDv: true);
      case 0x2b: return DHDVTextOp(readDh: true , readDv: true);
      case 0x2c: return FontOp(longOp: true);
      case 0x2e: return GlyphStateOp();
      case 0x30...0x34:
        return RectOp(same: false, verb: QDVerb(rawValue: opcode - 0x30)!);
      case 0x35...0x37:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 8));
      case 0x38...0x3C:
        return RectOp(same: true, verb: QDVerb(rawValue: opcode - 0x38)!);
      case 0x3D...0x3F:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 8));
      case 0x40...0x44:
        return RoundRectOp(same: false, verb: QDVerb(rawValue: opcode - 0x40)!);
      case 0x45...0x47:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 8));
      case 0x48...0x4C:
        return RoundRectOp(same: true, verb: QDVerb(rawValue: opcode - 0x48)!);
      case 0x4D...0x4F:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 0));
      case 0x50...0x54:
        return OvalOp(same: false, verb: QDVerb(rawValue: opcode - 0x50)!);
      case 0x58...0x5C:
        return OvalOp(same: true, verb: QDVerb(rawValue: opcode - 0x58)!);
      case 0x60...0x64:
        return ArcOp(same: false, verb: QDVerb(rawValue: opcode - 0x60)!);
      case 0x65...0x67:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 12));
      case 0x68...0x6C:
        return ArcOp(same: true, verb: QDVerb(rawValue: opcode - 0x68)!);
      case 0x6D...0x6F:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 4));
      case 0x70...0x74:
        return PolygonOp(same: false, verb: QDVerb(rawValue: opcode - 0x70)!);
      case 0x80...0x84:
        return RegionOp(same: false, verb: QDVerb(rawValue: opcode - 0x80)!);
      case 0x85...0x87:
        return RegionOp(same: false, verb: .ignore);
      case 0x90: return BitRectOpcode(isPacked: false);
      case 0x98: return BitRectOpcode(isPacked: true);
      case 0x9A: return DirectBitOpcode();
      case 0x9B: return DirectBitOpcodeWithMask();
      case 0xA0: return CommentOp(long_comment:false);
      case 0xA1: return CommentOp(long_comment:true);
      case 0xA2...0xAF: return ReservedOp(code: opcode, reservedType: .readLength(bytes: 2));
      case 0xB0...0xCF: return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 0));
      case 0xD0...0xFE: return ReservedOp(code: opcode, reservedType: .readLength(bytes: 4));
      case 0xFF: return EndOp();
      case 0x0100...0x1ff: return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 2));
      case 0x0200...0x2fe: return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 4));
      case 0x0300...0x0bff:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: Int(opcode) / 0x80));
      case 0x0c00: return Version2HeaderOp();
      case 0x0c01...0x7fff:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: Int(opcode) / 0x80));
      case 0x8000...0x80ff:
        return ReservedOp(code: opcode, reservedType: .fixedLength(bytes: 0));
      case 0x8100...0x81ff:
        return ReservedOp(code: opcode, reservedType: .readLength(bytes: 4));
      case 0x8200: return QuickTimeOpcode();
      case 0x8202...0xffff:
        return ReservedOp(code: opcode, reservedType: .readLength(bytes: 4));
      case 0xFFFF : return ReservedOp(code: opcode, reservedType: .readLength(bytes: 4));
      default:
        throw QuickDrawError.unknownOpcodeError(opcode:opcode);
    }
  }
  
  /// Parse one opcode.
  /// - Parameters:
  ///   - picture: the picture to execute picture operations into.
  /// - Returns: true if futher opcodes should be read.
  func parseOne(picture: inout QDPicture) throws -> Bool {
    
    let codeValue = try dataReader.readOpcode(version: picture.version);
    var opcode = try QDParser.decode(opcode: codeValue);
    if let reserved = opcode as? ReservedOp {
      let p = String(format: "%04X", dataReader.currentIndex - 2) ;
      let code = String(format: "%04X", reserved.code) ;
      logger.log(level: .debug, "Reserved opcode \(code) encountered at \(p)");
    }
    try opcode.load(reader: dataReader);
    if let picture_operation = opcode as? PictureOperation {
      picture_operation.execute(picture: &picture);
    }

    picture.opcodes.append(opcode);
    guard !(opcode is EndOp) else {
      return false;
    }
    return true;
  }
  
  /// Parse the actual QuickDraw picture
  /// - Returns: a picture object that can be rendered.
  public func parse() throws -> QDPicture  {
    let startTime = CFAbsoluteTimeGetCurrent();
    // Parse v1 header.
    let size = Int(try dataReader.readUInt16());
    let frame = try dataReader.readRect();
    // Create picture object
    var picture = QDPicture(size: size, frame:frame, filename: dataReader.filename);
    do {
      while (try parseOne(picture: &picture)) {}
    } catch {
      let message = String(localized: "Failed parsing QuickDraw file");
      logger.log(level: .error, "\(message): \(error)");
    }
    let timeElapsed = CFAbsoluteTimeGetCurrent() - startTime;
    let name = picture.filename ?? ""
    logger.log(level: .debug, "Picture \(name) parsed in : \(timeElapsed) seconds");
    picture.fixFrame();
    return picture
  }
  
  var dataReader: QuickDrawDataReader;
  let logger : Logger = Logger(subsystem: "net.codiferes.wiesmann.QuickDraw", category: "parser");
  
  var filename : String? {
    set (name) {
      dataReader.filename = name;
    }
    get {
      return dataReader.filename
    }
  }
}

