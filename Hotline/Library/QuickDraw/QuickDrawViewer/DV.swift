//
//  DV.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 07.07.2025.
//

import Foundation
import CoreMedia
import VideoToolbox

// Generic decoder that uses Core Video to decode one video frame.
class DVImage : PixMapMetadata, @unchecked Sendable {

  init(codec: MacTypeCode, dimensions : QDDelta) throws {
    self.codec = codec;
    self.dimensions = dimensions;
    self.pixmap = [];
    self.formatDescription = try makeCMFormatDescription(codec: codec, dimensions: dimensions);
  }

  let codec: MacTypeCode;
  let dimensions: QDDelta;
  var rowBytes: Int = 0;
  let cmpSize: Int = 8;
  let pixelSize: Int = 24;
  var clut: QDColorTable? = nil;
  var pixmap : [UInt8];
  let formatDescription : CMFormatDescription;

  var description: String {
    return "Video \(codec)} " + describePixMap(self);
  }

  func load(data : consuming Data) throws {
    let session = try makeVTDecodingSession(
      formatDescription: formatDescription, toFormat:  kCVPixelFormatType_24RGB);
    let sampleBuffer = try makeCMSampleBuffer(formatDescription: formatDescription, data: data);
    let (rowBytes, pixmap) = try decodeBuffer(session: session, sampleBuffer: sampleBuffer);
    self.pixmap = pixmap;
    self.rowBytes = rowBytes;
  }
}
