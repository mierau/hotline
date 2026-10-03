import AppKit
import UniformTypeIdentifiers

/// PICT pictures, which macOS no longer draws properly, decoded and drawn by QuickDrawViewer's
/// renderer (in QuickDrawViewer/).
enum PICTImage {
  static let contentType = UTType("com.apple.pict")!

  /// Whether a file is a PICT, by its extension (.pict, .pct or .pic) or its HFS type code.
  static func isPICT(name: String, hfsType: String?) -> Bool {
    if hfsType == "PICT" {
      return true
    }
    let fileExtension = (name as NSString).pathExtension
    return UTType(filenameExtension: fileExtension) == self.contentType
  }

  /// The picture in a PICT file, drawn as PDF so it stays sharp at any size. Nil if the file
  /// isn't a picture QuickDrawViewer can read.
  static func pdfData(fromFileAt url: URL) -> Data? {
    guard let data = try? Data(contentsOf: url),
          let pictData = self.withStandardHeader(data),
          let parser = try? QDParser(data: pictData),
          let picture = try? parser.parse() else {
      return nil
    }
    let pdf = picture.pdfData() as Data
    return pdf.isEmpty ? nil : pdf
  }

  /// An image of the PDF on white, which is what pictures were drawn on. Parts a picture doesn't
  /// paint are transparent in the PDF, and would vanish against a dark window.
  static func image(fromPDF pdf: Data) -> NSImage? {
    guard let picture = NSImage(data: pdf) else {
      return nil
    }
    return NSImage(size: picture.size, flipped: false) { rect in
      NSColor.white.setFill()
      rect.fill()
      picture.draw(in: rect)
      return true
    }
  }

  /// The picture with the standard 512-byte header in front, which is what QDParser expects.
  /// Most PICT files have exactly that, but some have a few extra header bytes and pictures taken
  /// from resources have none, so look for the version opcode every picture starts with.
  private static func withStandardHeader(_ data: Data) -> Data? {
    let bytes = [UInt8](data.prefix(600))

    func isPicture(at offset: Int) -> Bool {
      // After the 2-byte size and 8-byte frame: 0x0011 0x02FF for version 2, 0x11 0x01 for version 1.
      guard offset + 14 <= bytes.count else {
        return false
      }
      let version2 = bytes[offset + 10] == 0x00 && bytes[offset + 11] == 0x11 && bytes[offset + 12] == 0x02 && bytes[offset + 13] == 0xFF
      let version1 = bytes[offset + 10] == 0x11 && bytes[offset + 11] == 0x01
      return version2 || version1
    }

    guard let offset = (Array(512..<528) + Array(0..<16)).first(where: isPicture) else {
      return nil
    }

    var standard = Data(count: 512)
    standard.append(data.subdata(in: (data.startIndex + offset)..<data.endIndex))
    return standard
  }
}
