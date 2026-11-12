import Foundation
import CoreServices
import NetSocket

enum LineEnding {
  case lf // Unix-style (\n)
  case crlf // Windows-style (\r\n)
  case cr // Classic Mac-style (\r)
}

// MARK: -

extension String {
  /// A name from a server or a link as the name of one file or folder on disk, so it can only ever
  /// name something in the folder it's put in: a "/" in it as the ":" the Finder shows as "/",
  /// without NUL characters, and "Untitled" for a name that's empty, "." or "..".
  var safeFileName: String {
    let name = self.replacingOccurrences(of: "/", with: ":").replacingOccurrences(of: "\0", with: "")
    return name.isEmpty || name == "." || name == ".." ? "Untitled" : name
  }

  /// The name with a number, the way the Finder names a copy: "Name 2.ext" for 2.
  func numberedFileName(_ number: Int) -> String {
    let base = (self as NSString).deletingPathExtension
    let pathExtension = (self as NSString).pathExtension
    return pathExtension.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(pathExtension)"
  }
}

// MARK: -

extension URL {
  func urlForResourceFork() -> URL {
    self.appendingPathComponent("..namedfork/rsrc")
  }

  /// A path of names from a server below this folder, each as one name, so the path can't lead
  /// out of it, as a ".." or a "/" in a name would.
  func appendingPathComponents(_ components: [String]) -> URL {
    components.reduce(self) { $0.appending(component: $1.safeFileName) }
  }
  
#if os(macOS)
  func notifyDownloadFinished() {
    print("DOWNLOAD FINISHED AT", self)
    DistributedNotificationCenter.default().post(name: .init("com.apple.DownloadFileFinished"), object: self.path)
  }
#endif
}

// MARK: -

public struct TaskTimeoutError: Error {}

extension Task where Success == Never, Failure == Never {
  public static func withTimeout<T>(seconds: TimeInterval, operation: @escaping @Sendable () async throws -> T) async throws -> T {
    if seconds <= 0 {
      throw TaskTimeoutError()
    }

    return try await withThrowingTaskGroup(of: T.self) { group in
      group.addTask {
        try await operation()
      }

      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        throw TaskTimeoutError()
      }

      do {
        let value = try await group.next()!
        group.cancelAll()
        return value
      } catch {
        group.cancelAll()
        throw error
      }
    }
  }
}

// MARK: -

extension String {
  func convertingLineEndings(to targetEnding: LineEnding) -> String {
    let lf = "\n"
    let crlf = "\r\n"
    let cr = "\r"
    
    // Normalize all line endings to LF (\n)
    let normalizedString = self.replacing(cr, with: lf).replacing(crlf, with: lf)
    
    // Replace normalized LF (\n) line endings with the target line ending
    switch targetEnding {
    case .lf:
      return normalizedString
    case .crlf:
      return normalizedString.replacing(lf, with: crlf)
    case .cr:
      return normalizedString.replacing(lf, with: cr)
    }
  }
  
  func replyToString() -> String {
    if self.range(of: "^Re:", options: [.regularExpression, .caseInsensitive]) != nil {
      return String(self)
    }
    return "Re: \(self)"
  }
  
  func fourCharCode() -> FourCharCode {
    guard self.count == 4 else {
      return 0
    }
    
    return self.utf16.reduce(0, {$0 << 8 + FourCharCode($1)})
  }
}

// MARK: -

