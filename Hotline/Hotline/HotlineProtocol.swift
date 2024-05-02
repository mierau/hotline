import Foundation

struct HotlinePorts {
  static let DefaultServerPort: Int = 5500
  static let DefaultTrackerPort: Int = 5498
}

struct HotlineUserOptions: OptionSet {
  let rawValue: UInt16
  
  static let none: HotlineUserOptions = []
  
  static let refusePrivateMessages = HotlineUserOptions(rawValue: 1 << 0)
  static let refusePrivateChat = HotlineUserOptions(rawValue: 1 << 1)
  static let automaticResponse = HotlineUserOptions(rawValue: 1 << 2)
}

struct HotlineUserAccessOptions: OptionSet {
  let rawValue: UInt64
  
  static func accessIndexToBit(_ index: Int) -> Int {
    return 63 - index
  }
  
  static func printAccessOptions(_ val: HotlineUserAccessOptions) {
    func formatBinaryString(_ binaryString: String) -> String {
        var formattedString = ""
        for (index, char) in binaryString.reversed().enumerated() {
            if index % 8 == 0 && index != 0 {
                formattedString.append("_")
            }
            formattedString.append(char)
        }
        return String(formattedString.reversed())
    }

    var formattedBits = String(val.rawValue, radix: 2)
    if formattedBits.count < 64 {
      formattedBits = String(repeating: "0", count: 64 - formattedBits.count) + formattedBits
    }
    formattedBits = formatBinaryString(formattedBits)
    
    print("Access Options for \(formattedBits):")
    print("")
    print("File System Maintenance")
    print("Can download files: \(val.contains(.canDownloadFiles))")
    print("Can download folders: \(val.contains(.canDownloadFolders))")
    print("Can upload files: \(val.contains(.canUploadFiles))")
    print("Can upload folders: \(val.contains(.canUploadFolders))")
    print("Can upload anywhere: \(val.contains(.canUploadAnywhere))")
    print("Can delete files: \(val.contains(.canDeleteFiles))")
    print("Can rename files: \(val.contains(.canRenameFiles))")
    print("Can move files: \(val.contains(.canMoveFiles))")
    print("Can comment files: \(val.contains(.canSetFileComment))")
    print("Can create folders: \(val.contains(.canCreateFolders))")
    print("Can delete folders: \(val.contains(.canDeleteFolders))")
    print("Can rename folders: \(val.contains(.canRenameFolders))")
    print("Can move folders: \(val.contains(.canMoveFolders))")
    print("Can comment folders: \(val.contains(.canSetFolderComment))")
    print("Can view dropboxes: \(val.contains(.canViewDropBoxes))")
    print("Can make aliases: \(val.contains(.canMakeAliases))")
    
    print("")
    print("User Maintenance")
    print("Can create accounts: \(val.contains(.canCreateUsers))")
    print("Can delete accounts: \(val.contains(.canDeleteUsers))")
    print("Can read accounts: \(val.contains(.canOpenUsers))")
    print("Can modify accounts: \(val.contains(.canModifyUsers))")
    print("Can get user info: \(val.contains(.canGetClientInfo))")
    print("Can disconnect users: \(val.contains(.canDisconnectUsers))")
    print("Cannot be disconnected: \(val.contains(.cantBeDisconnected))")
    
    print("")
    print("Messaging")
    print("Can send private messages: \(val.contains(.canSendPrivateMessages))")
    print("Can broadcast: \(val.contains(.canBroadcast))")
    
    print("")
    print("News")
    print("Can read message board: \(val.contains(.canReadMessageBoard))")
    print("Can post message board: \(val.contains(.canPostMessageBoard))")
    print("Can delete news articles: \(val.contains(.canDeleteNewsArticles))")
    print("Can create news categories: \(val.contains(.canCreateNewsCategories))")
    print("Can delete news categories: \(val.contains(.canDeleteNewsCategories))")
    print("Can create news bundles: \(val.contains(.canCreateNewsFolders))")
    print("Can delete news bundles: \(val.contains(.canDeleteNewsFolders))")
    
    print("")
    print("Chat")
    print("Can initiate private chat: \(val.contains(.canCreateChat))")
    print("Can read chat: \(val.contains(.canReadChat))")
    print("Can send chat: \(val.contains(.canSendChat))")
    
    print("")
    print("Miscellaneous")
    print("Can use any name: \(val.contains(.canUseAnyName))")
    print("Don't show agreement: \(val.contains(.canSkipAgreement))")
    print("Can change own password: \(val.contains(.canChangeOwnPassword))")
    
    print("Can close chat: \(val.contains(.canCloseChat))")
    print("Can shown in list: \(val.contains(.canShownInList))")
    print("")
  }
  
