import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension FileManager {
  @discardableResult
  func moveToDownloads(from sourceURL: URL, using filename: String, bounceDock: Bool = false) -> Bool {
    let filePath = URL.downloadsDirectory.generateUniqueFilePath(filename: filename)
    let destinationURL = URL(filePath: filePath).resolvingSymlinksInPath()
    
    do {
      try FileManager.default.moveItem(at: sourceURL.resolvingSymlinksInPath(), to: destinationURL)
    }
    catch {
      return false
    }
    
    if bounceDock {
      #if os(macOS)
      DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: destinationURL.path)
      #endif
    }
    
    return true
  }
  
  @discardableResult
  func copyToDownloads(from sourceURL: URL, using filename: String, bounceDock: Bool = false) -> Bool {
    let filePath = URL.downloadsDirectory.generateUniqueFilePath(filename: filename)
    let destinationURL = URL(filePath: filePath).resolvingSymlinksInPath()
    
    do {
      try FileManager.default.copyItem(at: sourceURL.resolvingSymlinksInPath(), to: destinationURL)
    }
    catch {
      return false
    }
    
    if bounceDock {
      #if os(macOS)
      DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: destinationURL.path)
      #endif
    }
    
    return true
  }
}

// MARK: -

extension View {
  @ViewBuilder
  func applyNavigationDocumentIfPresent(_ url: URL?) -> some View {
    if let url {
      self.navigationDocument(url)
    } else {
      self
    }
  }
}

// MARK: -

extension Data {
  func saveAsFileToDownloads(filename: String, bounceDock: Bool = true) -> Bool {
    let filePath = URL.downloadsDirectory.generateUniqueFilePath(filename: filename)
    
    if FileManager.default.createFile(atPath: filePath, contents: self) {
      if bounceDock {
        #if os(macOS)
        var downloadURL = URL(filePath: filePath)
        downloadURL.resolveSymlinksInPath()
        DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: downloadURL.path)
        #endif
      }
      return true
    
//    if FileManager.default.createFile(atPath: filePath, contents: nil) {
//      if let h = FileHandle(forWritingAtPath: filePath) {
//        try? h.write(contentsOf: self)
//        try? h.close()
//        
//      }
    }
    return false
  }
  
  enum ImageFormat {
    case gif
    case jpeg
    case png
    case webp
    case unknown
  }
  
  var detectedImageFormat: ImageFormat {
    guard self.count >= 12 else { return .unknown }
    
    let bytes = [UInt8](self.prefix(12))
    
    // GIF: "GIF8"
    if bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x38 {
      return .gif
    }
    
    // JPEG: FF D8 FF
    if bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
      return .jpeg
    }
    
    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A && bytes[7] == 0x0A {
      return .png
    }
    
    // WebP: "RIFF" at 0-3 and "WEBP" at 8-11
    if bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
      return .webp
    }
    
    return .unknown
  }
}

// MARK: -

extension URL {
  func generateUniqueFilePath(filename base: String) -> String {
    let fileManager = FileManager.default
    var finalName = base
    var counter = 2
    
    // Helper function to generate a new filename with a counter
    func makeFileName() -> String {
      let baseName = (base as NSString).deletingPathExtension
      let extensionName = (base as NSString).pathExtension
      return extensionName.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(extensionName)"
    }
    
    // Check if file exists and append counter until a unique name is found
    var filePath = self.appending(component: finalName).path(percentEncoded: false)
    while fileManager.fileExists(atPath: filePath) {
      finalName = makeFileName()
      filePath = self.appending(component: finalName).path(percentEncoded: false)
      counter += 1
    }
    
    return filePath
  }
  
  func generateUniqueFileURL(filename base: String) -> URL {
    let filePath = self.generateUniqueFilePath(filename: base)
    return URL(filePath: filePath)
  }
}

// MARK: -

extension UTType {
  var canBePreviewedByQuickLook: Bool {
    // QuickLook supports most common document types
    let supportedSupertypes: [UTType] = [
      .image,
      .movie,
      .audio,
      .pdf,
      .font,
      .usdz,
      .text,
      .sourceCode,
      .spreadsheet,
      .presentation,
      
//       Microsoft Office
      .init(filenameExtension: "doc")!,
      .init(filenameExtension: "docx")!,
      .init(filenameExtension: "xls")!,
      .init(filenameExtension: "xlsx")!,
      .init(filenameExtension: "ppt")!,
      .init(filenameExtension: "pptx")!,
    ]
    
    return supportedSupertypes.contains { self.conforms(to: $0) }
  }
}

