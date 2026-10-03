//
//  FixedPoint.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 18.01.2024.
//

import Foundation

///  Quickdraw uses integer coordinates, most of the time.
///  Some values can be fixed point (horizontal position in particular).
///  So we use a fixed point value to represent coordinates.
///  This type supports math operations that could be done quickly on a 68000 processor:
///  - addition, substraction
///  - shifts
public struct FixedPoint : CustomStringConvertible, Comparable, AdditiveArithmetic, Hashable, Sendable {
  
  public typealias Magnitude = Self;
  
  public init (rawValue: Int) {
    self.fixedValue = rawValue;
  }
  
  public init (_ value: Double) {
    let m = value * Double(FixedPoint.multiplier);
    self.fixedValue = Int(m.rounded());
  }
  
  public init <T : BinaryInteger> (_ value: T) {
    self.fixedValue = Int(value) * FixedPoint.multiplier;
  }
  
  private let fixedValue : Int;
  private static let multiplier : Int = 0x10000;
  private static let fractionMask : Int = multiplier - 1;
  
  public static let zero = FixedPoint(rawValue: 0);
  public static let one = FixedPoint(rawValue: multiplier);
  
  public var magnitude: FixedPoint {
    return FixedPoint(rawValue: Int(fixedValue.magnitude));
  }
  
  /// Return a compact, description.
  /// Use Unicode fraction to denote _perfect_ fractions that are typically used for line width and such.
  public var description: String {
    switch fixedValue {
      case 0 :
        return "0";
      case 0x8000:
        return "½";
      // Quarters
      case 0x4000:
        return "¼";
      case 0xc000:
        return "¾";
      // Eights
      case 0x2000:
        return "⅛";
      case 0x6000:
        return "⅜";
      case 0xA000:
        return "⅝";
      case 0xE000:
        return "⅞";
      case let fixedValue where fixedValue & FixedPoint.fractionMask == 0:
        return "\(rounded)";
      default:
        return "\(value)";
    }
  }
  
  public var rounded : Int {
    return fixedValue / FixedPoint.multiplier;
  }
  
  public var fractionPart : FixedPoint {
    return FixedPoint(rawValue : self.fixedValue & FixedPoint.fractionMask);
  }
  
  public var value : Double {
    return Double(fixedValue) / Double(FixedPoint.multiplier);
  }
  
  public var isRound : Bool {
    return fixedValue & FixedPoint.fractionMask == 0;
  }
  
  /// Addition
  /// - Parameters:
  ///   - a: left hand value to add
  ///   - b: right hand value to add
  /// - Returns: A fixed point with the sum of a + b.
  public static func + (a: FixedPoint, b: FixedPoint) -> FixedPoint {
    return FixedPoint(rawValue: a.fixedValue + b.fixedValue);
  }
  
  /// Substraction
  /// - Parameters:
  ///   - a: left hand value to add
  ///   - b: right hand value to add
  /// - Returns: A fixed point with the difference  a - b.
  public static func - (a: FixedPoint, b: FixedPoint) -> FixedPoint {
    return FixedPoint(rawValue: a.fixedValue - b.fixedValue);
  }
  
  /// Negation
  /// - Parameter v: value to negate
  /// - Returns: return the negative value of v.
  static prefix func -(v: FixedPoint) -> FixedPoint {
    return FixedPoint(rawValue: -v.fixedValue);
  }
  
  /// Shift right.
  /// - Parameters:
  ///   - v: fixed point value to shift
  ///   - s: number of right shifts
  /// - Returns: value shift to the right, Note that 1 >> 1 = 0.5
  static func >> (v: FixedPoint, s: Int) -> FixedPoint {
    let raw = v.fixedValue >> s;
    return FixedPoint(rawValue: raw);
  }
  
  /// Shift left
  /// - Parameters:
  ///   - v: fixed point value to shift
  ///   - s: number of left shifts
  /// - Returns: <#description#>
  static func << (v: FixedPoint, s: Int) -> FixedPoint {
    let raw = v.fixedValue << s;
    return FixedPoint(rawValue: raw);
  }
  
  public static func < (lhs: FixedPoint, rhs: FixedPoint) -> Bool {
    return lhs.fixedValue < rhs.fixedValue;
  }
  
  public static func * (lhs: FixedPoint, rhs: FixedPoint) -> FixedPoint {
    return FixedPoint(rawValue: lhs.fixedValue * rhs.fixedValue / multiplier);
  }
  
  public static func *= (lhs: inout FixedPoint, rhs: FixedPoint) {
    lhs = lhs * rhs;
  }
  
  /// We need division to parse `fract` types.
  /// - Parameters:
  ///   - a: numerator
  ///   - b: denominator
  /// - Returns: a/b
  public static func / (a : FixedPoint, b: FixedPoint) -> FixedPoint {
    return FixedPoint(a.value / b.value);
  }
}

func roundTo(_ value: FixedPoint, multipleOf: Int) -> Int {
  return (value.rounded + (multipleOf - 1)) / multipleOf * multipleOf;
}

extension QuickDrawDataReader {
  
  func readFixed() throws -> FixedPoint {
    let v = try readInt32();
    return FixedPoint(rawValue: Int(v));
  }
}
