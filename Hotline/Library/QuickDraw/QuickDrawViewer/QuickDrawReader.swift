//
//  QuickDrawReader.swift
//  QuickDrawKit
//
//  Created by Matthias Wiesmann on 20.12.2023.
//

import Foundation

/// Class that handles reading from the data object.
/// Handles deserialisation of basic QuickDraw types.
/// Reading of high-level objects (points, rectangles, regions), is handled in extensions along the type definitions.
class QuickDrawDataReader {
  
  ///  Initializes a reader from a data object.
  /// - Parameters:
  ///   - data: object containing the QuickDraw pict data.
  ///   - position: offset in the data object where reading should start, typically 512 as this is the standart offset.
  init(data: Data, position: Data.Index=512) throws {
    guard position <= data.count else {
      throw QuickDrawError.quickDrawIoError(message: "Initial position \(position) beyond \(data.count)");
    }
    guard position >= 0 else {
      throw QuickDrawError.quickDrawIoError(message:"Initial positon \(position)  is negative");
    }
    self.data = data;
    self.currentIndex = position;
  }
  
  func peekUInt8() throws -> UInt8 {
    guard currentIndex < data.count else {
      throw QuickDrawError.quickDrawIoError(message:"Peek at \(currentIndex) beyond \(data.count)");
    }
    return data[currentIndex];
  }
  
  func readUInt8() throws -> UInt8 {
    let value = try peekUInt8();
    currentIndex += 1;
    return value;
  }
  
  func readBool() throws -> Bool {
    let v = try readUInt8();
    return v > 0;
  }
  
  func readUInt8(bytes: Data.Index) throws -> [UInt8] {
    let subdata = try readData(bytes: bytes);
    return subdata.bytes;
  }
  
  func readSlice(bytes: Data.Index) throws -> ArraySlice<UInt8> {
    let start = self.currentIndex;
    self.currentIndex += bytes;
    let end = self.currentIndex;
    guard end <= data.count else {
      throw QuickDrawError.quickDrawIoError(message:"ReadSlice \(bytes):\(end) beyond \(data.count)");
    }
    return data.bytes[start..<end];
  }
  
  func readData(bytes: Data.Index) throws -> Data {
    guard bytes >= 0 else {
      throw QuickDrawError.quickDrawIoError(message: "Negative amount of bytes \(bytes)");
    }
    let end = currentIndex + bytes;
    guard end <= data.count else {
      throw QuickDrawError.quickDrawIoError(message:"Read \(bytes):\(end) beyond \(data.count)");
    }
    let result = data.subdata(in: currentIndex..<currentIndex + bytes);
    currentIndex += bytes;
    return result;
  }
  
  func readFullData() throws -> Data {
    return try readData(bytes: remaining);
  }
  
  func subReader(bytes: Data.Index) throws -> QuickDrawDataReader {
    let data = try readData(bytes : bytes);
    let sub = try QuickDrawDataReader(data: data, position: 0);
    sub.filename = self.filename;
    return sub;
  }
  
  func readString(bytes: Data.Index) throws -> String {
    let data = try readUInt8(bytes: bytes);
    guard let str = String(bytes:data, encoding: String.Encoding.macOSRoman) else {
      throw QuickDrawError.quickDrawIoError(message: String(localized: "Failed reading string"));
    }
    return str;
  }
  
  /// Read a fixed length (31 bytes) pascal string
  /// - Returns: a string , with a maximum 31 characters.
  func readStr31() throws -> String {
    let length = Data.Index(try readUInt8());
    let tail = 31 - length ;
    guard tail >= 0 else {
      throw QuickDrawError.invalidStr32(length: length);
    }
    let result = try readString(bytes:length);
    skip(bytes: tail);
    return result;
  }
  
  /// Read a Pascal string (length byte, followed by text bytes).
  /// - Returns: a string, with a maximum of 255 characters.
  func readPascalString() throws -> String {
    let length = Data.Index(try readUInt8());
    return try readString(bytes:length);
  }
  
  func readInt8() throws -> Int8 {
    return try Int8(bitPattern: readUInt8());
  }
  
  func readUInt16() throws -> UInt16 {
    let bytes = try readSlice(bytes: 2);
    return toScalar(bytes: bytes);
  }
  
  func readUInt16(bytes: Data.Index) throws -> [UInt16] {
    let num = bytes / 2;
    let raw = try readSlice(bytes: num * 2);
    var result :[UInt16] = [];
    result.reserveCapacity(num);
    for index in 0..<(num) {
      let p = index * 2 + raw.startIndex;
      let s = raw[p..<p + 2];
      let v : UInt16 = toScalar(bytes: s);
      result.append(v);
    }
    return result;
  }
  
  func readUInt16LE() throws ->  UInt16 {
    let v = try readUInt16();
    return v.byteSwapped;
  }
  
  func readUInt32LE() throws -> UInt32 {
    let v = try readUInt32();
    return v.byteSwapped;
  }
  
  func readInt16() throws -> Int16 {
    return Int16(bitPattern: try readUInt16());
  }
  
  func readUInt32() throws  -> UInt32 {
    let bytes = try readSlice(bytes: 4);
    return toScalar(bytes: bytes);
  }
  
  func readInt32() throws -> Int32 {
    return Int32(bitPattern: try readUInt32());
  }
  
  func readUInt64() throws -> UInt64 {
    let bytes = try readSlice(bytes: 8);
    return toScalar(bytes: bytes);
  }
  
  func readOpcode(version: Int) throws -> UInt16 {
    switch version {
      case 1:
        let opcode = try readUInt8()
        return UInt16(opcode);
      case 2:
        if (currentIndex % 2) == 1 {
          currentIndex+=1;
        }
        let opcode = try readUInt16()
        return opcode;
      default:
        throw QuickDrawError.unknownQuickDrawVersionError(version:version);
    }
  }
  
  func skip(bytes: Data.Index) -> Void {
    currentIndex += bytes;
  }
  
  var remaining : Int {
    return data.count - currentIndex;
  }
  
  var currentIndex: Data.Index;
  var data: Data;
  var filename : String?;
}
