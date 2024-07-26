import Foundation

enum DataEndianness {
  case big
  case little
  
  static let system: DataEndianness = {
    let number: UInt32 = 0x12345678
    return number == number.littleEndian ? .little : .big
  }()
}

@resultBuilder
struct DataBuilder {
  static var defaultEndian: DataEndianness = .system
  
  static func buildBlock(_ components: Data...) -> Data {
    components.reduce(Data(), +)
  }
  
  static func buildExpression(_ expression: Data) -> Data {
    expression
  }
  
  static func buildExpression(_ expression: String) -> Data {
    Data(expression.utf8)
  }
  
  static func buildExpression(_ expression: (String, String.Encoding)) -> Data {
    expression.0.data(using: expression.1) ?? Data()
  }
  
  static func buildExpression(_ expression: [UInt8]) -> Data {
    Data(expression)
  }
  
  static func buildExpression(_ expression: Date) -> Data {
    var dateData = Data()
    
    var year: UInt16 = 0
    var msecs: UInt16 = 0
    var secs: UInt32 = 0
    
    if let components = expression.hotlineDateComponents() {
      year = components.year
      secs = components.seconds
      msecs = components.milliseconds
    }
    
    year = DataBuilder.defaultEndian == .little ? year.littleEndian : year.bigEndian
    secs = DataBuilder.defaultEndian == .little ? secs.littleEndian : secs.bigEndian
    msecs = DataBuilder.defaultEndian == .little ? msecs.littleEndian : msecs.bigEndian
    
    dateData.append(withUnsafeBytes(of: year) { Data($0) })
    dateData.append(withUnsafeBytes(of: msecs) { Data($0) })
    dateData.append(withUnsafeBytes(of: secs) { Data($0) })
    
    return dateData
  }
  
  static func buildExpression<T: FixedWidthInteger>(_ expression: (T, DataEndianness)) -> Data {
    let value = expression.1 == .little ? expression.0.littleEndian : expression.0.bigEndian
    return withUnsafeBytes(of: value) { Data($0) }
  }
  
  static func buildExpression<T: FixedWidthInteger>(_ expression: T) -> Data {
    buildExpression((expression, DataBuilder.defaultEndian))
  }
  
  // Support for if statements
  static func buildEither(first component: Data) -> Data {
    component
  }
  
  static func buildEither(second component: Data) -> Data {
    component
  }
  
  // Support for optionals
  static func buildOptional(_ component: Data?) -> Data {
    component ?? Data()
  }
  
  static func buildFinalResult(_ component: Data) -> Data {
    var data = Data()
    data.append(component)
    return data
  }
}

extension Data {
  init(endian: DataEndianness = .system, @DataBuilder _ content: () -> Data) {
    DataBuilder.defaultEndian = endian
    self = content()
  }
}
