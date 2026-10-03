//
//  MacPaint.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 29.02.2024.
//
// Decoder for the MacPaint QuickTime codec.
// As well as support for loading MacPaint files by converting them to pictures.

import Foundation

/// MacPaint images are fixed size (720 × 576) PackBit compressed bitmaps.
///  See http://preserve.mactech.com/articles/mactech/Vol.01/01.07/MacPaintfiles/index.html
class MacPaintImage : PixMapMetadata, @unchecked Sendable {

  static let width : Int = 576;
  static let height : Int = 720;

  /// Some online documents claim that MacPaint sometime have a longer header.
  /// This is technically not the case, but typically a symptom that the file is in AppleSingle format.
  static let fileHeaderSize = 512;

  func load(data : Data) throws {
    let a = Array(data);
    self.bitmap = try decompressPackBit(
      data: a[0..<a.count], unpackedSize: MacPaintImage.height * rowBytes, byteNum: 1, checkSize: false);
  }
  
  /// Convert the MacPaint images into an opcode.
  /// This could be a QuickTime opcode that embeds the MacPaint data, but
  /// this is very involved, instead we just build a `BitRectOpcode`.
  func makeOpcode() -> some OpCode {

    let bitmapInfo = QDBitMapInfo(isPacked: true);
    bitmapInfo.rowBytes = self.rowBytes;
    let frame = QDRect(topLeft: .zero, dimension: self.dimensions);
    bitmapInfo.bounds = frame;
    bitmapInfo.srcRect = frame;
    bitmapInfo.dstRect = frame;
    bitmapInfo.data = bitmap;
    var bitRect = BitRectOpcode(isPacked: true);
    bitRect.bitmapInfo = bitmapInfo;
    return bitRect;
  }
  
  /// Convert a MacPaint images into a minimalistic picture.
  /// This is enough for this program, but a valid quickdraw file would have some header operations.
  func macPicture(filename: String?) -> QDPicture {
    let frame = QDRect(topLeft: .zero, dimension: self.dimensions);
    let picture = QDPicture(size: -1, frame: frame, filename: filename);
    picture.opcodes.append(makeOpcode());
    return picture;
  }
  
  let rowBytes: Int = MacPaintImage.width / 8;
  var cmpSize: Int = 1;
  var pixelSize: Int = 1;
  let dimensions = QDDelta(
      dv: FixedPoint(MacPaintImage.height),
      dh: FixedPoint(MacPaintImage.width));
  var clut: QDColorTable? = QDColorTable.palette1;
  var bitmap: [UInt8] = [];
  
  var description: String {
    let pm = describePixMap(self);
    return "MacPaint: \(pm)";
  }
}
