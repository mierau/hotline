//
//  QuickTake.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 06.10.2025.
//
/// Class to handle QuickTake images
/// These are basically the raw camera data wrapped in QuickTime container in a PICT.

import Foundation

enum QuickTakeError: LocalizedError {
  case bitReadFailed;
}

private func sharpForDelta(_ v: Int) -> Int {
  switch v {
    case 0..<4: return 0
    case 4..<8: return 1
    case 8..<16: return 2
    case 16..<32: return 3
    case 32..<48: return 4
    default: return 5
  }
}

/// Decode the raw bit stream into an array of 10 bit values.
 func quickTake100Decode(bitStream: [UInt8], width: Int, height: Int) throws -> [Float] {
  // Lookup tables
  let gstep: [Int16] = [
    -89, -60, -44, -32, -22, -15, -8, -2,
     2, 8, 15, 22, 32, 44, 60, 89
  ]

  let rstep: [[Int16]] = [
    [-3, -1, 1, 3],
    [-5, -1, 1, 5],
    [-8, -2, 2, 8],
    [-13, -3, 3, 13],
    [-19, -4, 4, 19],
    [-28, -6, 6, 28]
  ]

  var reader = BitReader(data: bitStream)
  reader.skipBytes(12);

  // Work buffer with border to handle predictors.
  var pixel = Array(repeating: Array(repeating: UInt8(0x80), count: width + 4), count: height + 4)

  /// First data block: green pixels, disposition: ▚
  for row in 2..<(height + 2) {
    for col in stride(from: 2 + (row & 1), to: width + 2, by: 2) {
      guard let bits = reader.getbits(4) else { throw QuickTakeError.bitReadFailed }

      let pred = (
        Int(pixel[row - 1][col - 1]) +
        2 * Int(pixel[row - 1][col + 1]) +
        Int(pixel[row][col - 2])) / 4;
      let val = UInt8(clamping: pred + Int(gstep[bits]))
      pixel[row][col] = val;

      if col < 4 {
        pixel[row][col - 2] = val
        pixel[row + 1][~row & 1] = val
      }
      if row == 2 {
        pixel[row - 1][col + 1] = val
        pixel[row - 1][col + 3] = val
      }
    }
    pixel[row][width + 2] = pixel[row][width + 1]
  }

  /// Second data block: red/blue pixels, disposition:  ▞
  for redblue in 0..<2 {
    for row in stride(from: 2 + redblue, to: height + 2, by: 2) {
      for col in stride(from: 3 - (row & 1), to: width + 2, by: 2) {
        let sharp: Int
        if row < 4 || col < 4 {
          sharp = 2
        } else {
          let deltas =
          abs(Int(pixel[row - 2][col]) - Int(pixel[row][col - 2])) +
          abs(Int(pixel[row - 2][col]) - Int(pixel[row - 2][col - 2])) +
          abs(Int(pixel[row][col - 2]) - Int(pixel[row - 2][col - 2]))
          sharp = sharpForDelta(deltas);
        }

        guard let bits = reader.getbits(2) else { throw QuickTakeError.bitReadFailed }
        let pred = (Int(pixel[row - 2][col]) + Int(pixel[row][col - 2])) / 2;
        let val = UInt8(clamping: pred + Int(rstep[sharp][bits]));
        pixel[row][col] = val;
        if row < 4 {
          pixel[row - 2][col + 2] = val
        }
        if col < 4 {
          pixel[row + 2][col - 2] = val
        }
      }
    }
  }

  /// Green refinement
  for row in 2..<(height + 2) {
    for col in stride(from: 3 - (row & 1), to: width + 2, by: 2) {
      let left = Int(pixel[row][col - 1]);
      let center = Int(pixel[row][col]);
      let right = Int(pixel[row][col + 1]);

      // Weighted average without aggressive offset
      let val = (left + (center * 4) + right) / 2 - 0x100;
      pixel[row][col] = UInt8(clamping: val)
    }
  }

  /// Convert to float and  move into height × width buffer.
  /// The response curve was making things worse.
  var output = [Float](repeating: 0, count: width * height)
  for row in 0..<height {
    for col in 0..<width {
      let v = Float(pixel[row + 2][col + 2]) / 255.0;
      output[row * width + col] = v;
    }
  }

  return output
}


func convertCMYGToYuv(cmyg: [Float], width: Int, height: Int) -> YUV420Image {
  // let temperatureAdjutement = Float(0);
  let halfWidth = width / 2
  let halfHeight = height / 2
  var yPlane = Array<UInt8>(repeating: 0, count: width * height)
  var uPlane = Array<UInt8>(repeating: 0, count: halfWidth * halfHeight)
  var vPlane = Array<UInt8>(repeating: 0, count: halfWidth * halfHeight)

  for row in stride(from: 0, to: height, by: 2) {
    for col in stride(from: 0, to: width, by: 2) {
      let offset = (row * width) + col;
      let green = cmyg[offset];
      let magenta = cmyg[offset + 1];
      let cyan = cmyg[offset + width];
      let yellow = cmyg[offset + width + 1];

      // Use harmonic mean to approximate 45° angle between components.
      let r = harmonicMean(magenta, yellow);
      let g = harmonicMean(cyan, yellow);
      let b = harmonicMean(cyan, magenta);

      let average_green = average(g, green);

      // Get U/V for the block
      let yuv = rgb2Yuv(
        r: r, g: average_green, b: b, temperature: 0.00, saturation: 5.0);
      // Use raw sensor values as luminance
      yPlane[offset] = average(green.normalizedByte, yuv.y);
      yPlane[offset + 1] = average(magenta.normalizedByte, yuv.y);
      yPlane[offset + width] = average(cyan.normalizedByte, yuv.y);
      yPlane[offset + width + 1] = average(yellow.normalizedByte, yuv.y);
      let halfOffset = (row / 2 * halfWidth) + (col / 2)
      uPlane[halfOffset] = yuv.u;
      vPlane[halfOffset] = yuv.v;
    }
  }
  let yCorrected = boostShadowsSelective(yPlane, strength: 1.2, threshold: 64);
  return YUV420Image(width: width, height: height, yPlane: yCorrected, uPlane: uPlane, vPlane: vPlane)
}

func decodeQTKND(dimensions: QDDelta, data : Data) throws -> YUV420Image {
  let width = dimensions.dh.rounded;
  let height = dimensions.dv.rounded;
  let raw = try quickTake100Decode(bitStream: data.bytes, width: width , height: height);
  return convertCMYGToYuv(cmyg: raw, width: width, height: height);
}