extension FileManager {
  static var extensionToHFSCreator: [String: UInt32] = [
    // Documents
    "txt": "ttxt".fourCharCode(),
    "rtf": "MSWD".fourCharCode(),
    "doc": "MSWD".fourCharCode(),
    "qxd": "XPR3".fourCharCode(),
    "indd": "InDn".fourCharCode(),
    "idd": "InDn".fourCharCode(),
    
    // Spreadsheets
    "csv": "ttxt".fourCharCode(),
    "xls": "XCEL".fourCharCode(),
    "xlsx": "XCEL".fourCharCode(),
    "numbers": "NMBR".fourCharCode(),
    
    // Presentations
    "ppt": "PPT3".fourCharCode(),
    "key": "KEYN".fourCharCode(),
    
    // Images
    "ai": "ART5".fourCharCode(),
    "jpg": "8BIM".fourCharCode(),
    "jpeg": "8BIM".fourCharCode(),
    "png": "8BIM".fourCharCode(),
    "gif": "8BIM".fourCharCode(),
    "tiff": "8BIM".fourCharCode(),
    "ico": "8BIM".fourCharCode(),
    "bmp": "8BIM".fourCharCode(),
    "eps": "8BIM".fourCharCode(),
    "ps": "8BIM".fourCharCode(),
    "psd": "8BIM".fourCharCode(),
    "pict": "8BIM".fourCharCode(),
    "tga": "8BIM".fourCharCode(),
    
    // Archives
    "zip": "SITx".fourCharCode(),
    "sit": "SITx".fourCharCode(),
    "dmg": "ddsk".fourCharCode(),
    "sea": "SITx".fourCharCode(),
    
    // Programming
    "swift": "R*ch".fourCharCode(),
    "java": "R*ch".fourCharCode(),
    "py": "R*ch".fourCharCode(),
    "c": "R*ch".fourCharCode(),
    "cpp": "R*ch".fourCharCode(),
    "cp": "R*ch".fourCharCode(),
    "h": "R*ch".fourCharCode(),
    "js": "R*ch".fourCharCode(),
    "html": "sfri".fourCharCode(),
    "css": "sfri".fourCharCode(),
    "php": "R*ch".fourCharCode(),
    "json": "R*ch".fourCharCode(),
    "md": "R*ch".fourCharCode(),
    "log": "R*ch".fourCharCode(),
    "xml": "R*ch".fourCharCode(),
  ]
  
  static var HFSTypeToExtension: [String: String] = [
    // Documents
    "text": "txt",
    "rtf ": "rtf",
    "wdbn": "doc",
    "w8bn": "docx",
    "wprd": "prd",
    "wp5 ": "wpd",
    "pdf ": "pdf",
    "xdoc": "qxd",
    "indd": "ind",
    
    // Spreadsheets
    "xls ": "xls",
    "xlsx": "xlsx",
    "nmbr": "numbers",
    
    // Presentations
    "ppt3": "ppt",
    "keyn": "key",
    
    // Images
    "jpeg": "jpg",
    "pngf": "png",
    "giff": "gif",
    "tiff": "tiff",
    "ico ": "ico",
    "bmpf": "bmp",
    "epsf": "eps",
    "8bps": "psd",
    "pict": "pict",
    "tpic": "tga",
    "swfl": "swf",
    
    // Audio
    "mp3 ": "mp3",
    "m4a ": "m4a",
    "caff": "aac",
    "wave": "wav",
    "aiff": "aiff",
    "midi": "midi",
    "snd ": "snd",
    
    // Video
    "m4v ": "mp4",
    "mpg ": "mpeg",
    "mpg2": "mpg2",
    "moov": "mov",
    "vfw ": "avi",
    "wmv ": "wmv",
    
    // Archives
    "zip ": "zip",
    "rar ": "rar",
    "7zip": "7z",
    "tar ": "tar",
    "gzip": "gz",
    "sitx": "sit",
    "sit!": "sit",
    "sit5": "sit",
    "pact": "cpt",
    "udif": "dmg",
    "dimg": "img",
    "cdrw": "cdr",
    
    // Fonts
    "tfil": "ttf",
  ]
  
