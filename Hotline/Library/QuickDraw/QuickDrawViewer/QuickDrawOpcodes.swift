//
//  QuickDrawOpcodes.swift
//  QuickDrawKit
//
//  Created by Matthias Wiesmann on 21.11.2023.
//

import os
import Foundation

/// -------
/// Protocols
/// -------

/// Minimal interface: be able to load.
/// Technically, opcodes are mutables, but they are only mutated once after construction.
protocol OpCode : Sendable  {
  mutating func load(reader: QuickDrawDataReader) throws -> Void
}

/// opcodes that affect the picture meta-data, typically execute at load time.
protocol PictureOperation : Sendable {
  func execute(picture : inout QDPicture) -> Void;
}

/// opcodes that affect the pen-state can be execute independently of the target graphic system.
protocol PenStateOperation : Sendable {
  func execute(penState : inout QDPenState) throws -> Void;
}

/// opcodes that affect the font state (size, font-name, etc).
protocol FontStateOperation : Sendable {
  func execute(fontState : inout QDFontState) -> Void;
}

protocol PortOperation : Sendable {
  func execute(port: inout QuickDrawPort) throws -> Void;
}

protocol CullableOpcode : Sendable {
  var canCull : Bool {
    get
  }
}

protocol ClipOpcode  {
  var clipRect : QDRect? { get }
}

/// -----------------
/// Simple control opcodes
/// -----------------

struct NoOp : OpCode, PictureOperation, CullableOpcode {
  func execute(picture: inout QDPicture) {}
  
  mutating func load(reader: QuickDrawDataReader) throws {}
  let canCull = true;
}

struct EndOp : OpCode, PictureOperation, CullableOpcode {
  func execute(picture: inout QDPicture) {}
  
  mutating func load(reader: QuickDrawDataReader) throws {}
  let canCull = true;
}

enum ReservedOpType {
  case fixedLength(bytes: Int);
  case readLength(bytes: Int);
}

struct ReservedOp : OpCode, PictureOperation, CullableOpcode {
  func execute(picture: inout QDPicture) {}
  
  mutating func load(reader: QuickDrawDataReader) throws {
    switch reservedType {
      case let .fixedLength(bytes):
        length = bytes;
      case let .readLength(bytes) where bytes == 4:
        length = Data.Index(try reader.readUInt32());
      case let .readLength(bytes) where bytes == 2:
        length = Data.Index(try reader.readUInt16());
      case let .readLength(bytes) where bytes == 1:
        length = Data.Index(try reader.readUInt8());
      default:
        throw QuickDrawError.invalidReservedSize(reservedType: reservedType);
    }
    reader.skip(bytes: length)
  }

  let code : UInt16;
  let canCull = true;
  let reservedType : ReservedOpType ;
  var length : Data.Index = 0;
}


struct DefHiliteOp : OpCode {
  mutating func load(reader: QuickDrawDataReader) throws -> Void {}
}


struct VersionOp : OpCode, PictureOperation {
  func execute(picture: inout QDPicture) {
    picture.version = Int(version);
  }
  
  mutating func load(reader: QuickDrawDataReader) throws -> Void {
    version = try reader.readUInt8();
    if version == 2 {
      _ = try reader.readUInt8();
    }
  }
  var version: UInt8 = 0;
}

struct Version2HeaderOp : OpCode, PictureOperation {
  mutating func load(reader: QuickDrawDataReader) throws -> Void {
    reader.skip(bytes: 4);
    resolution = try reader.readResolution();
    srcRect = try reader.readRect();
    reader.skip(bytes: 4);
    // reader.skip(bytes: 24);
  }
  
  func execute(picture: inout QDPicture) {
    if resolution != QDResolution.zeroResolution {
      picture.resolution = resolution;
      picture.srcRect = srcRect;
      picture.frame = srcRect;
    }
  }
  
  var resolution : QDResolution = QDResolution.defaultResolution;
  var srcRect : QDRect = QDRect.empty;
  
}

struct OriginOp : OpCode {
  mutating func load(reader: QuickDrawDataReader) throws -> Void {
    delta = try reader.readDelta();
  }
  
  var delta : QDDelta = QDDelta.zero;
}

/// ---------------------
/// Shape opcodes
/// ---------------------

struct RegionOp : OpCode, PortOperation, ClipOpcode {