// MARK: -

extension String {
  
  var isBlank: Bool {
    self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
  
  func markdownToAttributedString() -> AttributedString {
    let markdownText = self.convertingLinksToMarkdown()
    let attr = (try? AttributedString(markdown: markdownText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(self)
    
    return attr
  }
  
  func convertToAttributedStringWithLinks() -> AttributedString {
    let attributedString: NSMutableAttributedString = NSMutableAttributedString(string: self)
    for link in self.detectedLinks() {
      attributedString.addAttribute(.link, value: link.url.absoluteString, range: NSRange(link.range, in: self))
    }
    return AttributedString(attributedString)
  }

  /// The links in the text, found the way the rest of macOS finds them, as in Messages: web
  /// addresses with or without http, email addresses, and hotline:// links. Links of other kinds,
  /// like file://, aren't included, since they'd act on this Mac rather than open a page.
  ///
  /// A server's address and port written without a scheme, like hotline.example.org:5500 or
  /// 192.168.1.5:5500, links to the Hotline server, which in Hotline chat it nearly always is.
  func detectedLinks() -> [(range: Range<String.Index>, url: URL)] {
    guard let detector = String.linkDetector else {
      return []
    }
    let text = self as NSString
    var links: [(range: Range<String.Index>, url: URL)] = []
    let matches = detector.matches(in: self, range: NSRange(location: 0, length: text.length))
    for (index, match) in matches.enumerated() {
      guard var url = match.url, let scheme = url.scheme?.lowercased(), String.linkSchemes.contains(scheme) else {
        continue
      }
      var range = match.range
      // Data detectors give up partway through a link with a long unbroken stretch in it, like the
      // token on a signed address, and stop at the last place they were sure of. Carry on to where
      // it really ends, short of the next link.
      let limit = index + 1 < matches.count ? matches[index + 1].range.location : text.length
      if let whole = String.wholeLink(cutShort: range, in: text, limit: limit),
         let wholeURL = URL(string: text.substring(with: whole)),
         wholeURL.scheme?.lowercased() == scheme {
        range = whole
        url = wholeURL
      }
      // A link at the end of something in parentheses can take the closing one with it.
      let found = text.substring(with: range)
      if found.hasSuffix(")"), found.filter({ $0 == ")" }).count > found.filter({ $0 == "(" }).count {
        range.length -= 1
        let address = url.absoluteString
        if address.hasSuffix(")"), let trimmed = URL(string: String(address.dropLast())) {
          url = trimmed
        }
      }
      if !found.contains("://"), scheme != "mailto", let host = url.host(), let port = url.port,
         url.path.isEmpty || url.path == "/", let server = URL(string: "hotline://\(host):\(port)") {
        url = server
      }
      if let stringRange = Range(range, in: self) {
        links.append((stringRange, url))
      }
    }

    // IP addresses and ports, which data detectors don't find.
    for match in self.matches(of: RegularExpressions.serverAddress) {
      let address = self[match.range]
      let octets = address.split(separator: ":")[0].split(separator: ".").compactMap { Int($0) }
      guard octets.count == 4, octets.allSatisfy({ $0 <= 255 }),
            !links.contains(where: { $0.range.overlaps(match.range) }),
            let url = URL(string: "hotline://\(address)") else {
        continue
      }
      links.append((match.range, url))
    }
    return links.sorted { $0.range.lowerBound < $1.range.lowerBound }
  }

  /// Text with Markdown's special characters escaped, so a link's text shows as it was written,
  /// rather than *these* becoming italics.
  private static func escapingMarkdown(_ text: Substring) -> String {
    var escaped = ""
    for character in text {
      if "\\`*_{}[]<>()#+!|~".contains(character) {
        escaped.append("\\")
      }
      escaped.append(character)
    }
    return escaped
  }

  private static let linkDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

  /// The characters an address can have in it.
  private static let addressCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~:/?#[]@!$&'()*+,;=%")
  /// What can end a sentence or a bit of formatting rather than an address.
  private static let trailingPunctuation = CharacterSet(charactersIn: ".,;:!?'\"*_~`")

  /// A link written with its scheme that a data detector stopped short of the end of, as far as
  /// its address goes, up to a space or anything else that can't be in one, but not past `limit`,
  /// and leaving off punctuation at the end. Nil if it didn't stop short.
  private static func wholeLink(cutShort range: NSRange, in text: NSString, limit: Int) -> NSRange? {
    guard text.substring(with: range).contains("://") else {
      return nil
    }
    var end = NSMaxRange(range)
    while end < limit, let character = Unicode.Scalar(text.character(at: end)), self.addressCharacters.contains(character) {
      end += 1
    }
    while end > NSMaxRange(range), let character = Unicode.Scalar(text.character(at: end - 1)), self.trailingPunctuation.contains(character) {
      end -= 1
    }
    return end > NSMaxRange(range) ? NSRange(location: range.location, length: end - range.location) : nil
  }
  /// The schemes a link can have, which open a page, a server, or an email, and not anything on this Mac.
  static let linkSchemes: Set<String> = ["http", "https", "hotline", "mailto"]

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
    // Except in links already written in Markdown, whose text and address would otherwise become
    // links of their own inside it.
    let markdownLinks = self.ranges(of: RegularExpressions.markdownLink)
    let links = self.detectedLinks().filter { link in !markdownLinks.contains { $0.overlaps(link.range) } }

    // Build result by interleaving original text with markdown links
    var result = ""
    var currentIndex = self.startIndex
    for link in links {
      result += self[currentIndex..<link.range.lowerBound]
      result += "[\(String.escapingMarkdown(self[link.range]))](\(link.url.absoluteString))"
      currentIndex = link.range.upperBound
    }
    result += self[currentIndex..<self.endIndex]
    return result
  }
}

// MARK: -

#if os(macOS)
extension String {
  func toNSAttributedStringWithMarkdownAndLinks(
    baseFont: NSFont,
    linkColor: NSColor,
    paragraphStyle: NSParagraphStyle? = nil
  ) -> NSAttributedString {
    let markdownText = self.convertingLinksToMarkdown()

    let result: NSMutableAttributedString
    if let parsed = try? NSAttributedString(
      markdown: markdownText,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    ) {
      result = NSMutableAttributedString(attributedString: parsed)
    } else {
      result = NSMutableAttributedString(string: self)
    }

    let fullRange = NSRange(location: 0, length: result.length)

    // Set default text color for all text
    result.addAttribute(.foregroundColor, value: NSColor.textColor, range: fullRange)

    // Preserve bold/italic traits from markdown while applying base font
    result.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
      var traits: NSFontDescriptor.SymbolicTraits = []
      if let existingFont = value as? NSFont {
        traits = existingFont.fontDescriptor.symbolicTraits
      }
      let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
      let font = NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
      result.addAttribute(.font, value: font, range: range)
    }

    // Apply link color
    result.enumerateAttribute(.link, in: fullRange, options: []) { value, range, _ in
      if value != nil {
        result.addAttribute(.foregroundColor, value: linkColor, range: range)
      }
    }

    // Apply paragraph style
    if let style = paragraphStyle {
      result.addAttribute(.paragraphStyle, value: style, range: fullRange)
    }

    return result
  }
}
#endif

// MARK: -

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

// MARK: -

extension Color {
  init(hex: Int, opacity: Double = 1.0) {
    self.init(red: Double((hex >> 16) & 0xFF) / 255.0, green: Double((hex >> 8) & 0xFF) / 255.0, blue: Double(hex & 0xFF) / 255.0, opacity: opacity)
  }
}

// MARK: - Glass Button Styles

#if os(macOS)
extension View {
  @ViewBuilder
  func glassButtonStyle() -> some View {
    if #available(macOS 26, *) {
      self.buttonStyle(.glass)
    } else {
      self
    }
  }

  @ViewBuilder
  func glassProminentButtonStyle() -> some View {
    if #available(macOS 26, *) {
      self.buttonStyle(.glassProminent)
    } else {
      self.buttonStyle(.borderedProminent)
    }
  }

  @ViewBuilder
  func bottomBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    if #available(macOS 26, *) {
      self.safeAreaBar(edge: .bottom, content: content)
    } else {
      self.safeAreaInset(edge: .bottom, spacing: 0, content: content)
    }
  }
}
#endif
