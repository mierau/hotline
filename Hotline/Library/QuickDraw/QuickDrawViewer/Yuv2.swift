//
//  Yuv2.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 31.01.2024.
//
// Decoder for the QuickTime `yuv2` codec.

import Foundation
import CoreGraphics

/// Convert  YUV data into RGB
/// - Parameter data: YUV bytes
/// - Returns: RGB8 bytes.
func convertYuv2Data(data: Data) -> [UInt8] {
  var rgb : [UInt8] = [];
  let pixelPairCount = data.count / 4;
  // Each pixel pair has 2×3 bytes.
  rgb.reserveCapacity(pixelPairCount * 6);
  for i in 0..<pixelPairCount {
    let start = i * 4;
    let y1 = data[start];
    let u  = data[start + 1];
    let y2 = data[start + 2];
    let v  = data[start + 3];
    rgb.append(contentsOf: signedYuv2Rgb(y:y1, u:u, v:v).bytes);
    rgb.append(contentsOf: signedYuv2Rgb(y:y2, u:u, v:v).bytes);
  }
  return rgb;
}