  static var extensionToHFSType: [String: UInt32] = [
    // Documents
    "txt": "TEXT".fourCharCode(),
    "rtf": "RTF ".fourCharCode(),
    "doc": "WDBN".fourCharCode(),
    "docx": "W8BN".fourCharCode(),
    "prd": "WPRD".fourCharCode(),
    "wpd": "WP5 ".fourCharCode(),
    "pdf": "PDF ".fourCharCode(),
    "qxd": "XDOC".fourCharCode(),
    "indd": "inDd".fourCharCode(),
    "idd": "inDd".fourCharCode(),
    
    // Spreadsheets
    "csv": "TEXT".fourCharCode(),
    "xls": "XLS ".fourCharCode(),
    "xlsx": "XLSX".fourCharCode(),
    "numbers": "NMBR".fourCharCode(),
    
    // Presentations
    "ppt": "PPT3".fourCharCode(),
    "key": "KEYN".fourCharCode(),
    
    // Images
    "jpg": "JPEG".fourCharCode(),
    "jpeg": "JPEG".fourCharCode(),
    "png": "PNGf".fourCharCode(),
    "gif": "GIFf".fourCharCode(),
    "tiff": "TIFF".fourCharCode(),
    "ico": "ICO ".fourCharCode(),
    "bmp": "BMPf".fourCharCode(),
    "eps": "EPSF".fourCharCode(),
    "ps": "EPSF".fourCharCode(),
    "psd": "8BPS".fourCharCode(),
    "pict": "PICT".fourCharCode(),
    "tga": "TPIC".fourCharCode(),
    "swf": "SWFL".fourCharCode(),
    
    // Audio
    "mp3": "Mp3 ".fourCharCode(),
    "m4a": "M4A ".fourCharCode(),
    "aac": "caff".fourCharCode(),
    "wav": "WAVE".fourCharCode(),
    "aiff": "AIFF".fourCharCode(),
    "midi": "Midi".fourCharCode(),
    "snd": "snd ".fourCharCode(),
    
    // Video
    "mp4": "M4V ".fourCharCode(),
    "mpeg": "MPG ".fourCharCode(),
    "mpg2": "MPG2".fourCharCode(),
    "mov": "MooV".fourCharCode(),
    "avi": "VfW ".fourCharCode(),
    "wmv": "WMV ".fourCharCode(),
    
    // Archives
    "zip": "ZIP ".fourCharCode(),
    "rar": "RAR ".fourCharCode(),
    "7z": "7ZIP".fourCharCode(),
    "tar": "TAR ".fourCharCode(),
    "gz": "GZIP".fourCharCode(),
    "sit": "SITx".fourCharCode(),
    "dmg": "udif".fourCharCode(),
    "sea": "SITx".fourCharCode(),
    "cdr": "CDRW".fourCharCode(),
    
    // Programming
    "swift": "TEXT".fourCharCode(),
    "java": "TEXT".fourCharCode(),
    "py": "TEXT".fourCharCode(),
    "c": "TEXT".fourCharCode(),
    "cpp": "TEXT".fourCharCode(),
    "cp": "TEXT".fourCharCode(),
    "h": "TEXT".fourCharCode(),
    "js": "TEXT".fourCharCode(),
    "html": "TEXT".fourCharCode(),
    "css": "TEXT".fourCharCode(),
    "php": "TEXT".fourCharCode(),
    "json": "TEXT".fourCharCode(),
    "md": "TEXT".fourCharCode(),
    "log": "TEXT".fourCharCode(),
    "xml": "TEXT".fourCharCode(),
    
    // Fonts
    "ttf": "tfil".fourCharCode(),
  ]
  
  func getHFSTypeAndCreator(_ fileURL: URL) throws -> (hfsCreator: UInt32, hfsType: UInt32) {
    let filePath = fileURL.path(percentEncoded: false)
    let fileAttributes: [FileAttributeKey: Any] = try self.attributesOfItem(atPath: filePath)
    let fileExtension = fileURL.pathExtension.lowercased()
    
    var creator: UInt32 = "????".fourCharCode()
    if let creatorCode: NSNumber = fileAttributes[.hfsCreatorCode] as? NSNumber,
       creatorCode.uint32Value != 0 {
      creator = creatorCode.uint32Value
    }
    if creator == "????".fourCharCode() {
      if let possibleCreator = FileManager.extensionToHFSCreator[fileExtension] {
        creator = possibleCreator
      }
    }
    
    var type: UInt32 = "????".fourCharCode()
    if let typeCode: NSNumber = fileAttributes[.hfsTypeCode] as? NSNumber,
       typeCode.uint32Value != 0 {
      type = typeCode.uint32Value
    }
    if type == "????".fourCharCode() {
      if let possibleType = FileManager.extensionToHFSType[fileExtension] {
        type = possibleType
      }
    }
    
    return (hfsCreator: creator, hfsType: type)
  }
  
