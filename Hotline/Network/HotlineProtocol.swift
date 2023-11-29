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

struct HotlineTransactionParameter {
  let id: UInt16
  let dataSize: UInt16
  let data: Data
}

struct HotlineTransaction {
  static let headerSize = 20
  
  let flags: UInt8
  let isReply: UInt8
  let type: HotlineTransactionType
  let id: UInt32
  let errorCode: UInt32
  let totalSize: UInt32
  let dataSize: UInt32
  
  var parameterCount: UInt16 = 0
  var parameters: [HotlineTransactionParameter]? = nil
  
  func encode(to data: inout Data) {
    data.appendUInt8(self.flags)
    data.appendUInt8(self.isReply)
    data.appendUInt16(self.type.rawValue)
    data.appendUInt32(self.id)
    data.appendUInt32(self.errorCode)
    data.appendUInt32(self.totalSize)
    data.appendUInt32(self.dataSize)
    
    if let p = self.parameters, p.count > 0 {
      data.appendUInt16(UInt16(p.count))
      for param in p {
        data.appendUInt16(param.id)
        data.appendUInt16(param.dataSize)
        data.append(param.data)
      }
    }
  }
}

enum HotlineTransactionType: UInt16 {
  case unknown = 0
  case error = 100
  case getMessages = 101
  case newMessage = 102
  case oldPostNews = 103
  case serverMessage = 104
  case sendChat = 105
  case chatMessage = 106
  case login = 107
  case sendInstantMessage = 108
  case showAgreement = 109
  case disconnectUser = 110
  case disconnectMessage = 111
  case inviteToNewChat = 112
  case inviteToChat = 113
  case rejectChatInvite = 114
  case joinChat = 115
  case leaveChat = 116
  case notifyChatOfUserChange = 117
  case notifyChatOfUserDelete = 118
  case notifyChatSubject = 119
  case setChatSubject = 120
  case agreed = 121
  case serverBanner = 122
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
  case downloadInfo = 211
  case downloadBanner = 212
  case uploadFolder = 213
  case getUserNameList = 300
  case notifyOfUserChange = 301
  case notifyOfUserDelete = 302
  case getClientInfoText = 303
  case setClientUserInfo = 304
  case newUser = 350
  case deleteUser = 351
  case getUser = 352
  case setUser = 353
  case userAccess = 354
  case userBroadcast = 355
  case getNewsCategoryNameList = 370
  case getNewsArticleNameList = 371
  case deleteNewsItem = 380
  case newNewsFolder = 381
  case newNewsCategory = 382
  case getNewsArticleData = 400
  case postNewsArticle = 410
  case deleteNewsArticle = 411
}

