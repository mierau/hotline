import Foundation

enum DataEndianness {
  case big
  case little
}

@resultBuilder
struct DataBuilder {
  static var defaultEndian: DataEndianness = .little
  
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
    
    year = DataBuilder.defaultEndian == .big ? year.bigEndian : year.littleEndian
    secs = DataBuilder.defaultEndian == .big ? secs.bigEndian : secs.littleEndian
    msecs = DataBuilder.defaultEndian == .big ? msecs.bigEndian : msecs.littleEndian
    
    withUnsafeBytes(of: year) { dateData.append(Data($0)) }
    withUnsafeBytes(of: msecs) { dateData.append(Data($0)) }
    withUnsafeBytes(of: secs) { dateData.append(Data($0)) }
    
    return dateData
  }
  
  static func buildExpression(_ expression: Int) -> Data {
    print("ADDING BYTE:", expression)
    return withUnsafeBytes(of: UInt8(expression)) { Data($0) }
  }
  
  static func buildExpression<T: FixedWidthInteger>(_ expression: (T, DataEndianness)) -> Data {
    print("ADDING INTEGER:", expression)
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
}

extension Data {
  init(endian: DataEndianness = .little, @DataBuilder _ content: () -> Data) {
    DataBuilder.defaultEndian = endian
    self = content()
  }
}