  func getFinderComment(_ fileURL: URL) throws -> String {
    let filePath = fileURL.path(percentEncoded: false)
    let fileAttributes: [FileAttributeKey: Any] = try self.attributesOfItem(atPath: filePath)
    
    if let extendedAttributesData = fileAttributes[FileAttributeKey(rawValue: "NSFileExtendedAttributes")],
       let extendedAttributes = extendedAttributesData as? [FileAttributeKey: Any] {
      print(extendedAttributes)
      
      if let commentPlistDataAttribute = extendedAttributes[FileAttributeKey(rawValue: "com.apple.metadata:kMDItemFinderComment")],
         let commentPlistData = commentPlistDataAttribute as? Data {
        if let plist = try? PropertyListSerialization.propertyList(from: commentPlistData, options: [], format: nil),
           let plistString = plist as? String {
          return plistString
        }
      }
    }
    
    return ""
  }
  
  func getCreatedAndModifiedDates(_ fileURL: URL) -> (createdDate: Date, modifiedDate: Date) {
    let filePath = fileURL.path(percentEncoded: false)
    
    guard let fileAttributes: [FileAttributeKey: Any] = try? self.attributesOfItem(atPath: filePath),
          let createdNSDate: NSDate = fileAttributes[.creationDate] as? NSDate,
          let modifiedNSDate: NSDate = fileAttributes[.modificationDate] as? NSDate else {
      return (createdDate: Date(), modifiedDate: Date())
    }
    
    print("GOT CREATED DATE: ", createdNSDate)
    
    return (createdDate: createdNSDate as Date, modifiedDate: modifiedNSDate as Date)
  }
  
  func setExtendedFileAttribute(_ fileURL: URL, name: String, value: Data) throws {
    try fileURL.withUnsafeFileSystemRepresentation { fileSystemPath in
      let result = value.withUnsafeBytes { [count = value.count] in
        setxattr(fileSystemPath, name, $0.baseAddress, count, 0, 0)
      }
      
      guard result >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
    }
  }
  
  func removeExtendedFileAttribute(_ fileURL: URL, name: String) throws {
    try fileURL.withUnsafeFileSystemRepresentation { fileSystemPath in
      let result = removexattr(fileSystemPath, name, 0)
      guard result >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
    }
  }
  
