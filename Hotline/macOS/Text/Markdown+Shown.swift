import AppKit
import UniformTypeIdentifiers

/// Markdown as it's shown, everywhere it's read: styled as it's written, but without its marks,
/// with its links going where they go, its lists' bullets as bullets, its code blocks without their
/// ``` lines, and with the language they name above them instead, and its lines across drawn
/// across. Its drawings stay as they're drawn, in a fixed-width font, with only their addresses
/// made links. Links to files and folders on Hotline servers show as the file's icon and name,
/// long links show shorter, and links to images have a preview under the line they're on.
extension Markdown {
  /// A link to a file on a Hotline server, shown as the file's icon and name. The link itself, so
  /// copying gives the link rather than the name.
  static let fileLinkKey = NSAttributedString.Key("markdownFileLink")
  /// A long link shown shorter, as it was written, so copying gives all of it.
  static let fullLinkKey = NSAttributedString.Key("markdownFullLink")

  private static let shownTexts = NSCache<NSString, NSAttributedString>()

  /// Some text as it's shown in a place laid out as `layout` has it, worked out once for each.
  static func shown(_ text: String, layout: Layout = .board) -> NSAttributedString {
    let key = "\(layout.key)\n\(text)" as NSString
    if let shown = self.shownTexts.object(forKey: key) {
      return shown
    }
    let shown = self.shownText(text, layout: layout)
    self.shownTexts.setObject(shown, forKey: key)
    return shown
  }

  /// Some text as it's shown in a place laid out as `layout` has it, each line a paragraph of its
  /// own, worked out anew, to add to.
  static func shownText(_ text: String, layout: Layout) -> NSMutableAttributedString {
    // Classic clients end lines with \r.
    let text = text.utf16.contains(0x0D) ? text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n") : text
    let storage = NSMutableAttributedString(string: text, attributes: layout.attributes)
    let string = storage.string as NSString
    // Most text, in chat, is a few words, with nothing that could be a mark or a link.
    guard self.mightBeMoreThanWords(text) else {
      self.trimEdges(of: storage)
      return storage
    }

    let shown = Shown()
    let blocks = self.codeBlocks(in: string)
    let drawings = self.drawings(in: string, skipping: blocks.map(\.range))
    for block in blocks {
      self.showBlock(block, in: storage, layout: layout, shown: shown)
    }
    for drawing in drawings {
      self.styleDrawing(drawing, in: storage, layout: layout, shown: shown)
    }
    self.styleWords(in: storage, range: NSRange(location: 0, length: storage.length), skipping: blocks.map(\.range) + drawings, layout: layout, shown: shown)
    for link in shown.links {
      storage.addAttribute(.link, value: link.url, range: link.range)
    }
    for bullet in shown.bullets {
      storage.replaceCharacters(in: NSRange(location: bullet, length: 1), with: "•")
    }
    // Where each image's line ends, once what's hidden is gone.
    let images = shown.images.map { image in
      (lineEnd: image.lineEnd - shown.hidden.count(in: 0..<image.lineEnd), url: image.url, isImage: image.isImage)
    }
    // From the end, so what's before each one stays put.
    for range in shown.hidden.rangeView.reversed() {
      storage.deleteCharacters(in: NSRange(range))
    }
    let trimmed = self.trimEdges(of: storage)
    if layout.imagePreviews > 0 {
      self.addPreviews(of: images.map { ($0.lineEnd - trimmed, $0.url, $0.isImage) }, to: storage, layout: layout)
    }
    self.shortenLongLinks(in: storage)
    self.showFileLinks(in: storage)
    return storage
  }

  /// Whether text could be more than words: more than one line, or a line that starts as a quote,
  /// a list's item, a heading or a line across do, or something that could be a mark, or a link,
  /// an @, a scheme's ://, or a dot with something right after it, as in a domain. A dot at the end
  /// of a sentence doesn't count.
  static func mightBeMoreThanWords(_ text: String) -> Bool {
    if let first = text.utf16.first(where: { $0 != 0x20 }), "-*+>#_0123456789".utf16.contains(first) {
      return true
    }
    var afterDot = false
    for unit in text.utf16 {
      switch unit {
      // A line break, *, _, ~, `, [, \ or @.
      case 0x0A, 0x0D, 0x2A, 0x5F, 0x7E, 0x60, 0x5B, 0x5C, 0x40:
        return true
      // A letter or a number after a dot.
      case 0x30...0x39 where afterDot, 0x41...0x5A where afterDot, 0x61...0x7A where afterDot:
        return true
      default:
        break
      }
      afterDot = unit == 0x2E
    }
    return text.contains("://")
  }

