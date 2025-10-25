import SwiftUI
import Foundation

extension Color {
  init(hex: Int, opacity: Double = 1.0) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255.0, green: Double((hex >> 8) & 0xFF) / 255.0, blue: Double(hex & 0xFF) / 255.0, opacity: opacity)
  }
}

extension AttributedString {
  func setHangingIndent(firstLineHeadIndent: CGFloat = 0, otherLinesHeadIndent: CGFloat) -> AttributedString {
//    var blah = self
    
//    guard var paragraph = self.paragraphStyle else {
//      return
//    }
    
    var p = self.paragraphStyle?.mutableCopy() as? NSMutableParagraphStyle
    p?.headIndent = otherLinesHeadIndent
    p?.firstLineHeadIndent = firstLineHeadIndent
    
//    paragraph.headIndent = otherLinesHeadIndent          // indent for lines 2+
//    paragraph.firstLineHeadIndent = firstLineHeadIndent  // usually 0
    
    var blah = self
    
    
    blah.paragraphStyle = p
    
    return blah
  }
}

