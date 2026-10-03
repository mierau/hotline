//
//  TypeCode.swift
//  QuickDrawViewer
//
//  Created by Matthias Wiesmann on 04.02.2024.
//

import Foundation

enum MacTypeError: Error {
  case notMacRoman(str: String);
  case invalidLength(length: Int);
}

/// Types on the classic mac were identified using four letter codes.
/// These were stored as 4 bytes inside an 32 bit integer.
struct MacTypeCode : RawRepresentable, CustomStringConvertible, Sendable {
  init(rawValue: UInt32) {
    self.rawValue = rawValue;
  }
  
  init(fromString: String) throws {
    guard let data = fromString.cString(using: .macOSRoman) else {
      throw MacTypeError.notMacRoman(str: fromString);
    }
    // There could be a zero at the end
    guard data.count >= 4 else {
      throw MacTypeError.invalidLength(length: data.count);
    }
    rawValue =
    UInt32(data[0]) << 24 |
    UInt32(data[1]) << 16 |
    UInt32(data[2]) << 8 |
    UInt32(data[3]);
  }
  
  var description: String {
    let data = byteArrayBE(from: rawValue);
    return String(bytes:data, encoding: String.Encoding.macOSRoman) ?? "\(rawValue)";
  }
  
  let rawValue: UInt32;
  static let zero = MacTypeCode(rawValue: 0);
}

extension QuickDrawDataReader {
  func readType() throws -> MacTypeCode {
    let data = try readUInt32();
    return MacTypeCode(rawValue:data);
  }
}