  static let canDeleteFiles = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(0))
  static let canUploadFiles = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(1))
  static let canDownloadFiles = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(2))
  static let canRenameFiles = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(3))
  static let canMoveFiles = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(4))
  static let canCreateFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(5))
  static let canDeleteFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(6))
  static let canRenameFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(7))
  
  static let canMoveFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(8))
  static let canReadChat = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(9))
  static let canSendChat = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(10))
  static let canCreateChat = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(11))
  static let canCloseChat = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(12))
  static let canShownInList = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(13))
  static let canCreateUsers = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(14))
  static let canDeleteUsers = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(15))
  
  static let canOpenUsers = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(16))
  static let canModifyUsers = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(17))
  static let canChangeOwnPassword = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(18))
  static let canSendPrivateMessages = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(19))
  static let canReadMessageBoard = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(20))
  static let canPostMessageBoard = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(21))
  static let canDisconnectUsers = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(22))
  static let cantBeDisconnected = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(23))
  
  static let canGetClientInfo = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(24))
  static let canUploadAnywhere = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(25))
  static let canUseAnyName = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(26))
  static let canSkipAgreement = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(27))
  static let canSetFileComment = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(28))
  static let canSetFolderComment = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(29))
  static let canViewDropBoxes = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(30))
  static let canMakeAliases = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(31))
  
  static let canBroadcast = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(32))
  static let canDeleteNewsArticles = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(33))
  static let canCreateNewsCategories = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(34))
  static let canDeleteNewsCategories = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(35))
  static let canCreateNewsFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(36))
  static let canDeleteNewsFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(37))
  static let canUploadFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(38))
  static let canDownloadFolders = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(39))
  static let canSendMessages = HotlineUserAccessOptions(rawValue: 1 << HotlineUserAccessOptions.accessIndexToBit(40))
}

struct HotlineServer: Identifiable, Hashable {
  let id = UUID()
  let address: String
  let port: UInt16
  let users: UInt16
  let name: String?
  let description: String?
  
  static func == (lhs: HotlineServer, rhs: HotlineServer) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}

struct HotlineNewsArticle: Identifiable {
  let id: UInt32
  let parentID: UInt32
  let flags: UInt32
  let title: String
  let username: String
  let date: Date?
  var flavors: [(String, UInt16)] = []
  var path: [String] = []
  
  static func == (lhs: HotlineNewsArticle, rhs: HotlineNewsArticle) -> Bool {
    return lhs.id == rhs.id
  }
}

struct HotlineNewsList: Identifiable {
  let id: UInt32
  let name: String
  let description: String
  let count: UInt32
  var path: [String] = []
  
  var articles: [HotlineNewsArticle] = []
  