  func getExtendedFileAttribute(_ fileURL: URL, name: String) throws -> Data {
    let data = try fileURL.withUnsafeFileSystemRepresentation { fileSystemPath in
      let length = getxattr(fileSystemPath, name, nil, 0, 0, 0)
      guard length >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
      
      var data = Data(count: length)
      if length == 0 {
        return data
      }
      
      let result = data.withUnsafeMutableBytes { [count = data.count] in
        getxattr(fileSystemPath, name, $0.baseAddress, count, 0, 0)
      }
      guard result >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]) }
      
      return data
    }
    
    return data
  }
  
  func getFileForkSizes(_ fileURL: URL) throws -> (dataForkSize: UInt32, resourceForkSize: UInt32) {
    let filePath = fileURL.path(percentEncoded: false)
    guard self.fileExists(atPath: filePath) else {
      throw CocoaError(.fileNoSuchFile)
    }
    
    // Get data fork size.
    var dataForkSize: UInt32 = 0
    let dataFileAttributes: [FileAttributeKey: Any]? = try? self.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
    if let dataNSSizeAttribute: NSNumber = dataFileAttributes?[FileAttributeKey.size] as? NSNumber {
      dataForkSize = UInt32(dataNSSizeAttribute.int64Value)
    }
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    
    // Get resource fork size.
    var resourceForkSize: UInt32 = 0
    let resourceFileURL: URL = fileURL.urlForResourceFork()
    let resourceFilePath: String = fileURL.path(percentEncoded: false)
    if self.fileExists(atPath: resourceFilePath) {
      let resourceFileAttributes: [FileAttributeKey: Any]? = try? self.attributesOfItem(atPath: resourceFileURL.path(percentEncoded: false))
      if let resourceNSSizeAttribute: NSNumber = resourceFileAttributes?[FileAttributeKey.size] as? NSNumber {
        resourceForkSize = UInt32(resourceNSSizeAttribute.int64Value)
      }
    }
    
    return (dataForkSize: dataForkSize, resourceForkSize: resourceForkSize)
  }
  
  /// Makes a new file for a download, with the type and creator codes and dates from its info fork,
  /// at `url`, or at the first free name like it. See `createNewFile(at:attributes:)`.
  ///
  /// - Returns: Where it was made, and a handle open for writing it.
  func createHotlineFile(at url: URL, infoFork: HotlineFileInfoFork) throws -> (url: URL, handle: FileHandle) {
    var attributes: [FileAttributeKey: Any] = [:]

    if infoFork.creator != 0 {
      attributes[.hfsCreatorCode] = infoFork.creator as NSNumber
    }
    if infoFork.type != 0 {
      attributes[.hfsTypeCode] = infoFork.type as NSNumber
    }
    attributes[.creationDate] = infoFork.createdDate as NSDate
    attributes[.modificationDate] = infoFork.modifiedDate as NSDate

    return try self.createNewFile(at: url, attributes: attributes)
  }

  /// Makes a new, empty file at `url`, or, when something's there already, at the first free name
  /// like it, numbered the way the Finder numbers copies. What's there is never replaced, and a link
  /// there is never followed.
  ///
  /// - Returns: Where it was made, and a handle open for writing it.
  func createNewFile(at url: URL, attributes: [FileAttributeKey: Any] = [:]) throws -> (url: URL, handle: FileHandle) {
    var candidate = url
    var number = 1
    while true {
      let path = candidate.path(percentEncoded: false)
      // Only if nothing's there, a link included.
      let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
      if descriptor >= 0 {
        if !attributes.isEmpty {
          try? self.setAttributes(attributes, ofItemAtPath: path)
        }
        return (candidate, FileHandle(fileDescriptor: descriptor, closeOnDealloc: true))
      }
      let failure = errno
      number += 1
      guard failure == EEXIST, number <= 10_000 else {
        throw POSIXError(POSIXErrorCode(rawValue: failure) ?? .EIO)
      }
      candidate = url.deletingLastPathComponent().appending(component: url.lastPathComponent.numberedFileName(number))
    }
  }

  /// Makes a new folder at `url`, or, when something's there already, at the first free name like
  /// it, numbered the way the Finder numbers copies. What's there is never replaced.
  ///
  /// - Returns: Where it was made.
  func createNewFolder(at url: URL) throws -> URL {
    try self.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var candidate = url
    var number = 1
    while true {
      do {
        try self.createDirectory(at: candidate, withIntermediateDirectories: false)
        return candidate
      }
      catch {
        let taken = (error as? CocoaError)?.code == .fileWriteFileExists
          || self.fileExists(atPath: candidate.path(percentEncoded: false))
        number += 1
        guard taken, number <= 10_000 else {
          throw error
        }
        candidate = url.deletingLastPathComponent().appending(component: url.lastPathComponent.numberedFileName(number))
      }
    }
  }

  /// Open an existing file's resource fork for writing, creating the fork if needed.
  ///
  /// `FileHandle(forWritingTo:)` can't be used here because the fork doesn't exist until it's created.
  ///
  /// - Parameter url: The file whose resource fork to open
  /// - Returns: FileHandle open for writing; the caller must close it
  /// - Throws: `POSIXError` if the fork can't be opened (e.g., the volume doesn't support resource forks)
  func openResourceForkForWriting(at url: URL) throws -> FileHandle {
    let path = url.resolvingSymlinksInPath().urlForResourceFork().path(percentEncoded: false)
    let fd = Darwin.open(path, O_WRONLY | O_CREAT, 0o644)
    guard fd >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
  }

  func getFlattenedFileSize(_ fileURL: URL) -> UInt64? {
    var fileIsDirectory: ObjCBool = false
    let filePath: String = fileURL.path(percentEncoded: false)
    
    guard fileURL.isFileURL,
          self.fileExists(atPath: filePath, isDirectory: &fileIsDirectory),
          fileIsDirectory.boolValue == false else {
      return nil
    }
    
    // The information fork as it's sent: with its name, and its comment, and the comment's length,
    // which servers that read exactly as much as they're told need counted too.
    guard let infoFork = HotlineFileInfoFork(file: fileURL)?.data() else {
      return nil
    }
    
    var totalSize: UInt64 = 0
    
    // Add flat file header size.
    totalSize += UInt64(HotlineFileHeader.DataSize)
    
    // Add information fork header size.
    totalSize += UInt64(HotlineFileForkHeader.DataSize)
    
    // Add information fork size.
    totalSize += UInt64(infoFork.count)
    
    // Add file fork sizes.
    if let forkSizes = try? self.getFileForkSizes(fileURL) {
      // Add data fork size.
      totalSize += UInt64(HotlineFileForkHeader.DataSize)
      totalSize += UInt64(forkSizes.dataForkSize)
      
      // Add resource fork size.
      if forkSizes.resourceForkSize > 0 {
        totalSize += UInt64(HotlineFileForkHeader.DataSize)
        totalSize += UInt64(forkSizes.resourceForkSize)
      }
    }
    
    
    // Add data fork size.
//    var dataSize: UInt64 = 0
//    let dataFileAttributes: [FileAttributeKey: Any]? = try? self.attributesOfItem(atPath: fileURL.path(percentEncoded: false))
//    if let dataSizeAttribute: UInt64 = dataFileAttributes?[FileAttributeKey.size] as? UInt64 {
//      dataSize = UInt64(dataSizeAttribute)
//    }
//    
//    totalSize += dataSize
//    
//    // Add resource fork size.
//    var resourceForkSize: UInt64 = 0
//    let resourceFileURL: URL = fileURL.appendingPathComponent("..namedfork/rsrc")
//    let resourceFilePath: String = fileURL.path(percentEncoded: false)
//    if self.fileExists(atPath: resourceFilePath) {
//      let resourceFileAttributes: [FileAttributeKey: Any]? = try? self.attributesOfItem(atPath: resourceFileURL.path(percentEncoded: false))
//      if let resourceSizeAttribute: UInt64 = resourceFileAttributes?[FileAttributeKey.size] as? UInt64 {
//        resourceForkSize = UInt64(resourceSizeAttribute)
//        print("FOUND RESOURCE FORK: \(resourceForkSize)")
//      }
//    }
//
//    totalSize += resourceForkSize

    return totalSize
  }

  /// Get the total size of all files in a folder (recursively)
  /// Returns the sum of flattened file sizes for all files in the folder, and the total count of all items (files + folders)
  func getFolderSize(_ folderURL: URL) -> (size: UInt64, count: UInt32)? {
    var isDirectory: ObjCBool = false
    let folderPath = folderURL.path(percentEncoded: false)

    guard folderURL.isFileURL,
          self.fileExists(atPath: folderPath, isDirectory: &isDirectory),
          isDirectory.boolValue == true else {
      return nil
    }

    var totalSize: UInt64 = 0
    var itemCount: UInt32 = 0

    guard let enumerator = self.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
      return nil
    }

    for case let fileURL as URL in enumerator {
      guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey]) else {
        continue
      }

      let isRegularFile = resourceValues.isRegularFile ?? false
      let isDirectory = resourceValues.isDirectory ?? false

      // As many as a folder upload sends, as the server takes exactly as many as it's told: folders,
      // and files that can be read, but not links, which aren't followed.
      if isDirectory {
        itemCount += 1
      }
      else if isRegularFile, let fileSize = self.getFlattenedFileSize(fileURL) {
        itemCount += 1
        totalSize += fileSize
      }
    }

    return (size: totalSize, count: itemCount)
  }
}

