//
//  QuickDrawPoint.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 17.04.2024.
//

import Foundation

/// Point in  QuickDraw space.
struct QDPoint : CustomStringConvertible, Equatable, Sendable {

  init(vertical: FixedPoint, horizontal: FixedPoint) {
    self.vertical = vertical;
    self.horizontal = horizontal;
  }
  
  public init <T : BinaryInteger> (vertical:  T, horizontal: T) {
    self.init(vertical: FixedPoint(vertical), horizontal: FixedPoint(horizontal));
  }
  
  public var description: String {
    return "<→\(horizontal),↓\(vertical)>";
  }
  
  static func + (point: QDPoint, delta: QDDelta) -> QDPoint {
    let vertical = point.vertical + delta.dv;
    let horizontal = point.horizontal + delta.dh;
    return QDPoint(vertical: vertical, horizontal: horizontal);
  }
  
  static func - (point: QDPoint, delta: QDDelta) -> QDPoint {
    return point + (-delta);
  }
  
  static func - (p1: QDPoint, p2: QDPoint) -> QDDelta {
    let dv = p1.vertical - p2.vertical;
    let dh = p1.horizontal - p2.horizontal;
    return QDDelta(dv: dv, dh: dh);
  }

  func mostNorthWest(point : QDPoint) -> QDPoint {
    let vertical = min(self.vertical, point.vertical);
    let horizontal = min(self.horizontal, point.horizontal);
    return QDPoint(vertical: vertical, horizontal: horizontal);
  }

  func mostSouthEast(point : QDPoint) -> QDPoint {
    let vertical = max(self.vertical, point.vertical);
    let horizontal = max(self.horizontal, point.horizontal);
    return QDPoint(vertical: vertical, horizontal: horizontal);
  }

  let vertical: FixedPoint;
  let horizontal: FixedPoint;
  
  static let zero = QDPoint(
    vertical: FixedPoint.zero, horizontal: FixedPoint.zero);
  
}

/// Relative position in Quickdraw space, functionally, this is the same as a point, but we distinguish
/// as adding deltas make sense, adding points does not.
struct QDDelta : CustomStringConvertible, Equatable, AdditiveArithmetic {
  
  init(dv : FixedPoint, dh : FixedPoint) {
    self.dv = dv;
    self.dh = dh;
  }
  
  init<T : BinaryInteger> (dv : T, dh : T) {
    self.dv = FixedPoint(dv);
    self.dh = FixedPoint(dh);
  }
  
  public var description: String {
    return "<∂→\(dh),∂↓\(dv)>";
  }
  
  let dh: FixedPoint;
  let dv: FixedPoint;
  
  static func + (a: QDDelta, b: QDDelta) -> QDDelta {
    return QDDelta(dv: a.dv + b.dv, dh: a.dh + b.dh);
  }
  
  static func - (lhs: QDDelta, rhs: QDDelta) -> QDDelta {
    return lhs + (-rhs);
  }
  
  static prefix func -(d: QDDelta) -> QDDelta {
    return QDDelta(dv: -d.dv, dh: -d.dh);
  }
  
  static let zero : QDDelta = QDDelta(dv: Int8(0), dh: Int8(0));
}

extension QuickDrawDataReader {
  
  func readPoint() throws -> QDPoint {
    let v = FixedPoint(try readInt16());
    let h = FixedPoint(try readInt16());
    return QDPoint(vertical: v, horizontal: h);
  }
  
  func readDelta() throws -> QDDelta {
    let h = try readInt16();
    let v = try readInt16();
    return QDDelta(dv:v, dh:h);
  }
}