  init(from data: [UInt8]) {
    self.id = data.readUInt32(at: 0)!
    
    self.count = data.readUInt32(at: 4)!
    
    let (n, nl) = data.readPString(at: 8)
    self.name = n!
    
    let (d, dl) = data.readPString(at: 8 + nl)
    self.description = d!
    
    var baseIndex = Int(8 + nl + dl)
    
    for _ in 0..<Int(self.count) {
      let articleID = data.readUInt32(at: baseIndex)!
      baseIndex += 4
      
      let date = data.readDate(at: baseIndex)!
//      let timestampData = data.readData(at: baseIndex, length: 8)!
      baseIndex += 8
      
      let parentID = data.readUInt32(at: baseIndex)!
      baseIndex += 4
      
      let flags = data.readUInt32(at: baseIndex)!
      baseIndex += 4
      
      let flavorCount = data.readUInt16(at: baseIndex)!
      baseIndex += 2
      
      let titleLength = data.readUInt8(at: baseIndex)!
      baseIndex += 1
      
      let title = data.readString(at: baseIndex, length: Int(titleLength))!
      baseIndex += Int(titleLength)
      
      let posterLength = data.readUInt8(at: baseIndex)!
      baseIndex += 1
      
      let poster = data.readString(at: baseIndex, length: Int(posterLength))!
      baseIndex += Int(posterLength)
      
      // Parse date info
//      let yearData = timestampData.readUInt16(at: 0)!
//      let millisecondData = timestampData.readUInt16(at: 2)!
//      let secondsData = timestampData.readUInt32(at: 4)!
//      let articleData = convertHotlineDate(year: yearData, seconds: secondsData, milliseconds: millisecondData)
      var newArticle = HotlineNewsArticle(id: articleID, parentID: parentID, flags: flags, title: title, username: poster, date: date)
      
      print("ARTICLE ID: \(articleID)")
      print("PARENT ID: \(parentID)")
      print("FLAGS: \(flags)")
      print("FLAVOR COUNT: \(flavorCount)")
      print("TITLE: \(title)")
      print("POSTER: \(poster)")
      
      if flavorCount > 1 {
        print("MORE THAN ONE FLAVOR!!")
      }
      
      for _ in 0..<Int(flavorCount) {
        let flavorLength = data.readUInt8(at: baseIndex)!
        baseIndex += 1
        
        let flavorText = data.readString(at: baseIndex, length: Int(flavorLength))!
        baseIndex += Int(flavorLength)
        
        let articleSize = data.readUInt16(at: baseIndex)!
        baseIndex += 2
        
        newArticle.flavors.append((flavorText, articleSize))
        
//        let articleString = data.readString(at: baseIndex + i + 4 + 8 + 4 + 4 + 2 + 1 + Int(titleLength) + 1 + Int(posterLength) + 1 + Int(flavorLength) + 2, length: Int(articleSize))!
        
        print("FLAVOR: \(flavorText)")
        print("ARTICLE SIZE: \(articleSize)")
//        print("ARTICLE: \(articleString)")
      }
      
      self.articles.append(newArticle)
    }
  }
}

struct HotlineNewsCategory: Identifiable, Hashable {
  let id = UUID()
  let type: UInt16
  let count: UInt16
  let name: String
  var path: [String] = []
  
  static func == (lhs: HotlineNewsCategory, rhs: HotlineNewsCategory) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  init(type: UInt16, count: UInt16, name: String) {
    self.type = type
    self.count = count
    self.name = name
  }
  
  init(from data: [UInt8]) {
    self.type = data.readUInt16(at: 0)!
    
    if self.type == 2 {
      // Read bundle properties
      self.count = data.readUInt16(at: 2)!
      let (n, _) = data.readPString(at: 4)
      self.name = n!
    }
    else if self.type == 3 {
      // Read category properties
      self.count = data.readUInt16(at: 2)!
//      let guid = data.readUInt32(at: 4)!
//      print("CATEGORY GUID: \(guid)")
//      let addSN = data.readUInt32(at: 20)!
//      let removeSN = data.readUInt32(at: 24)!
      let (n, _) = data.readPString(at: 28)
      self.name = n!
    }
    else {
      self.count = 0
      self.name = ""
    }
  }
}


@Observable
class HotlineFile: Identifiable, Hashable {
  let id = UUID()
  let type: String
  let creator: String
  let fileSize: UInt32
  let name: String
  
  var path: [String] = []
  var isExpanded: Bool = false
  var files: [HotlineFile]? = nil
  
  let isFolder: Bool
  
  static func == (lhs: HotlineFile, rhs: HotlineFile) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  init(type: String, creator: String, fileSize: UInt32, fileName: String) {
    self.type = type
    self.creator = creator
    self.fileSize = fileSize
    self.name = fileName
    
    self.isFolder = (self.type == "fldr")
    if self.isFolder {
      self.files = []
    }
  }
  
