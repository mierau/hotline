//
//  IntelRaw.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 01.04.2024.
//

import Foundation

/// The YVU9 is a planar format, in which U and V are sampled every 4 pixels horizontally
/// and vertically (sometimes referred to as 16:1:1). The V plane appears before the U plane.
class IntelRawImage : PixMapMetadata, @unchecked Sendable {

  init(dimensions : QDDelta) {
    let h = roundTo(dimensions.dh, multipleOf: 4);
    let v = roundTo(dimensions.dv, multipleOf: 4);
    self.dimensions = QDDelta(dv:v ,dh:h);
    self.rowBytes = 3 * h;
    self.pixmap = [];
  }
  
  // This could probably be done using some optimised library.
  func load(data : consuming Data) throws {
    let lines = dimensions.dv.rounded;
    let columns = dimensions.dh.rounded;
    let ySize = lines * columns
    let yData = data[0..<ySize];
    let vuLines = (lines + 3) / 4;
    let vuColumns = (columns + 3) / 4;
    let vuSize = vuLines * vuColumns;
    let vData = data[ySize..<ySize+vuSize];
    let uData = data[ySize+vuSize..<ySize+vuSize*2];
    for l in 0..<lines {
      let vul = l / 4;
      for c in 0..<columns {
        let yOffset = l * columns + c + yData.startIndex;
        let y = yData[yOffset];
        let vuc = c / 4;
        let vuOffset = vul * vuColumns + vuc;
        let v = vData[vuOffset + vData.startIndex];
        let u = uData[vuOffset + uData.startIndex];
        let rgb = yuv2Rgb(yuv: YUV8(y: y, u: u, v: v))
        pixmap.append(contentsOf: rgb.bytes);
      }
    }
  }
  
  let dimensions: QDDelta;
  let rowBytes: Int;
  let cmpSize: Int = 8;
  let pixelSize: Int = 24;
  var clut: QDColorTable? = nil;
  var pixmap : [UInt8];
  
  var description: String {
    return "Intel Raw " + describePixMap(self);
  }
}
