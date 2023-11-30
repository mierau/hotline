import Foundation

enum Endianness {
  case big
  case little
}

extension Data {
  init(_ val: UInt8) {
    self.init()
    self.appendUInt8(val)
  }
  
  init(_ val: UInt16) {
    self.init()
    self.appendUInt16(val)
  }
  
  init(_ val: UInt32) {
    self.init()
    self.appendUInt32(val)
  }
  
  func readUInt8(at offset: Int) -> UInt8? {
    guard offset >= 0, offset + MemoryLayout<UInt8>.size <= self.count else {
      return nil
    }
    return self[offset]
  }
  
  func readUInt16(at offset: Int, endianness: Endianness = .big) -> UInt16? {
    guard offset >= 0, offset + MemoryLayout<UInt16>.size <= self.count else {
      return nil
    }
    let value = self.subdata(in: offset..<(offset + MemoryLayout<UInt16>.size)).withUnsafeBytes { $0.load(as: UInt16.self) }
    return (endianness == .big) ? value.bigEndian : value.littleEndian
  }
  
  func readUInt32(at offset: Int, endianness: Endianness = .big) -> UInt32? {
    guard offset >= 0, offset + MemoryLayout<UInt32>.size <= self.count else {
      return nil
    }
    let value = self.subdata(in: offset..<(offset + MemoryLayout<UInt32>.size)).withUnsafeBytes { $0.load(as: UInt32.self) }
    return (endianness == .big) ? value.bigEndian : value.littleEndian
  }
  
  func readData(at offset: Int, length: Int) -> Data? {
    guard offset >= 0, offset + length <= self.count else {
      return nil
    }
    return self[offset..<(offset + length)]
  }
  
  func readString(at offset: Int, length: Int, encoding: String.Encoding) -> String? {
    return String(data: self[offset..<(offset + length)], encoding: encoding)
  }
  
  
  mutating func appendUInt8(_ value: UInt8, endianness: Endianness = .big) {
    var val = endianness == .big ? value.bigEndian : value.littleEndian
    append(&val, count: MemoryLayout<UInt8>.size)
  }
  
  mutating func appendUInt16(_ value: UInt16, endianness: Endianness = .big) {
    var val = endianness == .big ? value.bigEndian : value.littleEndian
    Swift.withUnsafeBytes(of: &val) { buffer in
      append(buffer.bindMemory(to: UInt8.self))
    }
//    append(&val, count: MemoryLayout<UInt16>.size)
  }
  
  mutating func appendUInt32(_ value: UInt32, endianness: Endianness = .big) {
    var val = endianness == .big ? value.bigEndian : value.littleEndian
    Swift.withUnsafeBytes(of: &val) { buffer in
      append(buffer.bindMemory(to: UInt8.self))
    }
//    append(&val, count: MemoryLayout<UInt32>.size)
  }
}