  init(from data: [UInt8]) {
    let typeRaw = data.readUInt32(at: 0)!
    let creatorRaw = data.readUInt32(at: 4)!
    
    self.type = typeRaw.fourCharCode()
    self.creator = creatorRaw.fourCharCode()
    self.fileSize = data.readUInt32(at: 8)!
    
    self.isFolder = (self.type == "fldr")
    if self.isFolder {
      self.files = []
    }
    
//    data.readUInt32(at: 12)! // reserved
//    let nameScript = data.readUInt16(at: 16)! // name script
//    print("NAME SCRIPT: \(nameScript)")
    
    let nameLength = data.readUInt16(at: 18)!
    self.name = data.readString(at: 20, length: Int(nameLength))!
  }
}

struct HotlineUser: Identifiable, Hashable {
  let id: UInt16
  let iconID: UInt16
  let status: UInt16
  let name: String
  
  var isAdmin: Bool {
    return ((self.status & 0x0002) != 0)
  }
  
  var isIdle: Bool {
    return ((self.status & 0x0001) != 0)
  }
  
  static func == (lhs: HotlineUser, rhs: HotlineUser) -> Bool {
    return lhs.id == rhs.id
  }
  
  init(id: UInt16, iconID: UInt16, status: UInt16, name: String) {
    self.id = id
    self.iconID = iconID
    self.status = status
    self.name = name
  }
  
  init(from data: [UInt8]) {
    self.id = data.readUInt16(at: 0)!
    self.iconID = data.readUInt16(at: 2)!
    self.status = data.readUInt16(at: 4)!
    
    let userNameLength = Int(data.readUInt16(at: 6)!)
    self.name = data.readString(at: 8, length: userNameLength)!
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
  
  func encoded() -> [UInt8] {
    var data: [UInt8] = []
    data.appendUInt16(self.id)
    data.appendUInt16(self.iconID)
    data.appendUInt16(self.status)
    
    let userNameData = name.data(using: .ascii, allowLossyConversion: true)!
    
    data.appendUInt16(UInt16(userNameData.count))
    data.appendData(userNameData)
    
    return data
    
//    var data = Data()
//    self.encode(to: &data)
//    return data
  }
  
//  func encode(to data: inout Data) {
//    data.appendUInt16(self.id)
//    data.appendUInt16(self.iconID)
//    data.appendUInt16(self.status)
//    
//    let userNameData = name.data(using: .ascii, allowLossyConversion: true)!
//    
//    data.appendUInt16(UInt16(userNameData.count))
//    data.append(userNameData)
//  }
}

struct HotlineTransactionField {
  let type: HotlineTransactionFieldType
  let dataSize: UInt16
  let data: [UInt8]
  
  init(type: HotlineTransactionFieldType, dataSize: UInt16, data: [UInt8]) {
    self.type = type
    self.dataSize = dataSize
    self.data = data
  }
  
  init(type: HotlineTransactionFieldType, val: UInt8) {
    self.init(type: type, dataSize: UInt16(1), data: [val])
  }
  
  init(type: HotlineTransactionFieldType, val: UInt16) {
    self.init(type: type, dataSize: UInt16(2), data: [UInt8](val))
  }
  
  init(type: HotlineTransactionFieldType, val: UInt32) {
    self.init(type: type, dataSize: UInt16(4), data: [UInt8](val))
  }
  
  init(type: HotlineTransactionFieldType, val: UInt64) {
    self.init(type: type, dataSize: UInt16(8), data: [UInt8](val))
  }
  
  init(type: HotlineTransactionFieldType, string: String, encoding: String.Encoding = .ascii, encrypt: Bool = false) {
    var bytes = [UInt8](string.utf8)
    if encrypt {
        bytes = string.utf8.map { char in
            return 0xFF - char
        }
    }

    self.init(type: type, dataSize: UInt16(bytes.count), data: [UInt8](bytes))
  }
  
  init(type: HotlineTransactionFieldType, string: String, encrypt: Bool) {
    self.init(type: type, string: string, encoding: .ascii, encrypt: encrypt)
  }
  
  init(type: HotlineTransactionFieldType, path: String) {
    var components: [String] = []
    
    for component in path.components(separatedBy: "/") {
      if !component.isEmpty {
        components.append(component)
      }
    }
    
    self.init(type: type, pathComponents: components)
  }
  