  mutating func load(reader: QuickDrawDataReader) throws {
    try region = reader.readRegion();
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    let rgn = self.region ?? port.lastRegion;
    try port.stdRegion(region: rgn, verb: verb);
  }
  
  let same : Bool;
  let verb : QDVerb
  var region: QDRegion?;

  var clipRect: QDRect? {
    if verb == .clip {
      return region?.boundingBox;
    }
    return nil;
  }
}

/// Rectangle operation
struct RectOp : OpCode, PortOperation, ClipOpcode {
  mutating func load(reader: QuickDrawDataReader) throws {
    if !same {
      rect = try reader.readRect();
    }
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    let rect = rect ?? port.lastRect;
    try port.stdRect(rect : rect, verb: verb);
  }
  
  let same: Bool;
  let verb: QDVerb;
  var rect: QDRect?;

  var clipRect: QDRect? {
    if verb == .clip {
      return rect;
    }
    return nil;
  }
}

/// Oval operation
struct OvalOp : OpCode, PortOperation {
  mutating func load(reader: QuickDrawDataReader) throws {
    if !same {
      rect = try reader.readRect();
    }
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    let rect = rect ?? port.lastRect;
    try port.stdOval(rect : rect, verb: verb);
  }
  
  let same: Bool;
  let verb: QDVerb;
  var rect: QDRect?;
}

struct RoundRectOp : OpCode, PortOperation {
  func execute(port: inout any QuickDrawPort) throws {
    let rect = rect ?? port.lastRect;
    try port.stdRoundRect(rect: rect, verb: verb);
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    if !same {
      rect = try reader.readRect();
    }
  }
  
  let same: Bool;
  let verb: QDVerb;
  var rect: QDRect?;
}

struct OvalSizeOp : OpCode, PenStateOperation {
  func execute(penState: inout QDPenState) {
    penState.ovalSize = size;
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    size = try reader.readDelta();
  }
  
  var size : QDDelta = QDDelta.zero;
}

/// Arc operation
struct ArcOp : OpCode, PortOperation {

  mutating func load(reader: QuickDrawDataReader) throws {
    if !same {
      rect = try reader.readRect();
    }
    startAngle = try reader.readInt16();
    angle = try reader.readInt16();
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    try port.stdArc(
      rect: rect, startAngle : startAngle, angle: angle, verb: verb);
  }
  
  let same: Bool;
  let verb: QDVerb;
  var rect = QDRect.empty;
  var startAngle: Int16 = 0;
  var angle: Int16 = 0;
}


/// Polygon operation
struct PolygonOp : OpCode, PortOperation, @unchecked Sendable {

  mutating func load(reader: QuickDrawDataReader) throws {
    poly = try reader.readPoly();
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    let poly = GetPolygon(last: port.lastPoly);
    try port.stdPoly(polygon: poly, verb: verb);
  }
  
  func GetPolygon(last : QDPolygon) -> QDPolygon {
    return self.poly ?? last;
  }
  
  let same: Bool;
  let verb: QDVerb;
  var poly: QDPolygon?;
}

// MARK: - Line Operations

enum LineDestination {
  case unset;
  case relative(delta: QDDelta);
  case absolute(point: QDPoint);
}

struct LineOp : OpCode, PortOperation, CustomStringConvertible {
  
  mutating func load(reader: QuickDrawDataReader) throws {
    if !from {
      start = try reader.readPoint();
    }
    if short {
      let dh = try reader.readInt8();
      let dv = try reader.readInt8();
      end = .relative(delta: QDDelta(dv: dv, dh:dh))
    } else {
      end = .absolute(point: try reader.readPoint());
    }
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    let qd_points = getPoints(current: port.penState.location);
    try port.stdLine(points: qd_points);
  }
  
  // Get the set of points for the line (2).
  // current is required for `from` operations.
  private func getPoints(current : QDPoint?) -> [QDPoint] {
    let p1 = (start ?? current)!;
    var points : [QDPoint] = [p1];
    switch end {
      case .absolute(let point):
        points.append(point);
      case .relative(let delta):
        points.append(p1 + delta);
      case .unset:
        break;
    }
    return points;
  }
  
