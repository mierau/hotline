import Foundation
import CoreServices

enum LineEnding {
  case lf // Unix-style (\n)
  case crlf // Windows-style (\r\n)
  case cr // Classic Mac-style (\r)
}

// MARK: -

extension URL {
  func urlForResourceFork() -> URL {
    self.appendingPathComponent("..namedfork/rsrc")
  }

  /// Append multiple path components to a URL by iterating through an array
  /// - Parameter components: Array of path component strings
  /// - Returns: New URL with all components appended
  func appendingPathComponents(_ components: [String]) -> URL {
    var path = self.path
    for component in components {
      path = (path as NSString).appendingPathComponent(component)
    }
    return URL(filePath: path)
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
    "udif": "dmg",
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
  
  /// Create a file with metadata from a Hotline INFO fork
  ///
  /// - Parameters:
  ///   - url: Destination URL for the new file
  ///   - infoFork: Hotline file info containing metadata
  /// - Returns: FileHandle open for writing
  /// - Throws: Error if file creation fails
  func createHotlineFile(at url: URL, infoFork: HotlineFileInfoFork) throws -> FileHandle {
    var attributes: [FileAttributeKey: Any] = [:]

    if infoFork.creator != 0 {
      attributes[.hfsCreatorCode] = infoFork.creator as NSNumber
    }
    if infoFork.type != 0 {
      attributes[.hfsTypeCode] = infoFork.type as NSNumber
    }
    attributes[.creationDate] = infoFork.createdDate as NSDate
    attributes[.modificationDate] = infoFork.modifiedDate as NSDate

    guard self.createFile(atPath: url.path, contents: nil, attributes: attributes) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    guard let handle = FileHandle(forWritingAtPath: url.path) else {
      throw HotlineTransferClientError.failedToTransfer
    }

    return handle
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
    
    guard let fileName = fileURL.lastPathComponent.data(using: .macOSRoman, allowLossyConversion: true) else {
      return nil
    }
    
    var totalSize: UInt64 = 0
    
    // Add flat file header size.
    totalSize += UInt64(HotlineFileHeader.DataSize)
    
    // Add information fork header size.
    totalSize += UInt64(HotlineFileForkHeader.DataSize)
    
    // Add information fork size.
    totalSize += UInt64(HotlineFileInfoFork.BaseDataSize)
    totalSize += UInt64(fileName.count)
    
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

      // Count all items (files and folders)
      if isRegularFile || isDirectory {
        itemCount += 1

        // Only add size for files, not folders
        if isRegularFile, let fileSize = self.getFlattenedFileSize(fileURL) {
          totalSize += fileSize
        }
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
  init(_ val: UInt8) {
    self.init()
    self.appendUInt8(val)
  }
  
  init(_ val: UInt16) {
    self.init()
    self.appendUInt16(val)
  }
  
  init(_ val: UInt32) {
    self.init()
    self.appendUInt32(val)
  }
  
  init(_ val: UInt64) {
    self.init()
    self.appendUInt64(val)
  }
  
  mutating func consumeUInt8() -> UInt8? {
    guard let val = self.readUInt8(at: 0) else {
      return nil
    }
    
    self.removeFirst(1)
    return val
  }
  
  mutating func consumeUInt16() -> UInt16? {
    guard let val = self.readUInt16(at: 0) else {
      return nil
    }
    
    self.removeFirst(2)
    return val
  }
  
  mutating func consumeUInt32() -> UInt32? {
    guard let val = self.readUInt32(at: 0) else {
      return nil
    }
    
    self.removeFirst(4)
    return val
  }
  
  mutating func consumeUInt64() -> UInt64? {
    guard let val = self.readUInt64(at: 0) else {
      return nil
    }
    
    self.removeFirst(8)
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
    guard let val: Data = self.readData(at: 0, length: length) else {
      return nil
    }
    
    self.removeFirst(length)
    return val
  }
  
  mutating func consumeBytes(_ length: Int) -> [UInt8]? {
    guard let val: [UInt8] = self.readData(at: 0, length: length) else {
      return nil
    }
    
    self.removeFirst(length)
    return val
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
  
  func readUInt8(at offset: Int) -> UInt8? {
    guard offset >= 0, offset + 1 <= self.count else {
      return nil
    }
    return self[offset]
  }
  
  func readUInt16(at offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= self.count else {
      return nil
    }
    
    return (UInt16(self[offset]) << 8) + UInt16(self[offset + 1])
  }
  
  func readUInt32(at offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= self.count else {
      return nil
    }
    
    return (UInt32(self[offset]) << 24) + (UInt32(self[offset + 1]) << 16) + (UInt32(self[offset + 2]) << 8) + UInt32(self[offset + 3])
  }
  
  func readUInt64(at offset: Int) -> UInt64? {
    guard offset >= 0, offset + 8 <= self.count else {
      return nil
    }
    
    let a: UInt64 = (UInt64(self[offset]) << 56) +
      (UInt64(self[offset + 1]) << 48) +
      (UInt64(self[offset + 2]) << 40) +
      (UInt64(self[offset + 3]) << 32)
    
    let b: UInt64 = (UInt64(self[offset + 4]) << 24) +
      (UInt64(self[offset + 5]) << 16) +
      (UInt64(self[offset + 6]) << 8) +
       UInt64(self[offset + 7])
    
    return a + b
  }
  
  func readDate(at offset: Int) -> Date? {
    guard offset >= 0, offset + 2 + 2 + 4 <= self.count else {
      return nil
    }
    
    if
      let year = self.readUInt16(at: offset),
      let ms = self.readUInt16(at: offset + 2),
      let secs = self.readUInt32(at: offset + 2 + 2) {
      return Date(year: year, seconds: secs, milliseconds: ms)
//      return convertHotlineDate(year: year, seconds: secs, milliseconds: ms)
    }
    
    return nil
  }
  
  func readData(at offset: Int, length: Int) -> Data? {
    guard offset >= 0, offset + length <= self.count else {
      return nil
    }
    return Data(self[offset..<(offset + length)])
  }
  
  func readData(at offset: Int, length: Int) -> [UInt8]? {
    guard offset >= 0, offset + length <= self.count else {
      return nil
    }
    return Array(self[offset..<(offset + length)])
  }
  
  func readString(at offset: Int, length: Int) -> String? {
    guard let data: Data = self.readData(at: offset, length: length) else {
      return nil
    }
    
    return data.readString(at: 0, length: length)
  }
  
  func readPString(at offset: Int) -> (String?, Int) {
    guard offset >= 0, offset + 1 <= self.count else {
      return (nil, 0)
    }
    let len = Int(self.readUInt8(at: offset)!)
    guard offset + 1 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+1, length: len), 1 + len)
  }
  
  func readLongPString(at offset: Int) -> (String?, Int) {
    guard offset >= 0, offset + 2 <= self.count else {
      return (nil, 0)
    }
    let len = Int(self.readUInt16(at: offset)!)
    guard len > 0 else {
      return ("", 0)
    }
    guard offset + 2 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+2, length: len), len)
  }
  
