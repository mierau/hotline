import Foundation

/// The list of what's in a XAR archive, as an installer package is, which comes first, after a
/// short header, as compressed XML.
enum XARArchive {
  /// What's in an archive `size` long, read through `read`, which gives the `length` bytes of it
  /// from `offset`.
  static func entries(size: Int, read: (_ offset: Int, _ length: Int) async throws -> Data) async throws -> [ArchiveEntry] {
    // "xar!", the header's length, a version, and how long the list is, compressed.
    let header = Data(try await read(0, min(size, 28)))
    guard header.count == 28, header.hasSignature(Array("xar!".utf8), at: 0),
          let headerLength = header.bigEndian(UInt16.self, at: 4).map(Int.init), headerLength >= 28,
          let listLength = header.bigEndian(UInt64.self, at: 8).map({ Int(clamping: $0) }), listLength > 6,
          headerLength + listLength <= size else {
      throw ArchiveReadError.notAnArchive
    }

    // In zlib's wrapping: two bytes before it, and a check of four after.
    let list = Data(try await read(headerLength, listLength))
    guard list.count == listLength,
          let xml = try? (list.subdata(in: 2..<(list.count - 4)) as NSData).decompressed(using: .zlib) as Data else {
      throw ArchiveReadError.notAnArchive
    }
    let parser = XMLParser(data: xml)
    let contents = TableOfContents()
    parser.delegate = contents
    guard parser.parse() else {
      throw ArchiveReadError.notAnArchive
    }
    return contents.entries
  }

  /// The files in the XML list, each a <file> with a <name>, a <type>, and a <data> with the
  /// <size> it is out of the archive, and inside a folder, the <file>s in it.
  private final class TableOfContents: NSObject, XMLParserDelegate {
    private struct File {
      var name = ""
      var type = ""
      var size: UInt64 = 0
      let folder: Int?
    }

    private var files: [File] = []
    /// The <file>s inside one another the parser's in, innermost last.
    private var openFiles: [Int] = []
    private var elements: [String] = []
    private var text = ""

    var entries: [ArchiveEntry] {
      self.files.indices.compactMap { index in
        let file = self.files[index]
        guard !file.name.isEmpty else {
          return nil
        }
        var path = file.name
        var folder = file.folder
        while let index = folder {
          path = "\(self.files[index].name)/\(path)"
          folder = self.files[index].folder
        }
        let isFolder = file.type == "directory"
        return ArchiveEntry(path: path, isFolder: isFolder, size: isFolder ? 0 : file.size)
      }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
      if elementName == "file" {
        self.files.append(File(folder: self.openFiles.last))
        self.openFiles.append(self.files.count - 1)
      }
      self.elements.append(elementName)
      self.text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
      self.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
      self.elements.removeLast()
      // Only the file's own name, type and size, not those of things it has, like extended
      // attributes, which have them too.
      let parent = self.elements.last
      let grandparent = self.elements.dropLast().last
      if let file = self.openFiles.last {
        switch elementName {
        case "name" where parent == "file":
          self.files[file].name = self.text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: ":")
        case "type" where parent == "file":
          self.files[file].type = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "size" where parent == "data" && grandparent == "file":
          self.files[file].size = UInt64(self.text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        case "file":
          self.openFiles.removeLast()
        default:
          break
        }
      }
      self.text = ""
    }
  }
}
