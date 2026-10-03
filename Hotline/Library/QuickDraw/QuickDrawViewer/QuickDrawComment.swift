//
//  QuickDrawComment.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 20.03.2024.
//

import Foundation

/// ----------------
/// Comment operations
/// ----------------
/// https://developer.apple.com/library/archive/documentation/mac/pdf/Imaging_With_QuickDraw/Appendix_B.pdf
/// https://web.archive.org/web/20151028215708/http://www.opennt.net/projects/opennt/repository/revisions/26/entry/trunk/com/ole32/olecnv32/qdcoment.i

enum CommentType : UInt16, CaseIterable {
  case groupBegin = 0;
  case groupEnd = 1;
  case proprietary = 100;
  case macDrawBegin = 130;
  case macDrawEnd = 131;
  case groupedBegin = 140 ;
  case groupedEnd = 141 ;
  case bitmapBegin = 142 ;
  case bitmapEnd = 143 ;
  case textBegin   = 150;
  case textEnd   = 151;
  case stringBegin = 152 ;
  case stringEnd   = 153;
  case textCenter  = 154;
  case lineLayoutOff = 155;
  case lineLayoutOn = 156;
  case lineLayoutClient = 157;
  case polyBegin   = 160;
  case polyEnd   = 161;
  case polyCurve   = 162;
  case polyIgnore  = 163;
  case polySmooth  = 164;
  case polyClose   = 165;
  case arrow1 = 170 ;
  case arrow2 = 171 ;
  case arrow3 = 172 ;
  case arrowEnd = 173;
  case dashedLineBegin = 180;
  case dashedLineEnd = 181;
  case setLineWidth = 182;
  case postscriptStart = 190 ;
  case postscriptEnd = 191 ;
  case postscriptHandle = 192 ;
  case postscriptFile = 193 ;
  case textIsPostscript = 194 ;
  case resourcePostscript = 195;
  case postscriptBeginNoSave = 196 ;
  case setGrayLevel = 197;
  case rotateBegin = 200;
  case rotateEnd   = 201;
  case rotateCenter = 202;
  case formsPrinting = 210;
  case endFormsPrinting = 211;
  case picAutoNap = 214;
  case picAutoWake = 215;
  case picManNap = 216;
  case picManWake = 217;
  case iccColorProfile = 224;  // https://www.color.org/icc32.pdf
  case creator = 498 ;  // Seems to be set by Photoshop
  case scale = 499;
  case bitmapThinBegin = 1000;
  case bitmapThinEnd = 1001;
  case picLasso = 12345;  // Internal to MacPaint code
  case unknown = 0xffff;
}

/// Define pen and font comment  payloads as operations, so they can be executed like opcodes.
/// This allows some generic processing on the renderer code.

struct LineWidthPayload : PenStateOperation {
  func execute(penState: inout QDPenState) {
    penState.penWidth = width;
  }
  let width: FixedPoint;
}

struct TextCenterPayload : FontStateOperation {
  func execute(fontState: inout QDFontState) {
    fontState.textCenter = center;
  }
  let center : QDDelta;
}

struct TextPictPayload : FontStateOperation {
  func execute(fontState: inout QDFontState) {
    fontState.textPictRecord = textPictRecord;
  }
  let textPictRecord : QDTextPictRecord;
}

struct PostScript : CustomStringConvertible {
  var description: String {
    return "<PostScript>";
  }
  let source : String;
}

enum IccProfileSelector : UInt32 {
  case iccBegin = 0;
  case iccContinuation = 1;
  case iccEnd = 2;
}

struct IccProfile {
  let selector : IccProfileSelector;
  let data : Data?;
}

enum CommentPayload : Sendable {
  case noPayload;
  case dataPayload(creator: MacTypeCode, data: Data);
  case postScriptPayLoad(postscript: PostScript);
  case fontStatePayload(fontOperation: FontStateOperation);
  case penStatePayload(penOperation: PenStateOperation);
  case polySmoothPayload(verb: PolygonOptions);
  case canvasPayload(canvas: CanvasPayload);
  case creatorPayload(creator: MacTypeCode, frame: QDRect);
  case colorPayload(creator: MacTypeCode, color: QDColor, selector : UInt16?);
  case unknownPayload(rawType: Int, data: Data);
  case iccColorProfilePayload(selector: IccProfileSelector, data: Data?);
  case gradientPayload(creator: MacTypeCode, gradient: GradientDescription);
  case gradientEndPayload(creator: MacTypeCode);
  case customClipPayLoad(creator: MacTypeCode);
  case clarisPayload(claris: ClarisPayload);
}