  init(type: HotlineTransactionFieldType, pathComponents: [String]) {
    var pathData: [UInt8] = []
    
    pathData.appendUInt16(UInt16(pathComponents.count))
    for name in pathComponents {
      pathData.appendUInt16(0)
      
      var nameData = name.data(using: .macOSRoman, allowLossyConversion: true)
      if nameData == nil {
        nameData = Data()
      }
      
      pathData.appendUInt8(UInt8(nameData!.count))
      pathData.appendData(nameData!)
    }
    
    self.init(type: type, dataSize: UInt16(pathData.count), data: pathData)
  }

  func getUInt8() -> UInt8? {
    return self.data.readUInt8(at: 0)
  }
  
  func getUInt16() -> UInt16? {
    return self.data.readUInt16(at: 0)
  }
  
  func getUInt32() -> UInt32? {
    return self.data.readUInt32(at: 0)
  }
  
  func getUInt64() -> UInt64? {
    return self.data.readUInt64(at: 0)
  }
  
  func getInteger() -> Int? {
    switch(self.dataSize) {
    case 1:
      if let val = self.getUInt8() {
        return Int(val)
      }
    case 2:
      if let val = self.getUInt16() {
        return Int(val)
      }
    case 4:
      if let val = self.getUInt32() {
        return Int(val)
      }
    case 8:
      if let val = self.getUInt64() {
        return Int(val)
      }
    default:
      break
    }
    
    return nil
  }
  
  func getString() -> String? {
    return self.data.readString(at: 0, length: self.data.count)
  }
  
  func getUser() -> HotlineUser {
    return HotlineUser(from: self.data)
  }
  
  func getFile() -> HotlineFile {
    return HotlineFile(from: self.data)
  }
  
  func getNewsCategory() -> HotlineNewsCategory {
    return HotlineNewsCategory(from: self.data)
  }
  
  func getNewsList() -> HotlineNewsList {
    return HotlineNewsList(from: self.data)
  }
}

struct HotlineTransaction {
  static let headerSize = 20
  static var sequenceID: UInt32 = 1
  
  static func nextID() -> UInt32 {
    HotlineTransaction.sequenceID += 1
    return HotlineTransaction.sequenceID
  }
  
  var flags: UInt8 = 0
  var isReply: UInt8 = 0
  var type: HotlineTransactionType
  var id: UInt32
  var errorCode: UInt32 = 0
  var totalSize: UInt32 = UInt32(HotlineTransaction.headerSize)
  var dataSize: UInt32 = 0
  
  var fields: [HotlineTransactionField] = []
  
  init(type: HotlineTransactionType) {
    self.type = type
    self.id = HotlineTransaction.nextID()
  }
  
  init?(from data: [UInt8]) {
    guard
      let flags = data.readUInt8(at: 0),
      let isReply = data.readUInt8(at: 1),
      let type = data.readUInt16(at: 2),
      let id = data.readUInt32(at: 4),
      let errorCode = data.readUInt32(at: 8),
      let totalSize = data.readUInt32(at: 12),
      let dataSize = data.readUInt32(at: 16) else {
      
      return nil
    }
    
    self.init(type: HotlineTransactionType(rawValue: type) ?? .unknown, flags: flags, isReply: isReply, id: id, errorCode: errorCode, totalSize: totalSize, dataSize: dataSize)
  }
  
  mutating func decodeFields(from data: [UInt8]) {
    var fieldData = data
    
    guard fieldData.count > 0,
          let fieldCount = fieldData.consumeUInt16(),
          fieldCount > 0 else {
      return
    }
    
    for _ in 0..<fieldCount {
      if
        let fieldID = fieldData.consumeUInt16(),
        let fieldSize = fieldData.consumeUInt16(),
        let fieldRemainingData: [UInt8] = fieldData.consumeBytes(Int(fieldSize)) {
        
        if let fieldType = HotlineTransactionFieldType(rawValue: fieldID) {
          self.fields.append(HotlineTransactionField(type: fieldType, dataSize: fieldSize, data: fieldRemainingData))
        }
        else {
          print("HotlineClient: UNKNOWN FIELD TYPE!", fieldID, fieldSize)
        }
      }
    }
  }
  