  public var description: String {
    var result = "Line ";
    if let s = start {
      result += "\(s)"
    }
    switch end {
      case .absolute(let point):
        result += "→ \(point)";
      case .relative(let delta):
        result += "→ \(delta)";
      case .unset:
        break;
    }
    return result;
  }
  
  
  let short : Bool;
  let from : Bool;
  var start : QDPoint?;
  var end : LineDestination = .unset;
}

// MARK: - Color Operations
// ------------------------

struct ColorOp : OpCode, PenStateOperation, CustomStringConvertible {
  
  mutating func load(reader: QuickDrawDataReader) throws {
    if rgb {
      color = try .rgb(rgb: reader.readRGB());
    } else {
      color = try .qd1(qd1: reader.readQD1Color());
    }
  }
  
  func execute(penState: inout QDPenState) {
    switch selection {
      case QDColorSelection.foreground: penState.fgColor = color;
      case QDColorSelection.background: penState.bgColor = color;
      case QDColorSelection.operations: penState.opColor = color;
      case QDColorSelection.highlight: penState.highlightColor = color;
    }
  }
  
  var description: String {
    return "ColorOp: \(selection) : \(color)";
  }
  
  let rgb : Bool;  // should color be loaded as RGB (true), or old style QuickDraw?
  let selection : QDColorSelection;  // What selection does the color apply to.
  var color : QDColor = QDColor.white;
}


// MARK: - Pen operations
// ----------------------

struct PatternOp : OpCode, PenStateOperation  {
  func execute(penState: inout QDPenState) throws {
    switch verb {
      case .fill, .paint:
        penState.fillPattern = .bw(pattern: pattern);
      case .frame:
        penState.drawPattern = .bw(pattern: pattern);
      default:
        throw QuickDrawError.unsupportedVerb(verb: verb);
    }
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    pattern = try reader.readPattern()
  }
  
  let verb : QDVerb;
  var pattern : QDPattern = QDPattern.black;
}

struct PixPatternOp : OpCode, PenStateOperation  {
  
  mutating func load(reader: QuickDrawDataReader) throws {
    let patternSelector = try reader.readUInt16();
    let pattern = try reader.readPattern();
    if (patternSelector == 2) {
      let color : QDColor = try .rgb(rgb: reader.readRGB());
      patternType = .color(pattern: pattern, color: color);
    } else {
      let bitmapInfo = try reader.readQDBitMapInfoStart(isPacked: true);
      bitmapInfo.data = try reader.readQDBitMapInfoData(bitmapInfo: bitmapInfo);
      patternType = .pattern(pattern: pattern, bitmap: bitmapInfo);
    }
  }

  func execute(penState: inout QDPenState) throws {
    switch verb {
      case .fill: penState.fillPattern = patternType; return;
      case .frame: penState.drawPattern = patternType; return;
      default:
        break;
    }
  }

  let verb : QDVerb;
  var patternType : QDPixPattern = .bw(pattern: QDPattern.black);

}

struct PenSizeOp : OpCode, PenStateOperation {
  func execute(penState: inout QDPenState) {
    penState.penSize = penSize;
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    penSize = try reader.readPoint();
  }
  
  var penSize = QDPoint.zero;
}

struct PenModeOp : OpCode, PenStateOperation {
  mutating func load(reader: QuickDrawDataReader) throws {
    mode = QuickDrawMode(rawValue: try reader.readUInt16());
  }
  
  func execute(penState: inout QDPenState) {
    penState.mode = mode;
  }
  var mode : QuickDrawMode = QuickDrawMode.defaultMode;
}

struct TextModeOp : OpCode, FontStateOperation {
  mutating func load(reader: QuickDrawDataReader) throws {
    mode = QuickDrawMode(rawValue: try reader.readUInt16());
  }
  
  func execute(fontState: inout QDFontState) {
    fontState.fontMode = mode;
  }
  var mode : QuickDrawMode = QuickDrawMode.defaultMode;
}

// MARK: - Font operations
// -----------------------

struct FontOp : OpCode, FontStateOperation {
  func execute(fontState: inout QDFontState) {
    fontState.setFont(fontId: self.fontId, fontName: self.fontName);
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    if longOp {
      let _ = try reader.readUInt16();
      fontId = Int(try reader.readUInt16());
      fontName = try reader.readPascalString();
    } else {
      fontId = Int(try reader.readUInt16());
    }
  }
  
  let longOp: Bool;
  var fontId: Int?;
  var fontName: String?;
}


