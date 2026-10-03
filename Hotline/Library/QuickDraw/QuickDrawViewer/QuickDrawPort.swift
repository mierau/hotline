//
//  QuickDrawPort.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 21.03.2024.
//

import Foundation

struct QDPortBits : OptionSet {
  let rawValue: UInt16;
  static let textEnable = QDPortBits(rawValue: 1 << 0);
  static let lineEnable = QDPortBits(rawValue: 1 << 1);
  static let rectEnable = QDPortBits(rawValue: 1 << 3);
  static let rRectEnable = QDPortBits(rawValue: 1 << 4);
  static let ovalEnable = QDPortBits(rawValue: 1 << 5);
  static let arcEnable = QDPortBits(rawValue: 1 << 6);
  static let polyEnable = QDPortBits(rawValue: 1 << 7);
  static let rgnEnable = QDPortBits(rawValue: 1 << 8);
  static let bitsEnable = QDPortBits(rawValue: 1 << 9);
  static let commentsEnable = QDPortBits(rawValue: 1 << 10);
  static let txtMeasEnable = QDPortBits(rawValue: 1 << 11);
  static let clipEnable = QDPortBits(rawValue: 1 << 12);
  static let quickTimeEnable = QDPortBits(rawValue: 1 << 13);
  static let gradientEnable = QDPortBits(rawValue: 1 << 14);
  static let defaultState = QDPortBits([
    textEnable, lineEnable, rectEnable, rRectEnable, ovalEnable,
    arcEnable, polyEnable, rgnEnable, bitsEnable, commentsEnable,
    txtMeasEnable, clipEnable, quickTimeEnable
  ]);
}

protocol QuickDrawPort {
  // QuickDraw Bottleneck functions
  func stdPoly(polygon: QDPolygon, verb: QDVerb) throws -> Void;
  func stdRect(rect : QDRect, verb: QDVerb) throws -> Void;
  func stdOval(rect : QDRect, verb: QDVerb) throws -> Void;
  func stdText(text : String) throws -> Void;
  func stdRegion(region : QDRegion, verb: QDVerb) throws -> Void;
  func stdRoundRect(rect : QDRect, verb: QDVerb) throws -> Void;
  func stdLine(points: [QDPoint]) throws -> Void;
  func stdArc(rect: QDRect, startAngle : Int16, angle: Int16, verb: QDVerb) throws -> Void;
  // QuickDraw does not support gradient, but this dispatches comments.
  func stdGradient(gradient: GradientDescription) throws -> Void;

  // Port state
  var penState : QDPenState {get  set };
  var fontState : QDFontState {get set};
  var portBits : QDPortBits {get set};
  // Last values
  var lastPoly : QDPolygon { get set};
  var lastRect : QDRect {get set};
  var lastRegion : QDRegion { get set};
}


protocol QuickDrawRenderer {
  func execute(opcode: OpCode) throws -> Void;
  func execute(picture: QDPicture, zoom: Double) throws -> Void;
  /// Bottleneck functions
}
