import Foundation
import UniformTypeIdentifiers
import SwiftUI

struct TextFile: FileDocument {
  // tell the system we support only plain text
  static var readableContentTypes = [UTType.plainText, UTType.utf8PlainText]
  
  // by default our document is empty
  var text = ""
  
  // a simple initializer that creates new, empty documents
  init(initialText: String = "") {
    text = initialText
  }
  
  // this initializer loads data that has been saved previously
  init(configuration: ReadConfiguration) throws {
    
    if let data = configuration.file.regularFileContents {
      if let str = String(data: data, encoding: .utf8) {
        self.text = str
      }
    }
  }
  
  // this will be called when the system wants to write our data to disk
  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    return FileWrapper(regularFileWithContents: self.text.data(using: .utf8)!)
  }
}
