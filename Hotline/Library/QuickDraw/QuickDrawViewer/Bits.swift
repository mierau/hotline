//
//  Bits.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 09.03.2024.
//
// Various low level bit and memory manipulation utilities.

import Foundation

extension Data {
  var bytes: [UInt8] {
    return [UInt8](self)
  }
}

extension SIMD4<UInt8> {
  var bytes: [UInt8] {
    return [self.x, self.y, self.z, self.w];
  }
}

extension Int {
  /// Returns the integer value clamped to the 8-bit unsigned range (0 to 255).
  var clampedToByteRange: Int {
    return Int(UInt8(clamping: self))
  }
}

/// Convert some integer type into a sequence of boolean, starting from the most significant bit.
/// - Parameter from: number to convert
/// - Returns: an array of boolean
func boolArray<T>(_ from: T) -> [Bool] where T : FixedWidthInteger {
  var buffer = from;
  let mask : T = 1 << (T.bitWidth - 1);
  var result : [Bool] = [];
  for _ in 0..<T.bitWidth {
    let match = buffer & mask != 0;
    result.append(match);
    buffer = buffer << 1;
  }
  return result;
}

func toScalar<T>(bytes : ArraySlice<UInt8>) -> T where T: FixedWidthInteger {
  return bytes.reduce(0) { T($0) << 8 + T($1) }
}

func makeUInt24(bytes: (UInt8, UInt8, UInt8)) -> UInt32 {
  return UInt32(bytes.0) << 16 | UInt32(bytes.1) << 8 | UInt32(bytes.2);
}

func byteArrayLE<T>(from value: T) -> [UInt8] where T: FixedWidthInteger {
  withUnsafeBytes(of: value.littleEndian, Array.init)
}

func byteArrayBE<T>(from value: T) -> [UInt8] where T: FixedWidthInteger {
  withUnsafeBytes(of: value.bigEndian, Array.init)
}


struct BitReader {
  private let data: [UInt8]
  private var byteOffset = 0
  private var bitCount = 0
  private var buffer: UInt64 = 0

  init(data: [UInt8]) { self.data = data }

  mutating func skipBytes(_ count: Int) -> Void {
    byteOffset += count;
  }

  mutating func getbits(_ count: Int) -> Int? {
    guard count > 0 else { return nil }
    while bitCount < count {
      guard byteOffset < data.count else { return nil }
      // Change: shift left instead of using bit position
      buffer = (buffer << 8) | UInt64(data[byteOffset])
      bitCount += 8
      byteOffset += 1
    }
    bitCount -= count
    // Change: extract from top bits
    let result = Int((buffer >> bitCount) & ((1 << count) - 1))
    return result
  }
}