  init(type: HotlineTransactionType, flags: UInt8, isReply: UInt8, id: UInt32, errorCode: UInt32, totalSize: UInt32, dataSize: UInt32) {
    self.type = type
    self.flags = flags
    self.isReply = isReply
    self.id = id
    self.errorCode = errorCode
    self.totalSize = totalSize
    self.dataSize = dataSize
  }
  
  mutating func setFieldUInt8(type: HotlineTransactionFieldType, val: UInt8) {
    self.fields.append(HotlineTransactionField(type: type, val: val))
  }
  
  mutating func setFieldUInt16(type: HotlineTransactionFieldType, val: UInt16) {
    self.fields.append(HotlineTransactionField(type: type, val: val))
  }
  
  mutating func setFieldUInt32(type: HotlineTransactionFieldType, val: UInt32) {
    self.fields.append(HotlineTransactionField(type: type, val: val))
  }
  
  mutating func setFieldEncodedString(type: HotlineTransactionFieldType, val: String) {
    self.fields.append(HotlineTransactionField(type: type, string: val, encrypt: true))
  }
  
  mutating func setFieldString(type: HotlineTransactionFieldType, val: String, encoding: String.Encoding = .utf8) {
    self.fields.append(HotlineTransactionField(type: type, string: val, encoding: encoding, encrypt: false))
  }
  
  mutating func setFieldPath(type: HotlineTransactionFieldType, val: [String]) {
    self.fields.append(HotlineTransactionField(type: type, pathComponents: val))
  }
  
  func getField(type: HotlineTransactionFieldType) -> HotlineTransactionField? {
    return self.fields.first { p in
      p.type == type
    }
  }
  
  func getFieldList(type: HotlineTransactionFieldType) -> [HotlineTransactionField] {
    return self.fields.filter { p in
      p.type == type
    }
  }
  
