import Foundation

enum Endianness {
  case big
  case little
}

extension Data {
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
  
  func read<T: FixedWidthInteger>(type: T.Type, at offset: Int) -> T? {
    guard offset >= 0, offset + MemoryLayout<T>.size <= self.count else {
      return nil // Ensure the offset is within the Data's range
    }
    
    return self.withUnsafeBytes { rawBufferPointer in
      let pointer = rawBufferPointer.baseAddress!
        .advanced(by: offset)
        .assumingMemoryBound(to: T.self)
      
//      switch endianness {
//      case .big:
      return pointer.pointee.bigEndian
//      case .little:
//        return pointer.pointee.littleEndian
//      }
    }
  }
  
  func readString(at offset: Int, length: Int, encoding: String.Encoding) -> String? {
    return String(data: self[offset..<(offset + length)], encoding: encoding)
  }
}
