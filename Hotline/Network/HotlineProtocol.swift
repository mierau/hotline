import Foundation

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

struct HotlineUser: Identifiable, Hashable {
  let id: UInt16
  let userName: String
  
  static func == (lhs: HotlineUser, rhs: HotlineUser) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}

struct HotlineUserInfo {
  let id: UInt16
  let iconID: UInt16
  let flags: UInt16
  let userName: String
  
  init(data: Data) {
    self.id = data.readUInt16(at: 0)!
    self.iconID = data.readUInt16(at: 2)!
    self.flags = data.readUInt16(at: 4)!
    
    let userNameLength = data.readUInt16(at: 6)!
    self.userName = data.readString(at: 8, length: Int(userNameLength), encoding: .ascii)!
  }
}

struct HotlineTransactionParameter {
  let type: HotlineTransactionFieldType
  let dataSize: UInt16
  let data: Data
  
  func getUInt8() -> UInt8? {
    return data.readUInt8(at: 0)
  }
  
  func getUInt16() -> UInt16? {
    return data.readUInt16(at: 0)
  }
  
  func getUInt32() -> UInt32? {
    return data.readUInt32(at: 0)
  }
  
  func getString(encoding: String.Encoding = .ascii) -> String? {
    return String(data: self.data, encoding: encoding)
  }
  
  func getUserInfo() -> HotlineUserInfo {
    return HotlineUserInfo(data: self.data)
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
  var id: UInt32 = HotlineTransaction.nextID()
  var errorCode: UInt32 = 0
  var totalSize: UInt32 = UInt32(HotlineTransaction.headerSize)
  var dataSize: UInt32 = 0
  
  var parameters: [HotlineTransactionParameter] = []
  
  init(type: HotlineTransactionType) {
    self.type = type
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
  
  mutating func setParameterUInt8(type: HotlineTransactionFieldType, val: UInt8) {
    self.parameters.append(HotlineTransactionParameter(type: type, dataSize: UInt16(MemoryLayout<UInt8>.size), data: Data(val)))
//    self.parameters[type] = HotlineTransactionParameter(dataSize: UInt16(MemoryLayout<UInt8>.size), data: Data(val))
  }
  
  mutating func setParameterUInt16(type: HotlineTransactionFieldType, val: UInt16) {
    self.parameters.append(HotlineTransactionParameter(type: type, dataSize: UInt16(MemoryLayout<UInt16>.size), data: Data(val)))
//    self.parameters[type] = HotlineTransactionParameter(dataSize: UInt16(MemoryLayout<UInt16>.size), data: Data(val))
  }
  
  mutating func setParameterUInt32(type: HotlineTransactionFieldType, val: UInt32) {
    self.parameters.append(HotlineTransactionParameter(type: type, dataSize: UInt16(MemoryLayout<UInt32>.size), data: Data(val)))
//    self.parameters[type] = HotlineTransactionParameter(type: type, dataSize: UInt16(MemoryLayout<UInt32>.size), data: Data(val))
  }
  
  mutating func setParameterEncodedString(type: HotlineTransactionFieldType, val: String) {
    let encodedVal = String(val.utf8.map { char in
      Character(UnicodeScalar(0xFF - char))
    })
    
    self.setParameterString(type: type, val: encodedVal)
  }
  
  mutating func setParameterString(type: HotlineTransactionFieldType, val: String) {
    var stringData = Data()
//    stringData.appendUInt16(UInt16(val.count))
    stringData.append(contentsOf: val.utf8)
    
    self.parameters.append(HotlineTransactionParameter(type: type, dataSize: UInt16(stringData.count), data: stringData))
//    self.parameters[type] = HotlineTransactionParameter(dataSize: UInt16(stringData.count), data: stringData)
  }
  
  func getParameter(type: HotlineTransactionFieldType) -> HotlineTransactionParameter? {
    return self.parameters.first { p in
      p.type == type
    }
    
//    return self.parameters[type]
  }
  
  func getParameterList(type: HotlineTransactionFieldType) -> [HotlineTransactionParameter] {
    return self.parameters.filter { p in
      p.type == type
    }
  }
  
  func encoded() -> Data {
    var data = Data()
    self.encode(to: &data)
    return data
  }
  
  func encode(to data: inout Data) {
    data.appendUInt8(self.flags)
    data.appendUInt8(self.isReply)
    data.appendUInt16(self.type.rawValue)
    data.appendUInt32(self.id)
    data.appendUInt32(self.errorCode)
    
    if self.parameters.count > 0 {
      var parameterData = Data()
      parameterData.appendUInt16(UInt16(self.parameters.count))
      for param in self.parameters {
        parameterData.appendUInt16(param.type.rawValue)
        parameterData.appendUInt16(param.dataSize)
        parameterData.append(param.data)
      }
      
      data.appendUInt32(UInt32(parameterData.count))
      data.appendUInt32(UInt32(parameterData.count))
      data.append(parameterData)
    }
    else {
      data.appendUInt32(0)
      data.appendUInt32(0)
    }
  }
}

enum HotlineTransactionFieldType: UInt16 {
  case userName = 102 // String
  case userLogin = 105 // Encoded string
  case userPassword = 106 // Encoded string
  case userIconID = 104 // Integer
  case userID = 103 // Integer
  case data = 101 // String
  case userAccess = 110 // 64-bit integer??
  case userFlags = 112
  case options = 113 // 32-bit integer?
  case versionNumber = 160 // Integer
  case bannerID = 161
  case serverName = 162
  case userInfo = 300
}

enum HotlineTransactionType: UInt16 {
  case reply = 0
  case error = 100
  case getMessages = 101
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
}