  /// Nothing before the first words or after the last, as a code block with no code in it can
  /// leave. How much was taken from the start.
  @discardableResult
  private static func trimEdges(of storage: NSMutableAttributedString) -> Int {
    let string = storage.string as NSString
    var end = string.length
    while end > 0, let character = Unicode.Scalar(string.character(at: end - 1)), CharacterSet.whitespacesAndNewlines.contains(character) {
      end -= 1
    }
    var start = 0
    while start < end, string.character(at: start) == 0x0A {
      start += 1
    }
    storage.deleteCharacters(in: NSRange(location: end, length: string.length - end))
    storage.deleteCharacters(in: NSRange(location: 0, length: start))
    return start
  }

  // MARK: Previews

  /// A small preview, each on a line of its own, under the line with the link to the image, or in
  /// its place, for one written as an image with nothing else on its line, up to as many as the
  /// layout has room for, and each image once.
  private static func addPreviews(of images: [(lineEnd: Int, url: URL, isImage: Bool)], to storage: NSMutableAttributedString, layout: Layout) {
    var seen: Set<URL> = []
    var lines: [Int: [ImageAttachment]] = [:]
    for image in images where seen.count < layout.imagePreviews && !seen.contains(image.url) {
      seen.insert(image.url)
      lines[min(max(0, image.lineEnd), storage.length), default: []].append(ImageAttachment(url: image.url, standsForLink: image.isImage))
    }
    // From the end, so what's before each line stays put.
    for (at, attachments) in lines.sorted(by: { $0.key > $1.key }) {
      let string = storage.string as NSString
      let style = storage.length == 0 ? nil : storage.attribute(.paragraphStyle, at: min(at, storage.length - 1), effectiveRange: nil)
      let paragraph = style as? NSParagraphStyle ?? layout.paragraph()
      // Under what's on the line, or in its place, when nothing is.
      let alone = at == 0 || string.character(at: at - 1) == 0x0A || string.character(at: at - 1) == 0x2028
      let previews = NSMutableAttributedString()
      for (index, attachment) in attachments.enumerated() {
        if index > 0 || !alone {
          previews.append(NSAttributedString(string: "\u{2028}", attributes: [.font: layout.font, .paragraphStyle: paragraph]))
        }
        let picture = NSMutableAttributedString(attachment: attachment)
        // In a tiny font, so its line is only as tall as the preview, which is nothing until its
        // image starts to come in.
        picture.addAttributes([.paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: 1)], range: NSRange(location: 0, length: picture.length))
        previews.append(picture)
      }
      storage.insert(previews, at: at)
      // With room under them, before what comes after.
      if at < string.length {
        let paragraph = (storage.string as NSString).paragraphRange(for: NSRange(location: at, length: 0))
        storage.enumerateAttribute(.paragraphStyle, in: paragraph) { value, part, _ in
          let style = ((value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
          style.paragraphSpacing = max(style.paragraphSpacing, self.previewSpacing)
          storage.addAttribute(.paragraphStyle, value: style, range: part)
        }
      }
    }
  }

  /// The room under previews, before the line after them.
  private static let previewSpacing: CGFloat = 6

  // MARK: Long Links

  /// How long a link can be before most of what's after its ? is hidden.
  private static let longLinkLength = 80
  /// The longest a long link's first parameter can be and still show, like YouTube's v=…, which
  /// says which video.
  private static let shownParameterLength = 24

  /// Web links longer than `longLinkLength` with parameters, shown as they're written, without
  /// them.
  static func shortenLongLinks(in text: NSMutableAttributedString) {
    var long: [(range: NSRange, shown: String, written: String)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
      guard range.length > self.longLinkLength, let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
        return
      }
      let written = (text.string as NSString).substring(with: range)
      // Only an address shown as it's written, not words a link was given.
      guard !written.contains(" "), let host = url.host()?.lowercased(), written.lowercased().contains(host),
            let shown = self.shortLink(written) else {
        return
      }
      long.append((range, shown, written))
    }
    // From the end, so earlier ranges stay put.
    for link in long.reversed() {
      var attributes = text.attributes(at: link.range.location, effectiveRange: nil)
      attributes[self.fullLinkKey] = link.written
      text.replaceCharacters(in: link.range, with: NSAttributedString(string: link.shown, attributes: attributes))
    }
  }

  /// A link shown up to its ? or #, with its first parameter if that's short, then …. Nil if
  /// there's nothing after that to hide.
  static func shortLink(_ link: String) -> String? {
    guard let cut = link.firstIndex(where: { $0 == "?" || $0 == "#" }) else {
      return nil
    }
    var shown = String(link[..<cut])
    if link[cut] == "?" {
      let parameters = link[link.index(after: cut)...]
      let first = parameters.prefix { $0 != "&" && $0 != "#" }
      if !first.isEmpty, first.count <= self.shownParameterLength {
        guard first.endIndex < parameters.endIndex else {
          return nil
        }
        shown += "?" + first
      }
    }
    return shown + "\u{2026}"
  }

  // MARK: Links to Files

