//
//  QuickDrawRect.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 17.04.2024.
//

import Foundation

/// Rectangle
struct QDRect : CustomStringConvertible, Equatable, Sendable {
  
  init(topLeft: QDPoint, bottomRight: QDPoint) {
    self.topLeft = topLeft;
    self.bottomRight = bottomRight;
  }
  
  init(topLeft: QDPoint, dimension : QDDelta) {
    self.topLeft = topLeft;
    self.bottomRight = topLeft + dimension;
  }
  
  public var description: String {
    return "▭ ⌜\(topLeft),\(bottomRight)⌟"
  }
  
  let topLeft: QDPoint;
  let bottomRight: QDPoint;
  
  var dimensions : QDDelta {
    get {
      return bottomRight - topLeft;
    }
  }
  
  var center : QDPoint {
    get {
      let h = (topLeft.horizontal + bottomRight.horizontal) >> 1;
      let v = (topLeft.vertical + bottomRight.vertical) >> 1;
      return QDPoint(vertical: v, horizontal: h);
    }
  }
  
  var isEmpty : Bool {
    return dimensions.dh == .zero || dimensions.dv == .zero;
  }

  func contains(_ point: QDPoint) -> Bool {
    return
      point.horizontal >= topLeft.horizontal &&
      point.horizontal <= bottomRight.horizontal &&
      point.vertical >= topLeft.vertical &&
      point.vertical <= bottomRight.vertical;
  }

  static func + (rect: QDRect, delta: QDDelta) -> QDRect {
    let topleft = rect.topLeft + delta;
    let dimensions = rect.dimensions;
    return QDRect(topLeft: topleft, dimension: dimensions);
  }

  func extendToContain(point : QDPoint) -> QDRect {
    return QDRect(
        topLeft: topLeft.mostNorthWest(point: point),
        bottomRight: bottomRight.mostSouthEast(point: point));
  }

  static let empty = QDRect(topLeft: QDPoint.zero, bottomRight: QDPoint.zero);
}

extension QuickDrawDataReader {
  func readRect() throws -> QDRect  {
    let tl = try readPoint();
    let br = try readPoint();
    return QDRect(topLeft: tl, bottomRight: br);
  }
}