  mutating func appendUInt8(_ value: UInt8, endianness: Endianness = .big) {
    let val = endianness == .big ? value.bigEndian : value.littleEndian
    self.append(val)
  }
  
  mutating func appendUInt16(_ value: UInt16, endianness: Endianness = .big) {
    let val = endianness == .big ? value.bigEndian : value.littleEndian
    let bytes: [UInt8] = [
      UInt8(val & 0x00FF),
      UInt8((val >> 8) & 0x00FF),
    ]
    self.append(contentsOf: bytes)
  }
  
  mutating func appendUInt32(_ value: UInt32, endianness: Endianness = .big) {
    let val = endianness == .big ? value.bigEndian : value.littleEndian
    let bytes: [UInt8] = [
      UInt8(val & 0x000000FF),
      UInt8((val >> 8) & 0x000000FF),
      UInt8((val >> 16) & 0x000000FF),
      UInt8((val >> 24) & 0x000000FF),
    ]
    self.append(contentsOf: bytes)
  }
  
  mutating func appendUInt64(_ value: UInt64, endianness: Endianness = .big) {
    let val: UInt64 = endianness == .big ? value.bigEndian : value.littleEndian
    let bytes: [UInt8] = [
      UInt8(val & 0x00000000000000FF),
      UInt8((val >> 8) & 0x00000000000000FF),
      UInt8((val >> 16) & 0x00000000000000FF),
      UInt8((val >> 24) & 0x00000000000000FF),
      UInt8((val >> 32) & 0x00000000000000FF),
      UInt8((val >> 40) & 0x00000000000000FF),
      UInt8((val >> 48) & 0x00000000000000FF),
      UInt8((val >> 56) & 0x00000000000000FF),
    ]
    self.append(contentsOf: bytes)
  }
  