extension Date {
  init?(year: UInt16, seconds: UInt32, milliseconds: UInt16) {
    var components = DateComponents()
    components.timeZone = .gmt
    components.year = Int(year)
    components.month = 1
    components.day = 1
    components.second = 0
    
    guard let baseDate = Calendar.current.date(from: components) else {
      return nil
    }
    
    self = baseDate.advanced(by: TimeInterval(seconds))
  }
  
  func hotlineDateComponents() -> (year: UInt16, seconds: UInt32, milliseconds: UInt16)? {
    let epochTime = self.timeIntervalSince1970
    let gmtDate = Date(timeIntervalSince1970: epochTime)
    
    let calendar = Calendar.current
    var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: gmtDate)
    components.month = 1
    components.day = 1
    components.hour = 0
    components.minute = 0
    components.second = 0
    components.nanosecond = 0
    
    guard let startOfYear = calendar.date(from: components),
          let year = components.year else {
      return nil
    }
    
    return (year: UInt16(year), seconds: UInt32(gmtDate.timeIntervalSince(startOfYear)), milliseconds: UInt16(0))
  }
}

extension Array where Element == UInt8 {
  /// An integer's bytes in the given order.
  init<T: FixedWidthInteger>(_ value: T, endian: Endian) {
    self.init()
    self.append(value, endian: endian)
  }