struct FontSizeOp : OpCode, FontStateOperation {
  func execute(fontState: inout QDFontState) {
    fontState.fontSize = textSize;
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    textSize = FixedPoint(try reader.readUInt16());
  }
  
  var textSize = FixedPoint.zero;
}

struct GlyphStateOp : OpCode, FontStateOperation {
  func execute(fontState: inout QDFontState) {
    fontState.glyphState = glyphState;
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    let len = Data.Index(try reader.readUInt16());
    guard len >= 4 else {
      throw QuickDrawError.corruptPayload(message: "GlyphState too short: \(len)");
    }
    if try reader.readBool() {
      glyphState.insert(.outlinePreferred);
    }
    if try reader.readBool() {
      glyphState.insert(.preserveGlyphs);
    }
    if try reader.readBool() {
      glyphState.insert(.fractionalWidths);
    }
    if try reader.readBool() {
      glyphState.insert(.scalingDisabled);
    }
    reader.skip(bytes: len - 4);
  }
  
  var glyphState : QDGlyphState = QDGlyphState.defaultState;
}

struct TextRatioOp : OpCode, FontStateOperation {
  
  mutating func load(reader: QuickDrawDataReader) throws {
    let numerator = try reader.readPoint();
    let denominator = try reader.readPoint();
    guard denominator.vertical.value != 0.0 else {
      throw QuickDrawError.invalidFract(message: "Zero denominator");
    }
    guard denominator.horizontal.value != 0.0 else {
      throw QuickDrawError.invalidFract(message: "Zero denominator");
    }
    x = numerator.horizontal / denominator.horizontal;
    y = numerator.vertical / denominator.vertical;
    
  }
  
  func execute(fontState: inout QDFontState) {
    fontState.xRatio = x;
    fontState.yRatio = y;
  }
  
  var x : FixedPoint = FixedPoint.one;
  var y : FixedPoint = FixedPoint.one;
}

struct SpaceExtraOp : OpCode, FontStateOperation {
  mutating func load(reader: QuickDrawDataReader) throws {
    extraSpace = try reader.readFixed();
  }
  
  func execute(fontState: inout QDFontState) {
    fontState.extraSpace = extraSpace;
  }
  
  var extraSpace : FixedPoint = FixedPoint.zero;
}

struct PnLocHFracOp : OpCode, PenStateOperation {
  mutating func load(reader: QuickDrawDataReader) throws {
    let f = try reader.readUInt16();
    penFraction = FixedPoint(rawValue: Int(f));
  }
  
  func execute(penState: inout QDPenState) {
    let v = penState.location.vertical;
    let h = penState.location.horizontal + penFraction;
    
    penState.location = QDPoint(vertical: v, horizontal: h)
  }
  
  var penFraction : FixedPoint = FixedPoint.zero;
  
}

struct FontStyleOp : OpCode, FontStateOperation {
  func execute(fontState: inout QDFontState) {
    fontState.fontStyle = fontStyle;
  }
  
  mutating func load(reader: QuickDrawDataReader) throws {
    fontStyle = QDFontStyle(rawValue: try reader.readUInt8());
  }
  
  var fontStyle = QDFontStyle.defaultStyle;
}

struct DHDVTextOp : OpCode, PortOperation {
  
  mutating func load(reader: QuickDrawDataReader) throws {
    var dv = 0;
    var dh = 0;
    if readDh {
      dh = Int(try reader.readUInt8());
    }
    if readDv {
      dv = Int(try reader.readUInt8());
    }
    delta = QDDelta(dv:dv, dh:dh);
    text = try reader.readPascalString();
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    port.fontState.location = port.fontState.location + self.delta;
    try port.stdText(text: self.text);
  }
  
  let readDh : Bool;
  let readDv : Bool;
  var delta : QDDelta = QDDelta.zero;
  
  var text : String = "";
  
}

struct LongTextOp : OpCode, PortOperation {
  
  
  mutating func load(reader: QuickDrawDataReader) throws {
    position = try reader.readPoint();
    text = try reader.readPascalString();
  }
  
  func execute(port: inout any QuickDrawPort) throws {
    port.fontState.location = self.position;
    try port.stdText(text: self.text);
  }
  
  var position : QDPoint = QDPoint.zero;
  var text : String = "";
}