  mutating func appendData(_ data: Data) {
    self.append(contentsOf: data)
  }
  
  mutating func appendData(_ data: [UInt8]) {
    self.append(contentsOf: data)
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
  
  init(_ val: UInt8) {
    self.init()
    self.appendUInt8(val)
  }
  
  init(_ val: UInt16) {
    self.init()
    self.appendUInt16(val)
  }
  
  init(_ val: UInt32) {
    self.init()
    self.appendUInt32(val)
  }
  
  func readUInt8(at offset: Int) -> UInt8? {
    guard offset >= 0, offset + 1 <= self.count else {
      return nil
    }
    return self[offset]
  }
  
  func readUInt16(at offset: Int) -> UInt16? {
    guard offset >= 0, offset + 2 <= self.count else {
      return nil
    }
    
    return (UInt16(self[offset]) << 8) + UInt16(self[offset + 1])
  }
  
  func readUInt32(at offset: Int) -> UInt32? {
    guard offset >= 0, offset + 4 <= self.count else {
      return nil
    }
    
    return (UInt32(self[offset]) << 24) + (UInt32(self[offset + 1]) << 16) + (UInt32(self[offset + 2]) << 8) + UInt32(self[offset + 3])
  }
  
  func readUInt64(at offset: Int) -> UInt64? {
    guard offset >= 0, offset + 8 <= self.count else {
      return nil
    }
    
    return withUnsafeBytes { $0.load(as: UInt64.self ) }
  }
  
  func readDate(at offset: Int) -> Date? {
    guard offset >= 0, offset + 2 + 2 + 4 <= self.count else {
      return nil
    }
    
    if
      let year = self.readUInt16(at: offset),
      let ms = self.readUInt16(at: offset + 2),
      let secs = self.readUInt32(at: offset + 2 + 2) {
      return Date(year: year, seconds: secs, milliseconds: ms)
    }
    
    return nil
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
    
    self.appendUInt16(year)
    self.appendUInt16(msecs)
    self.appendUInt32(secs)
  }
    
  func readData(at offset: Int, length: Int) -> Data? {
    guard offset >= 0, offset + length <= self.count else {
      return nil
    }
    return self.subdata(in: offset..<(offset + length))
  }

  func readString(at offset: Int, length: Int) -> String? {
    let subdata = self[offset..<(offset + length)]
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
    guard offset >= 0, offset + 1 <= self.count else {
      return (nil, 0)
    }
    let len = Int(self.readUInt8(at: offset)!)
    guard offset + 1 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+1, length: len), 1 + len)
  }
  
  func readLongPString(at offset: Int) -> (String?, Int) {
    guard offset >= 0, offset + 2 <= self.count else {
      return (nil, 0)
    }
    let len = Int(self.readUInt16(at: offset)!)
    guard len > 0 else {
      return ("", 0)
    }
    guard offset + 2 + len <= self.count else {
      return (nil, 0)
    }
    return (self.readString(at: offset+2, length: len), len)
  }
  
  
  mutating func appendUInt8(_ value: UInt8, endianness: Endianness = .big) {
    var val = endianness == .big ? value.bigEndian : value.littleEndian
    append(&val, count: MemoryLayout<UInt8>.size)
  }
  
  mutating func appendUInt16(_ value: UInt16, endianness: Endianness = .big) {
    var val = endianness == .big ? value.bigEndian : value.littleEndian
    Swift.withUnsafeBytes(of: &val) { buffer in
      append(buffer.bindMemory(to: UInt8.self))
    }
//    append(&val, count: MemoryLayout<UInt16>.size)
  }
  
  mutating func appendUInt32(_ value: UInt32, endianness: Endianness = .big) {
    var val = endianness == .big ? value.bigEndian : value.littleEndian
    Swift.withUnsafeBytes(of: &val) { buffer in
      append(buffer.bindMemory(to: UInt8.self))
    }
//    append(&val, count: MemoryLayout<UInt32>.size)
  }
  
  mutating func appendZeros(count: Int) {
    append(contentsOf: Array<UInt8>(repeating: 0, count: count))
  }
  
  mutating func appendString(_ value: String, encoding: String.Encoding) {
    guard let encodedString = value.data(using: encoding) else {
      return
    }
    
    append(encodedString)
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
