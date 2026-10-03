//
//  QuickDrawPolygon.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 17.04.2024.
//

import Foundation

struct PolygonOptions : OptionSet, CustomStringConvertible {
  var rawValue: UInt8;
  static let frame = PolygonOptions(rawValue: 1 << 0);
  static let fill = PolygonOptions(rawValue: 1 << 1);
  static let close = PolygonOptions(rawValue: 1 << 2);
  static let smooth = PolygonOptions(rawValue: 1 << 3);
  static let empty = PolygonOptions([]);
  
  var description: String {
    var result : String = "PolySmoothVerb "
    if contains(.frame) {result += " frame"}
    if contains(.fill) {result += " fill"}
    if contains(.close) {result += " close"}
    if contains(.smooth) {result += " smooth"}
    return result;
  }
}

class QDPolygon : CustomStringConvertible {
  var description: String {
    return "⬡ \(points.count) points";
  }

  init(points: [QDPoint]) {
    self.points = points;
    self.options = PolygonOptions.empty;
  }

  var points : [QDPoint] = [];
  var options : PolygonOptions;

  func addLine(line : [QDPoint]) {
    if self.points.isEmpty {
      self.points = line;
      return;
    }
    if line.first == points.last {
      points.removeLast();
    }
    points.append(contentsOf: line);
  }

  var boundingBox : QDRect {
    if points.isEmpty {
      return .empty;
    }
    var topLeft = points[0];
    var bottomRight = points[0];

    for (position, point)  in points.enumerated() {
      if position == 0 {
        continue;
      }
      topLeft = topLeft.mostNorthWest(point: point);
      bottomRight = bottomRight.mostSouthEast(point: point);
    }
    return  QDRect(topLeft: topLeft, bottomRight: bottomRight);
  }
}

extension QuickDrawDataReader {
  func readPoly() throws -> QDPolygon {
    let raw_size = try readUInt16();
    let _ = try readRect();

    let pointNumber = (raw_size - 10) / 4;
    var points : [QDPoint]  = [];
    if pointNumber > 0 {
      for  _ in 1...pointNumber {
        points.append(try readPoint());
      }
    }
    return QDPolygon(points: points);
  }
}