// MARK: - Bitmap/Pixmap op-codes
// ------------------------------

struct BitRectOpcode : OpCode {
  
  mutating func load(reader: QuickDrawDataReader) throws {
    bitmapInfo = try reader.readQDBitMapInfo(isPacked: isPacked);
  }

  let isPacked : Bool;
  var bitmapInfo : QDBitMapInfo?;
}

extension QuickDrawDataReader {

  func readQDBitMapInfoStart(isPacked: Bool) throws -> QDBitMapInfo {
    var masked = try readUInt16();
    var isPixMap = false;
    if masked & 0x8000 != 0 {
      isPixMap = true;
      masked = masked ^ 0x8000;
    }
    let bitmapInfo = QDBitMapInfo(isPacked: isPacked);
    bitmapInfo.rowBytes = Int(masked);
    bitmapInfo.bounds = try readRect();
    if isPixMap {
      let pixMapInfo = try readPixMapInfo();
      pixMapInfo.clut = try readClut();
      bitmapInfo.pixMapInfo = pixMapInfo;
    }
    return bitmapInfo;
  }

  func readQDBitMapInfoData(bitmapInfo : QDBitMapInfo) throws -> [UInt8] {
    let rows = bitmapInfo.bounds.dimensions.dv.rounded;
    var data : [UInt8] = [];
    for _ in 0 ..< rows {
      if !bitmapInfo.isPacked {
        let line_data = try readUInt8(bytes: Data.Index(bitmapInfo.rowBytes));
        data.append(contentsOf: line_data);
        continue;
      }
      var lineLength : Data.Index;
      if bitmapInfo.hasShortRows {
        lineLength = Data.Index(try readUInt8());
      } else {
        lineLength = Data.Index(try readUInt16());
      }
      let rowData = try readSlice(bytes: lineLength);
      let decompressed = try decompressPackBit(data: rowData, unpackedSize: bitmapInfo.rowBytes);
      data.append(contentsOf: decompressed);
    }
    return data;
  }

  func readQDBitMapInfo(isPacked: Bool) throws -> QDBitMapInfo {
    let bitmapInfo = try readQDBitMapInfoStart(isPacked: isPacked);
    bitmapInfo.srcRect = try readRect();
    bitmapInfo.dstRect = try readRect();
    bitmapInfo.mode = try QuickDrawMode(rawValue: readUInt16());
    bitmapInfo.data = try readQDBitMapInfoData(bitmapInfo: bitmapInfo);
    return bitmapInfo;
  }
}

extension QuickDrawDataReader {
  func readQDPixMapInfoStart() throws -> QDBitMapInfo {
    let pixMap = QDBitMapInfo(isPacked: false);
    self.skip(bytes: 4);  // Base address
    var masked = try self.readUInt16();
    if masked & 0x8000 != 0 {
      masked = masked ^ 0x8000;
    }

    pixMap.rowBytes = Int(masked);
    pixMap.bounds = try self.readRect();
    pixMap.pixMapInfo = try self.readPixMapInfo();
    pixMap.srcRect = try self.readRect();
    pixMap.dstRect = try self.readRect();
    pixMap.mode = try QuickDrawMode(rawValue: self.readUInt16());
    return pixMap;
  }

  /// Pack type 1
  func loadPixMapUnpacked(bitmapInfo: QDBitMapInfo) throws -> [UInt8] {
    let rows = bitmapInfo.height;
    let rowBytes = bitmapInfo.rowBytes;
    let byteNum = rows * rowBytes;
    return try self.readUInt8(bytes: byteNum);
  }

  /// Pack 2
  /// This is basically 24-bits RGB, Quickdraw would actually pad this to 32 bits.
  /// We just load it as 24-bits and update rowBytes to reflect this.
  func loadPixMapRemovePad(bitmapInfo: QDBitMapInfo) throws -> [UInt8] {
    let rows = bitmapInfo.height;
    let rowBytes = bitmapInfo.rowBytes * 3 / 4;
    let byteNum = rows * rowBytes;
    bitmapInfo.rowBytes = rowBytes;
    bitmapInfo.pixMapInfo!.pixelSize = 24;
    return try self.readUInt8(bytes: byteNum);
  }