  /// The name of the file or folder a hotline:// link points to, like
  /// hotline://server/files/Folder/File.zip, or nil if it isn't a link to one. A link that ends in
  /// a slash is to a folder.
  static func fileName(ofHotlineLink url: URL) -> String? {
    guard url.scheme?.lowercased() == "hotline" else {
      return nil
    }
    let path = url.pathComponents.filter { $0 != "/" }
    guard path.count >= 2, path[0] == "files", let name = path.last, !name.isEmpty else {
      return nil
    }
    return name
  }

  /// Links to files and folders on Hotline servers, shown as the icon and name the Files list shows
  /// rather than the link. A link with words of its own keeps them, with the icon before them.
  static func showFileLinks(in text: NSMutableAttributedString) {
    var links: [(range: NSRange, url: URL, name: String)] = []
    text.enumerateAttribute(.link, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      let url = (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
      if let url, let name = self.fileName(ofHotlineLink: url) {
        links.append((range, url, name))
      }
    }

    // From the end, so earlier ranges stay put.
    for link in links.reversed() {
      var attributes = text.attributes(at: link.range.location, effectiveRange: nil)
      attributes[self.fileLinkKey] = link.url
      let shown = (text.string as NSString).substring(with: link.range)
      let isBareLink = shown.lowercased().hasPrefix("hotline://")
      let file = NSMutableAttributedString(string: isBareLink ? link.name : shown, attributes: attributes)

      let attachment = NSTextAttachment()
      attachment.image = link.url.hasDirectoryPath ? self.folderIcon : self.fileIcon(forName: link.name)
      attachment.bounds = CGRect(x: 0, y: -3, width: 16 + self.fileIconGap, height: 16)
      let icon = NSMutableAttributedString(attachment: attachment)
      icon.addAttributes(attributes, range: NSRange(location: 0, length: icon.length))
      file.insert(icon, at: 0)
      text.replaceCharacters(in: link.range, with: file)
    }
  }

  /// The space between a file's icon and its name. It's part of the icon, since TextKit 2 doesn't
  /// kern attachments.
  private static let fileIconGap: CGFloat = 4

  /// The small folder the Files list shows.
  static let folderIcon = spaced(NSImage(named: "Folder") ?? NSWorkspace.shared.icon(for: .folder))

  /// Kept for each kind of file, by its extension. A cache, as text can be shown off the main
  /// thread.
  private static let fileIcons = NSCache<NSString, NSImage>()

  /// A file's icon from its name, as the Files browser shows it, 16 pt.
  private static func fileIcon(forName name: String) -> NSImage {
    let fileExtension = (name as NSString).pathExtension.lowercased()
    if let icon = self.fileIcons.object(forKey: fileExtension as NSString) {
      return icon
    }
    let type = fileExtension.isEmpty ? nil : UTType(filenameExtension: fileExtension)
    let icon = self.spaced(NSWorkspace.shared.icon(for: type ?? .data))
    self.fileIcons.setObject(icon, forKey: fileExtension as NSString)
    return icon
  }

  /// A 16 pt icon with the gap after it.
  private static func spaced(_ icon: NSImage) -> NSImage {
    NSImage(size: NSSize(width: 16 + self.fileIconGap, height: 16), flipped: false) { _ in
      icon.draw(in: NSRect(x: 0, y: 0, width: 16, height: 16))
      return true
    }
  }

  // MARK: Reading Back

  /// The links some text shows, outside its code, where nothing is a link.
  static func links(in text: String) -> [URL] {
    let shown = self.shownText(text, layout: Layout(imagePreviews: 0))
    var links: [URL] = []
    shown.enumerateAttribute(.link, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
      if let url = (value as? URL) ?? (value as? String).flatMap({ URL(string: $0) }) {
        links.append(url)
      }
    }
    return links
  }

  /// Shown text as plain text, as it's copied: with real line breaks, links to files as their
  /// links, rather than their names, long links as they were written, and images written as images
  /// as where they are, but nothing for icons and the previews of links that are there anyway.
  static func plainText(_ text: NSAttributedString) -> String {
    var plain = ""
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
      if let url = attributes[self.fileLinkKey] as? URL {
        // Once for all of the link, at its icon.
        if range.location == 0 || text.attribute(self.fileLinkKey, at: range.location - 1, effectiveRange: nil) as? URL != url {
          plain += url.absoluteString
        }
        return
      }
      if let written = attributes[self.fullLinkKey] as? String {
        if range.location == 0 || text.attribute(self.fullLinkKey, at: range.location - 1, effectiveRange: nil) as? String != written {
          plain += written
        }
        return
      }
      if let image = attributes[.attachment] as? ImageAttachment {
        plain += image.standsForLink ? image.url.absoluteString : ""
        return
      }
      plain += (text.string as NSString).substring(with: range)
    }
    return plain
      .replacingOccurrences(of: "\u{FFFC}", with: "")
      .replacingOccurrences(of: "\u{2028}", with: "\n")
  }
}
