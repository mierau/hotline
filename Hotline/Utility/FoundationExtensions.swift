import Foundation
import SwiftUI

enum Endianness {
  case big
  case little
}

extension String {
  
  func convertToAttributedStringWithLinks() -> AttributedString {
    let attributedString: NSMutableAttributedString = NSMutableAttributedString(string: self)
    let matches = self.ranges(of: RegularExpressions.relaxedLink)
    for match in matches {
      let matchString = String(self[match])
      if matchString.isEmailAddress() {
        attributedString.addAttribute(.link, value: "mailto:\(matchString)", range: NSRange(match, in: self))
      }
      else {
        attributedString.addAttribute(.link, value: matchString, range: NSRange(match, in: self))
      }
//      attributedString.addAttribute(.underlineStyle, value: 1, range: NSRange(match, in: self))
    }
    return AttributedString(attributedString)
  }
  
  func isEmailAddress() -> Bool {
    self.wholeMatch(of: RegularExpressions.emailAddress) != nil
  }
  
  func isWebURL() -> Bool {
    guard let url = URL(string: self) else {
      return false
    }
    switch url.scheme?.lowercased() {
    case "http", "https":
      return true
    default:
      return false
    }
  }
  
  func isImageURL() -> Bool {
    guard let url = URL(string: self) else {
      return false
    }
    
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg", "png", "gif":
      return true
    default:
      return false
    }
  }
  
  func convertingLinksToMarkdown() -> String {
    var cp = String(self)
    cp.replace(RegularExpressions.relaxedLink) { match -> String in
      let linkText = self[match.range]
      var injectedScheme = "https://"
      if let _ = try? RegularExpressions.supportedLinkScheme.prefixMatch(in: linkText) {
        injectedScheme = ""
      }
      
      return "[\(linkText)](\(injectedScheme)\(linkText))"
    }
    return cp
  }
}



extension Binding where Value: OptionSet, Value == Value.Element {
  func bindedValue(_ options: Value) -> Bool {
    return wrappedValue.contains(options)
  }
  
  func bind(_ options: Value) -> Binding<Bool> {
    return .init { () -> Bool in
      self.wrappedValue.contains(options)
    } set: { newValue in
      if newValue {
        self.wrappedValue.insert(options)
      } else {
        self.wrappedValue.remove(options)
      }
    }
  }
}
