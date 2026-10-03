//
//  QuickDrawResolution.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 17.04.2024.
//

import Foundation

/// Quickdraw picture resolution, in DPI.
struct QDResolution : Equatable, CustomStringConvertible {
  let hRes : FixedPoint;
  let vRes : FixedPoint;
  
  public var description: String {
    return "\(hRes)×\(vRes)";
  }
  
  /// Scale a delta as a function of the resolution, relative to the standard (72 DPI).
  /// - Parameters:
  ///   - dim: dimension to scale
  ///   - resolution: resolution description
  /// - Returns: scales dimension
  public static func ⨴ (dim : QDDelta, resolution: QDResolution) -> QDDelta {
    let h = dim.dh.value * defaultScalarResolution.value / resolution.hRes.value;
    let v = dim.dv.value * defaultScalarResolution.value / resolution.vRes.value;
    return QDDelta(dv: FixedPoint(v), dh: FixedPoint(h));
  }
  
  /// Return a rectangle scaled for a given resolution
  /// - Parameters:
  ///   - rect: rectangle to scale
  ///   - resolution: resolution to use for scaling
  /// - Returns: a scaled rectangle.
  public static func ⨴ (rect: QDRect, resolution: QDResolution) -> QDRect {
    let d = rect.dimensions ⨴ resolution;
    return QDRect(topLeft: rect.topLeft, dimension: d);
  }
  
  static let defaultScalarResolution = FixedPoint(72);
  static let defaultResolution = QDResolution(
    hRes: defaultScalarResolution, vRes: defaultScalarResolution);
  static let zeroResolution = QDResolution(hRes: FixedPoint.zero, vRes: FixedPoint.zero);
}

extension QuickDrawDataReader {
  func readResolution() throws -> QDResolution {
    let hRes = try readFixed();
    let vRes = try readFixed();
    return QDResolution(hRes: hRes, vRes: vRes);
  }
}