  /// Read a big-endian integer from the start, removing its bytes, or nil if there aren't enough.
  mutating func consume<T: FixedWidthInteger>(_ type: T.Type) -> T? {
    guard let val = self.read(T.self, at: 0) else {
      return nil
    }

    self.removeFirst(MemoryLayout<T>.size)
    return val
  }

  mutating func consume(_ length: Int) -> Bool {
    guard length <= self.count else {
      return false
    }
    
    self.removeFirst(length)
    return true
  }
  
  mutating func consumeBytes(_ length: Int) -> Data? {
    guard let val = self.read(length, at: 0) else {
      return nil
    }
    
    self.removeFirst(length)
    return val
  }
  
  mutating func consumeBytes(_ length: Int) -> [UInt8]? {
    guard let val = self.read(length, at: 0) else {
      return nil
    }
    
    self.removeFirst(length)
    return [UInt8](val)
  }
  
  mutating func consumeDate() -> Date? {
    guard let date = self.readDate(at: 0) else {
      return nil
    }
    
    self.removeFirst(2 + 2 + 4)
    return date
  }
  
  mutating func consumePString() -> String? {
    let (str, len) = self.readPString(at: 0)
    guard let str = str else {
      return nil
    }
    if len == 0 {
      return ""
    }
    
    self.removeFirst(len)
    return str
  }
  
  mutating func consumeLongPString() -> String? {
    let (str, len) = self.readLongPString(at: 0)
    guard let str = str else {
      return nil
    }
    if len == 0 {
      return ""
    }
    
    self.removeFirst(len)
    return str
  }
  
  mutating func consumeString(_ length: Int) -> String? {
    guard let val = self.readString(at: 0, length: length) else {
      return nil
    }
    
    self.removeFirst(length)
    return val
  }
  
  func readDate(at offset: Int) -> Date? {
    guard
      let year = self.read(UInt16.self, at: offset),
      let ms = self.read(UInt16.self, at: offset + 2),
      let secs = self.read(UInt32.self, at: offset + 2 + 2) else {
      return nil
    }
    
    return Date(year: year, seconds: secs, milliseconds: ms)
  }
  
  func readString(at offset: Int, length: Int) -> String? {
    guard let data = self.read(length, at: offset) else {
      return nil
    }
    
    return data.readString(at: 0, length: length)
  }
  
  func readPString(at offset: Int) -> (String?, Int) {
    guard let length = self.read(UInt8.self, at: offset) else {
      return (nil, 0)
    }
    let len = Int(length)
    guard offset + 1 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+1, length: len), 1 + len)
  }
  
  func readLongPString(at offset: Int) -> (String?, Int) {
    guard let length = self.read(UInt16.self, at: offset) else {
      return (nil, 0)
    }
    let len = Int(length)
    guard len > 0 else {
      return ("", 0)
    }
    guard offset + 2 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+2, length: len), len)
  }
  
  mutating func hotlineEncrypt() {
    for i in (0..<self.count).reversed() {
      self[i] = 0xFF - self[i]
    }
  }
  
  func hotlineEncrypted() -> [UInt8] {
    var cpy = [UInt8](self)
    
    
    
    for i in (0..<cpy.count).reversed() {
      cpy[i] = 0xFF - cpy[i]
    }
    return cpy
  }
}

extension Data {
  func hexDump() -> String {
    return self.map { String(format: "%02x", $0) }.joined(separator: " ")
  }
  
  func readDate(at offset: Int) -> Date? {
    guard
      let year = self.read(UInt16.self, at: offset),
      let ms = self.read(UInt16.self, at: offset + 2),
      let secs = self.read(UInt32.self, at: offset + 2 + 2) else {
      return nil
    }
    
    return Date(year: year, seconds: secs, milliseconds: ms)
  }
  