extension QuickDrawDataReader {
  /// See Technote 091: Optimizing for the LaserWriter—Picture Comments
  func readTextPictRecord() throws -> QDTextPictRecord {
    let raw_justification = try readUInt8();
    guard let justification = QDTextJustification(rawValue: raw_justification) else {
      throw QuickDrawError.quickDrawIoError(message: "Could not parse justification value \(raw_justification)");
    }
    let rawFlip = try readUInt8();
    guard let flip = QDTextFlip(rawValue: rawFlip) else {
      throw QuickDrawError.quickDrawIoError(message: "Could not parse flip value \(rawFlip)");
    }
    let angle1 = FixedPoint(try readInt16());
    let rawLineHeight = try readUInt8();
    guard let lineHeight = QDTextLineHeight(rawValue: rawLineHeight) else {
      throw QuickDrawError.quickDrawIoError(message: "Could not parse line height value \(rawLineHeight)");
    }
    skip(bytes: 1);  // Reserved
                            // MacDraw 1 comments are shorter
    if remaining < 4 {
      return QDTextPictRecord(justification: justification, flip: flip, angle: angle1, lineHeight: lineHeight);
    }
    let angle2 = try readFixed();
    let angle = angle2 + angle1
    return QDTextPictRecord(
      justification: justification, flip: flip, angle: angle, lineHeight: lineHeight);
  }
}

enum CanvasPayload {
  case canvasEnd;
  case canvasUnknown(code: UInt16, data: Data);
}

func parseCanvasPayload(creator: MacTypeCode, data: Data) throws -> CommentPayload {
  let reader = try QuickDrawDataReader(data: data, position: 0);
  let code = try reader.readUInt16();
  // code 9 always precedes a setLineWidth comment.
  switch code {
    case 0x44:
      return .canvasPayload(canvas: .canvasEnd);
    case 0xF7D3:
      reader.skip(bytes :10);
      let cmyk = try reader.readCMKY();
      let name = try reader.readPascalString();
      return .colorPayload(creator: creator, color: .cmyk(cmyk: cmyk, name: name), selector: code);
    default:
      return .canvasPayload(canvas: .canvasUnknown(code: code, data: try reader.readFullData()));
  }
}

enum ClarisPayload {
  case clarisUnknown(code: UInt16, data: Data);
}

extension QuickDrawDataReader {
  func readClarisGradient() throws -> GradientDescription {
    let gradientType = try readUInt16();
    skip(bytes: 6);
    var raw_colors: [QDColor] = [];
    for _ in 0..<4 {
      let rgb_color = try readRGB();
      skip(bytes: 2);
      raw_colors.append(.rgb(rgb: rgb_color));
    }
    // The top 4 bits of sizeControl tell us which colours to actually use.
    let sizeControl = try readUInt8();
    var colors: [QDColor] = [];
    for i in 0..<4 {
      if (sizeControl << i) & 0x80 != 0 {
        colors.append(raw_colors[i]);
      }
    }
    let angleDegree = try readUInt8();
    switch gradientType {
      case 0x0000:
        return GradientDescription(type: .linear(angleDegrees: Int(angleDegree)), colors: colors);
      case 0x0002:
        return GradientDescription(type: .radial, colors: colors);
      default:
        throw QuickDrawError.quickDrawIoError(message: "Unknwon gradient type \(gradientType)");
    }
  }
}

func parseClarisPayload(creator: MacTypeCode, data: Data) throws -> CommentPayload {
  let reader = try QuickDrawDataReader(data: data, position: 0);
  let code = try reader.readUInt16();
  switch code {
    case 0x0015:
      return .gradientEndPayload(creator: creator);
    case 0x0016:
      return .gradientPayload(creator: creator, gradient: try reader.readClarisGradient());
    default:
      return .clarisPayload(claris: .clarisUnknown(code: code, data: try reader.readFullData()));
  }
}


