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
    guard offset >= 0, offset + 1 <= self.count else {
      return nil
    }
    return self[offset]
  }
  
  func readUInt16(at offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= self.count else {
      return nil
    }
    
    return (UInt16(self[offset]) << 8) + UInt16(self[offset + 1])
  }
  
  func readUInt32(at offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= self.count else {
      return nil
    }
    
    return (UInt32(self[offset]) << 24) + (UInt32(self[offset + 1]) << 16) + (UInt32(self[offset + 2]) << 8) + UInt32(self[offset + 3])
  }
  
  func readUInt64(at offset: Int) -> UInt64? {
    guard offset >= 0, offset + 8 <= self.count else {
      return nil
    }
    
    return withUnsafeBytes { $0.load(as: UInt64.self ) }
  }
  
  func readDate(at offset: Int) -> Date? {
    guard offset >= 0, offset + 2 + 2 + 4 <= self.count else {
      return nil
    }
    
    if
      let year = self.readUInt16(at: offset),
      let ms = self.readUInt16(at: offset + 2),
      let secs = self.readUInt32(at: offset + 2 + 2) {
      return convertHotlineDate(year: year, seconds: secs, milliseconds: ms)
    }
    
    return nil
  }
    
  func readData(at offset: Int, length: Int) -> Data? {
    guard offset >= 0, offset + length <= self.count else {
      return nil
    }
    return self.subdata(in: offset..<(offset + length))
  }

  func readString(at offset: Int, length: Int) -> String? {
    let subdata = self[offset..<(offset + length)]
    if subdata.count == 0 {
      return ""
    }
    
    let allowedEncodings = [
      NSUTF8StringEncoding,
      NSShiftJISStringEncoding,
      NSUnicodeStringEncoding,
      NSWindowsCP1251StringEncoding
    ]

    var decodedNSString: NSString?
    let rawValue = NSString.stringEncoding(for: subdata, encodingOptions: [.allowLossyKey: false], convertedString: &decodedNSString, usedLossyConversion: nil)
    
    if allowedEncodings.contains(rawValue) {
      return decodedNSString as? String
    }
    
    else if rawValue > 1 {
      print("ENCODING FOUND \(rawValue)")
    }
    
    var macStr = String(data: subdata, encoding: .macOSRoman)
    if macStr == nil {
      macStr = String(data: subdata, encoding: .nonLossyASCII)
    }
    
    return macStr
  }
  
  func readPString(at offset: Int) -> (String?, Int) {
    guard offset >= 0, offset + 1 <= self.count else {
      return (nil, 0)
    }
    let len = Int(self.readUInt8(at: offset)!)
    guard offset + 1 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+1, length: len), 1 + len)
  }
  
  func readLongPString(at offset: Int) -> (String?, Int) {
    guard offset >= 0, offset + 2 <= self.count else {
      return (nil, 0)
    }
    let len = Int(self.readUInt16(at: offset)!)
    guard len > 0 else {
      return ("", 0)
    }
    guard offset + 2 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+2, length: len), len)
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

extension String {
  func fourCharCode() -> FourCharCode {
    guard self.count == 4 else {
      return 0
    }
    
    return self.utf16.reduce(0, {$0 << 8 + FourCharCode($1)})
  }
}

extension FourCharCode {
  func fourCharCode() -> String {
    let bytes = [
      UInt8((self >> 24) & 0xFF),
      UInt8((self >> 16) & 0xFF),
      UInt8((self >> 8) & 0xFF),
      UInt8(self & 0xFF)
    ]
    return String(bytes: bytes, encoding: .ascii) ?? ""
  }
}