  func encoded() -> [UInt8] {
    var data: [UInt8] = []
    data.appendUInt8(0)
    data.appendUInt8(self.isReply)
    data.appendUInt16(self.isReply == 1 ? HotlineTransactionType.reply.rawValue : self.type.rawValue)
    data.appendUInt32(self.id)
    data.appendUInt32(self.errorCode)
    
    if self.fields.count > 0 {
      var fieldData: [UInt8] = []
      fieldData.appendUInt16(UInt16(self.fields.count))
      for f in self.fields {
        fieldData.appendUInt16(f.type.rawValue)
        fieldData.appendUInt16(f.dataSize)
        fieldData.appendData(f.data)
      }
      
      data.appendUInt32(UInt32(fieldData.count))
      data.appendUInt32(UInt32(fieldData.count))
      data.appendData(fieldData)
    }
    else {
      data.appendUInt32(2)
      data.appendUInt32(2)
      data.appendUInt16(0)
    }
    return data
  }
}

enum HotlineTransactionFieldType: UInt16 {
  case errorText = 100 // String
  case data = 101 // String
  case userName = 102 // String
  case userID = 103 // Integer
  case userIconID = 104 // Integer
  case userLogin = 105 // Encoded string
  case userPassword = 106 // Encoded string
  case referenceNumber = 107 // Integer
  case transferSize = 108 // Integer
  case chatOptions = 109 // Integer
  case userAccess = 110 // 64-bit integer?
  case userAlias = 111 // ???
  case userFlags = 112 // Integer
  case options = 113 // 32-bit integer?
  case chatID = 114 // Integer
  case chatSubject = 115 // String
  case waitingCount = 116 // Integer
  case serverAgreement = 150 // ???
  case serverBanner = 151 // Data?
  case serverBannerType = 152 // Integer
  case serverBannerURL = 153 // String
  case noServerAgreement = 154 // Integer
  case versionNumber = 160 // Integer
  case communityBannerID = 161 // Integer
  case serverName = 162 // String
  case fileNameWithInfo = 200 // Data { type: 4, creator: 4, file size: 4, reserved: 4, name script: 2, name size: 2, name data: size }
  case fileName = 201 // String
  case filePath = 202 // Path
  case fileTransferOptions = 204 // Integer
  case fileTypeString = 205 // String
  case fileCreatorString = 206 // String
  case fileSize = 207 // Integer
  case fileCreateDate = 208
  case fileModifyDate = 209
  case fileComment = 210 // Integer
  case fileNewName = 211 // String
  case fileType = 213 // Integer
  case quotingMessage = 214 // String?
  case automaticResponse = 215 // String
  case folderItemCount = 220 // Integer
  case userNameWithInfo = 300 // Data { user id: 2, icon id: 2, user flags: 2, user name size: 2, user name: size }
  case newsCategoryGUID = 319 // Data?
  case newsCategoryListData = 320 // Data { type: 1 (1 = folder, 10 = category, 255 = other), category name: rest }
  case newsArticleListData = 321 // Data
  case newsCategoryName = 322 // String
  case newsCategoryListData15 = 323 // Data
  case newsPath = 325 // Data
  case newsArticleID = 326 // Integer
  case newsArticleDataFlavor = 327 // String
  case newsArticleTitle = 328 // String
  case newsArticlePoster = 329 // String
  case newsArticleDate = 330 // Data { year: 2, ms: 2, secs: 4 }
  case newsArticlePrevious = 331 // Integer
  case newsArticleNext = 332 // Integer
  case newsArticleData = 333 // Data
  case newsArticleFlags = 334 // Integer
  case newsArticleParentArticle = 335 // Integer
  case newsArticleFirstChildArticle = 336 // Integer
  case newsArticleRecursiveDelete = 337 // Integer
}

enum HotlineTransactionType: UInt16 {
  case reply = 0
  case error = 100
  case getMessageBoard = 101
  case newMessage = 102  // Server
  case oldPostNews = 103
  case serverMessage = 104 // Server
  case sendChat = 105
  case chatMessage = 106 // Server
  case login = 107
  case sendInstantMessage = 108
  case showAgreement = 109  // Server
  case disconnectUser = 110
  case disconnectMessage = 111 // Server
  case inviteToNewChat = 112
  case inviteToChat = 113 // Server
  case rejectChatInvite = 114
  case joinChat = 115
  case leaveChat = 116
  case notifyChatOfUserChange = 117 // Server
  case notifyChatOfUserDelete = 118 // Server
  case notifyChatSubject = 119 // Server
  case setChatSubject = 120
  case agreed = 121
  case serverBanner = 122 // Server
  case getFileNameList = 200
  case downloadFile = 202
  case uploadFile = 203
  case deleteFile = 204
  case newFolder = 205
  case getFileInfo = 206
  case setFileInfo = 207
  case moveFile = 208
  case makeFileAlias = 209
  case downloadFolder = 210
  case downloadInfo = 211 // Server
  case downloadBanner = 212
  case uploadFolder = 213
  case getNewsFile = 294
  case postNews = 295
  case receiveNewsFile = 296 // Server
  case getUserNameList = 300
  case notifyOfUserChange = 301 // Server
  case notifyOfUserDelete = 302 // Server
  case getClientInfoText = 303
  case setClientUserInfo = 304
  case newUser = 350
  case deleteUser = 351
  case getUser = 352
  case setUser = 353
  case userAccess = 354 // Server
  case userBroadcast = 355 // Client & Server
  case getNewsCategoryNameList = 370
  case getNewsArticleNameList = 371
  case deleteNewsItem = 380
  case newNewsFolder = 381
  case newNewsCategory = 382
  case getNewsArticleData = 400
  case postNewsArticle = 410
  case deleteNewsArticle = 411
  case connectionKeepAlive = 500
  
  case unknown = 15000
}

// MARK: - Utilities

func convertHotlineDate(year:UInt16, seconds: UInt32, milliseconds: UInt16) -> Date? {
  var components = DateComponents()
  components.timeZone = .gmt
  components.year = Int(year)
  components.month = 1
  components.day = 1
  components.second = 0
  
  let baseDate = Calendar.current.date(from: components)
  return baseDate?.advanced(by: TimeInterval(seconds))
}