  /// Pack 3
  /// Packbit algorithm on 16 bit quantities.
  func loadPixMapPixelRunLength(bitmapInfo: QDBitMapInfo) throws -> [UInt8] {
    let rows = bitmapInfo.height;
    var data : [UInt8] = [];
    for _ in 0..<rows {
      var lineLength : Data.Index;
      if bitmapInfo.hasShortRows {
        lineLength = Data.Index(try self.readUInt8());
      } else {
        lineLength = Data.Index(try self.readUInt16());
      }
      let line_data = try self.readSlice(bytes: lineLength);
      let decompressed = try decompressPackBit(
        data: line_data, unpackedSize: bitmapInfo.rowBytes, byteNum: 2);

      data.append(contentsOf: decompressed);
    }
    return data;
  }

  /// Pack 4
  /// Packbit algorithm on 8 bit quantities, for each row, first the red values, then the green, blue.
  func loadPixMapComponentRunLength(bitmapInfo: inout QDBitMapInfo) throws -> [UInt8]{
    let rows = bitmapInfo.height;
    let cmpCount = bitmapInfo.pixMapInfo?.cmpCount
    guard cmpCount == 3 || cmpCount == 4 else {
      throw QuickDrawError.wrongComponentNumber(componentNumber: bitmapInfo.cmpSize);
    }

    let rowBytes = bitmapInfo.rowBytes * cmpCount! / 4;
    var data : [UInt8] = [];

    for _ in 0..<rows {
      var lineLength : Data.Index;
      if bitmapInfo.hasShortRows {
        lineLength = Data.Index(try self.readUInt8());
      } else {
        lineLength = Data.Index(try self.readUInt16());
      }
      let line_data = try self.readSlice(bytes: lineLength);
      let decompressed = try decompressPackBit(data: line_data, unpackedSize: rowBytes, byteNum: 1);
      var interleaved = interleave(planar: decompressed[...], components: cmpCount!);
      /// Even if there is an alpha channel, it is actually meaningless, so we blank it.
      if (cmpCount! == 4) {
        interleaved = makeAlphaOpaque(argb: interleaved);
      }

      data.append(contentsOf: interleaved);
    }
    /// Update the pixel information to reflect reality. There is no alpha.
    bitmapInfo.rowBytes = rowBytes ;
    bitmapInfo.pixMapInfo?.pixelSize = cmpCount! * 8;
    return data;
  }
}

/// Direct bitmap operation opcode.
struct DirectBitOpcode : OpCode {
  mutating func load(reader: QuickDrawDataReader) throws {
    bitmapInfo = try reader.readQDPixMapInfoStart();
    switch bitmapInfo.pixMapInfo!.packType {
      case .noPack, .defaultPack:
        bitmapInfo.data = try reader.loadPixMapUnpacked(bitmapInfo: bitmapInfo);
      case .removePadByte:
        bitmapInfo.data = try reader.loadPixMapRemovePad(bitmapInfo: bitmapInfo);
      case .pixelRunLength:
        bitmapInfo.data = try reader.loadPixMapPixelRunLength(bitmapInfo: bitmapInfo);
      case .componentRunLength:
        bitmapInfo.data = try reader.loadPixMapComponentRunLength(bitmapInfo: &bitmapInfo);
    }
  }

  var bitmapInfo : QDBitMapInfo = QDBitMapInfo(isPacked: false);
}

/// Direct bitmap operation with mask opcode.
struct DirectBitOpcodeWithMask : OpCode {
  mutating func load(reader: QuickDrawDataReader) throws {
    bitmapInfo = try reader.readQDPixMapInfoStart();
    mask = try reader.readRegion();

    switch bitmapInfo.pixMapInfo!.packType {
      case .noPack, .defaultPack:
        bitmapInfo.data = try reader.loadPixMapUnpacked(bitmapInfo: bitmapInfo);
      case .removePadByte:
        bitmapInfo.data = try reader.loadPixMapRemovePad(bitmapInfo: bitmapInfo);
      case .pixelRunLength:
        bitmapInfo.data = try reader.loadPixMapPixelRunLength(bitmapInfo: bitmapInfo);
      case .componentRunLength:
        bitmapInfo.data = try reader.loadPixMapComponentRunLength(bitmapInfo: &bitmapInfo);
    }
  }

  var mask : QDRegion? = nil;
  var bitmapInfo : QDBitMapInfo = QDBitMapInfo(isPacked: false);
}