  mutating func appendDate(_ date: Date) {
    var year: UInt16 = 0
    var msecs: UInt16 = 0
    var secs: UInt32 = 0
    
    if let components = date.hotlineDateComponents() {
      year = components.year
      secs = components.seconds
      msecs = components.milliseconds
    }
    
    self.append(year, endian: .big)
    self.append(msecs, endian: .big)
    self.append(secs, endian: .big)
  }

  func readString(at offset: Int, length: Int) -> String? {
    guard let subdata = self.read(length, at: offset) else {
      return nil
    }
    if subdata.count == 0 {
      return ""
    }

    // Try UTF-8 first (modern clients, strict all-or-nothing).
    if let str = String(data: subdata, encoding: .utf8) {
      return str
    }

    // Try Shift-JIS (Japanese Hotline clients). Only accept the result
    // if a significant portion of characters are CJK (hiragana, katakana,
    // kanji) to avoid false positives from Mac OS Roman accented characters
    // (0x80-0x9F) which overlap with Shift-JIS lead bytes and can form
    // accidental CJK characters when paired with the following byte.
    if let str = String(data: subdata, encoding: .shiftJIS) {
      let cjkCount = str.unicodeScalars.count(where: { $0.value >= 0x3000 && $0.value <= 0x9FFF })
      let totalCount = str.unicodeScalars.count
      if cjkCount > 0, totalCount > 0, Double(cjkCount) / Double(totalCount) >= 0.25 {
        return str
      }
    }

    // Mac OS Roman fallback (classic Mac Hotline clients).
    // Accepts all 256 byte values so it always succeeds.
    return String(data: subdata, encoding: .macOSRoman)
  }
  
  func readPString(at offset: Int) -> (String?, Int) {
    guard let length = self.read(UInt8.self, at: offset) else {
      return (nil, 0)
    }
    let len = Int(length)
    guard offset + 1 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+1, length: len), 1 + len)
  }
  
  func readLongPString(at offset: Int) -> (String?, Int) {
    guard let length = self.read(UInt16.self, at: offset) else {
      return (nil, 0)
    }
    let len = Int(length)
    guard len > 0 else {
      return ("", 0)
    }
    guard offset + 2 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+2, length: len), len)
  }
  
  mutating func appendZeros(count: Int) {
    append(contentsOf: Array<UInt8>(repeating: 0, count: count))
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


extension NetSocket {
  /// Read a pascal string (1-byte length prefix followed by string data)
  ///
  /// This method reads a single byte for the length, then reads that many bytes and attempts
  /// to decode them as a string. It tries multiple encodings for compatibility with legacy
  /// protocols like Hotline: UTF-8, Shift-JIS, Windows-1251, and falls back to MacRoman.
  ///
  /// - Returns: The decoded string, or nil if length is 0
  /// - Throws: `NetSocketError` if reading fails or no encoding succeeds
  func readPascalString() async throws -> String? {
    let length = try await read(UInt8.self)
    guard length > 0 else { return nil }

    let dataLength = Int(length)
    let data = try await read(dataLength)
    
    return data.readString(at: 0, length: dataLength)

    // Try auto-detection with common encodings
//    let allowedEncodings = [
//      String.Encoding.utf8.rawValue,
//      String.Encoding.shiftJIS.rawValue,
//      String.Encoding.unicode.rawValue,
//      String.Encoding.windowsCP1251.rawValue
//    ]
//
//    var decodedString: NSString?
//    let detected = NSString.stringEncoding(
//      for: data,
//      encodingOptions: [.allowLossyKey: false],
//      convertedString: &decodedString,
//      usedLossyConversion: nil
//    )
//
//    if allowedEncodings.contains(detected), let str = decodedString as? String {
//      return str
//    }
//
//    // Fallback to MacRoman for classic Mac compatibility
//    guard let str = String(data: data, encoding: .macOSRoman) else {
//      throw NetSocketError.decodeFailed(NSError(
//        domain: "NetSocket",
//        code: -1,
//        userInfo: [NSLocalizedDescriptionKey: "Failed to decode pascal string with any known encoding"]
//      ))
//    }
//    return str
  }
}