func parseProprietaryPayload(creator: MacTypeCode, data: Data) throws -> CommentPayload {
  switch creator.description {
    case "drw2":
      return try parseCanvasPayload(creator: creator, data: data);
    case "dPro":
      return try parseClarisPayload(creator: creator, data: data);
    default:
      return .dataPayload(creator: creator, data: data);
  }
}

struct CommentOp : OpCode, CustomStringConvertible, CullableOpcode {
  
  mutating func load(reader: QuickDrawDataReader) throws {
    let value = try reader.readUInt16();
    kind = CommentType(rawValue: value) ?? .unknown;
    let size = long_comment ? Data.Index(try reader.readUInt16()) : Data.Index(0);
    switch (kind, size) {
      case (.proprietary, let size) where size > 4:
        let creator = try reader.readType();
        let data = try reader.readData(bytes: size - 4);
        payload = try parseProprietaryPayload(creator: creator, data: data);
      case (.postscriptBeginNoSave, _),
        (.postscriptStart, _),
        (.postscriptFile, _),
        (.postscriptHandle, _):
        let postscript = try reader.readPostScript(bytes: size);
        payload = .postScriptPayLoad(postscript : postscript);
      case (.textBegin, let size) where size > 0:
        let subreader = try reader.subReader(bytes: size);
        let fontOp = TextPictPayload(textPictRecord: try subreader.readTextPictRecord());
        payload = .fontStatePayload(fontOperation: fontOp);
      case (.setLineWidth, let size) where size > 0:
        let subreader = try reader.subReader(bytes: size);
        let point = try subreader.readPoint();
        let penOp = LineWidthPayload(width: point.vertical / point.horizontal);
        payload = .penStatePayload(penOperation: penOp);
      case (.textCenter, let size) where size > 0:
        let subreader = try reader.subReader(bytes: size);
        // readDelta assumes integer, here we want to read fixed points.
        let v = try subreader.readFixed();
        let h = try subreader.readFixed();
        let fontOp = TextCenterPayload(center: QDDelta(dv: v, dh: h));
        payload = .fontStatePayload(fontOperation: fontOp);
      case (.polySmooth, 1):
        var verb = PolygonOptions(rawValue: try reader.readUInt8());
        verb.insert(.smooth);
        payload = .polySmoothPayload(verb: verb);
      case (.iccColorProfile, size) where size > 4:
        let selector = IccProfileSelector(rawValue: try reader.readUInt32());
        let data = try reader.readData(bytes: size - 4);
        payload = .iccColorProfilePayload(selector: selector!, data: data);
      case (.iccColorProfile, size) where size == 4:
        let selector = IccProfileSelector(rawValue: try reader.readUInt32());
        payload = .iccColorProfilePayload(selector: selector!, data: nil);
      case (.creator, size):
        let subreader = try reader.subReader(bytes: size);
        let creator = try subreader.readType();
        subreader.skip(bytes: 2);
        let frame = try subreader.readRect();
        payload = .creatorPayload(creator: creator, frame: frame);
      case (_, 0):
        payload = .noPayload;
      case (.unknown, let size) where size > 0:
        payload = .unknownPayload(rawType: Int(value), data: try reader.readData(bytes: size));
      case (_, let size) where size > 0:
        let creator = try MacTypeCode(fromString: "APPL");
        payload = .dataPayload(creator: creator, data: try reader.readData(bytes: size));
      default:
        payload = .unknownPayload(rawType: Int(value), data: try reader.readData(bytes: size));
    }
  }

  var description: String {
    return "CommentOp \(kind): [\(payload)]"
  }
  
  var canCull: Bool {
    switch (kind, payload) {
      case (_, .postScriptPayLoad): return true;
      case (.postscriptEnd, _): return true;
      default:
        return false;
    }
  }
  
  let long_comment : Bool;
  var kind : CommentType = .unknown;
  var payload : CommentPayload = CommentPayload.noPayload;
}

extension QuickDrawDataReader {
  // PostScript is encoded as pure ASCII text.
  func readPostScript(bytes: Data.Index) throws -> PostScript {
    let data = try readUInt8(bytes: bytes);
    guard let str = String(bytes:data, encoding: String.Encoding.ascii) else {
      throw QuickDrawError.quickDrawIoError(message: "Failed decoding PostScript");
    }
    return PostScript(source: str);
  }
  
}
