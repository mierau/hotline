import SwiftUI

@Observable final class Hotline: HotlineClientDelegate {
  let trackerClient: HotlineTrackerClient
  let client: HotlineClient
  
  var status: HotlineClientStatus = .disconnected
  
  var server: Server?  {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverVersion: UInt16?  {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverName: String? {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverTitle: String = "Server"
  var username: String = "bolt"
  var iconID: UInt = 128
  var access: HotlineUserAccessOptions?
  var agreed: Bool = false
  
  var users: [User] = []
  var chat: [ChatMessage] = []
  var messageBoard: [String] = []
  var messageBoardLoaded: Bool = false
  var files: [FileInfo] = []
  var filesLoaded: Bool = false
  var news: [NewsInfo] = []
  var newsLoaded: Bool = false
  
  var downloads: [HotlineFileClient] = []
  
  @ObservationIgnored var bannerClient: HotlineFileClient?
  #if os(macOS)
  var bannerImage: NSImage? = nil
  #elseif os(iOS)
  var bannerImage: UIImage? = nil
  #endif
  
  
  // MARK: -
  
  init(trackerClient: HotlineTrackerClient, client: HotlineClient) {
    self.trackerClient = trackerClient
    self.client = client
    self.client.delegate = self
  }
  
  // MARK: -
  
  @MainActor func getServerList(tracker: String, port: Int = Tracker.defaultPort) async -> [Server] {
    let fetchedServers: [HotlineServer] = await self.trackerClient.fetchServers(address: tracker, port: port)
    
    var servers: [Server] = []
    
    for s in fetchedServers {
      if let serverName = s.name {
        servers.append(Server(name: serverName, description: s.description, address: s.address, port: Int(s.port), users: Int(s.users)))
      }
    }
    
    return servers
  }
  
  @MainActor func disconnectTracker() {
    self.trackerClient.disconnect()
  }
  
  @MainActor func login(server: Server, login: String, password: String, username: String, iconID: UInt, callback: ((Bool) -> Void)? = nil) {
    self.server = server
    self.serverName = server.name
    self.username = username
    self.iconID = iconID
    
    self.client.login(server.address, port: UInt16(server.port), login: login, password: password, username: username, iconID: UInt16(iconID)) { [weak self] err, serverName, serverVersion in
      self?.serverVersion = serverVersion
      if serverName != nil {
        self?.serverName = serverName
      }
      
      callback?(err == nil)
    }
  }
  
  @MainActor func sendUserInfo(username: String, iconID: UInt, options: HotlineUserOptions = [], autoresponse: String? = nil, callback: ((Bool) -> Void)? = nil) {
    self.username = username
    self.iconID = iconID
    
    self.client.sendSetClientUserInfo(username: username, iconID: UInt16(iconID), options: options, autoresponse: autoresponse) { success in
      callback?(success)
    }
  }
  
  @MainActor func getUserList(callback: ((Bool) -> Void)? = nil) {
    self.client.sendGetUserList() { success in
      callback?(success)
    }
  }
  
  @MainActor func disconnect() {
    self.client.disconnect()
    self.bannerClient?.disconnect()
  }
  
  @MainActor func sendAgree() {
    self.client.sendAgree(username: self.username, iconID: UInt16(self.iconID), options: .none)
  }
  
  @MainActor func sendChat(_ text: String) {
    self.client.sendChat(message: text, sent: nil)
  }
  
  @MainActor func getMessageBoard() async -> [String] {
    self.messageBoard = await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetMessageBoard() { err, messages in
        continuation.resume(returning: (err != nil ? [] : messages))
      }
    }
    
    self.messageBoardLoaded = true
    
    return self.messageBoard
  }
  
  @MainActor func getFileList(path: [String] = []) async -> [FileInfo] {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetFileList(path: path, sent: { success in
        if !success {
          continuation.resume(returning: [])
          return
        }
      }, reply: { [weak self] files in
        let parentFile = self?.findFile(in: self?.files ?? [], at: path)
        
        var newFiles: [FileInfo] = []
        for f in files {
          newFiles.append(FileInfo(hotlineFile: f))
        }
        
        DispatchQueue.main.async {
          if let parent = parentFile {
            parent.children = newFiles
          }
          else if path.isEmpty {
            self?.filesLoaded = true
            self?.files = newFiles
          }
          
          continuation.resume(returning: newFiles)
        }
      })
    }
  }
  
  @MainActor func getNewsArticle(id articleID: UInt, at path: [String], flavor: String) async -> String? {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetNewsArticle(id: UInt32(articleID), path: path, flavor: flavor, sent: { success in
        if !success {
          continuation.resume(returning: nil)
          return
        }
        
        print("GET NEWS CATS FROM \(path)")
      }, reply: { articleText in
//          let parentNews = self?.findNews(in: self?.news ?? [], at: path)
        
//        var newCategories: [NewsInfo] = []
//        for category in categories {
//          newCategories.append(NewsInfo(hotlineNewsCategory: category))
//        }
//        
//        if let parent = existingNewsItem {
//          parent.children = newCategories
//        }
//        else if path.isEmpty {
//          self?.news = newCategories
//        }
        
        continuation.resume(returning: articleText)
      })
    }
    
  }
  
  @MainActor func getNewsList(at path: [String] = []) async -> [NewsInfo] {
    return await withCheckedContinuation { [weak self] continuation in
      var requestCategories = true
      
      let existingNewsItem = self?.findNews(in: self?.news ?? [], at: path)
      
      if existingNewsItem != nil {
        if existingNewsItem!.type != .bundle {
          requestCategories = false
        }
      }
      
      if requestCategories {
        self?.client.sendGetNewsCategories(path: path, sent: { success in
          if !success {
            continuation.resume(returning: [])
            return
          }
          
          print("GET NEWS CATS FROM \(path)")
        }, reply: { [weak self] categories in
//          let parentNews = self?.findNews(in: self?.news ?? [], at: path)
          
          var newCategories: [NewsInfo] = []
          for category in categories {
            newCategories.append(NewsInfo(hotlineNewsCategory: category))
          }
          
          DispatchQueue.main.async {
            if let parent = existingNewsItem {
              parent.children = newCategories
            }
            else if path.isEmpty {
              self?.newsLoaded = true
              self?.news = newCategories
            }
            
            continuation.resume(returning: newCategories)
          }
        })
      }
      else {
        self?.client.sendGetNewsArticles(path: path, sent: { success in
          if !success {
            DispatchQueue.main.async {
              continuation.resume(returning: [])
            }
            return
          }
          
          print("GET NEWS ARTICLES FROM \(path)")
        }, reply: { [weak self] articles in
//          let parentNews = self?.findNews(in: self?.news ?? [], at: path)
          print("GENERATING NEWS")
          
          var newArticles: [NewsInfo] = []
          for article in articles {
            newArticles.append(NewsInfo(hotlineNewsArticle: article))
          }
          
          DispatchQueue.main.async {
            if let parent = existingNewsItem {
              print("UNDER PARENT:", parent.name)
              parent.children = newArticles
              
              print(parent.children)
            }
            else if path.isEmpty {
              self?.news = newArticles
            }
            
            continuation.resume(returning: newArticles)
          }
        })
      }
    }
  }
  
  @MainActor func getNewsCategories(at path: [String] = []) async -> [NewsInfo] {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetNewsCategories(path: path, sent: { success in
        if !success {
          DispatchQueue.main.async {
            continuation.resume(returning: [])
          }
          return
        }
        
        print("GET NEWS CATS FROM \(path)")
      }, reply: { [weak self] categories in
        let parentNews = self?.findNews(in: self?.news ?? [], at: path)
        
        var newCategories: [NewsInfo] = []
        for category in categories {
          newCategories.append(NewsInfo(hotlineNewsCategory: category))
        }
        
        DispatchQueue.main.async {
          if let parent = parentNews {
            parent.children = newCategories
          }
          else if path.isEmpty {
            self?.news = newCategories
          }
          
          continuation.resume(returning: newCategories)
        }
      })
    }
  }
  
  @MainActor func getArticles(at path: [String]) async -> [NewsInfo] {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetNewsArticles(path: path, sent: { success in
        if !success {
          DispatchQueue.main.async {
            continuation.resume(returning: [])
          }
          return
        }
      }, reply: { articles in
        DispatchQueue.main.async {
          continuation.resume(returning: [])
        }
      })
    }
  }
  
  func downloadFile(path: [String], callback: ((Bool) -> Void)?) {
    
  }
  
  @MainActor func downloadBanner(force: Bool = false, callback: ((Bool) -> Void)?) {
    if let b = self.bannerClient {
      b.disconnect()
      self.bannerClient = nil
    }
    
    if force {
      self.bannerImage = nil
    }
    
    if self.bannerImage != nil {
      callback?(true)
      return
    }
    
    self.client.sendDownloadBanner(sent: { success in
      if !success {
        print("FAIL BANNER")
        callback?(false)
        return
      }
    }, reply: { [weak self] downloadReferenceNumber, downloadTransferSize in
      if
        let self = self,
        let address = self.server?.address,
        let port = self.server?.port,
        let referenceNumber = downloadReferenceNumber,
        let transferSize = downloadTransferSize {
        self.bannerClient = HotlineFileClient(address: address, port: UInt16(port), reference: referenceNumber, size: UInt32(transferSize), type: .banner)
        self.bannerClient?.downloadToMemory({ [weak self] data in
          if let b = self?.bannerClient {
            b.disconnect()
            self?.bannerClient = nil
          }
          
          if data != nil {
            #if os(macOS)
            self?.bannerImage = NSImage(data: data!)
            #elseif os(iOS)
            self?.bannerImage = UIImage(data: data!)
            #endif
          }
          
          callback?(data != nil)
        })
      }
    })
  }
  
  // MARK: - Hotline Delegate
  
  func hotlineStatusChanged(status: HotlineClientStatus) {
    print("Hotline: Connection status changed to: \(status)")
    
    if status == .disconnected {
      self.serverVersion = nil
      self.serverName = nil
      self.access = nil
      
      self.users = []
      self.chat = []
      self.messageBoard = []
      self.messageBoardLoaded = false
      self.files = []
      self.filesLoaded = false
      self.news = []
      self.newsLoaded = false
      
      self.bannerImage = nil
      
      if let b = self.bannerClient {
        b.disconnect()
        self.bannerClient = nil
      }
    }
    
    self.status = status
  }
  
  func hotlineGetUserInfo() -> (String, UInt16) {
    return (self.username, UInt16(self.iconID))
  }
  
  func hotlineReceivedAgreement(text: String) {
    self.chat.append(ChatMessage(text: text, type: .agreement, date: Date()))
  }
  
  func hotlineReceivedServerMessage(message: String) {
//    print("Hotline: received server message:\n\(message)")
//    self.chat.append(ChatMessage(text: message, type: .server, date: Date()))
  }
  
  func hotlineReceivedChatMessage(message: String) {
    self.chat.append(ChatMessage(text: message, type: .message, date: Date()))
  }
  
  func hotlineReceivedUserList(users: [HotlineUser]) {
    var existingUserIDs: [UInt] = []
    var userList: [User] = []
    
    print("GOT USER LIST", users)
    
    for u in users {
      if let i = self.users.firstIndex(where: { $0.id == u.id }) {
        // If a user is already in the user list we have to assume
        // they changed somehow before we received the user list
        // which means let's keep their existing info.
        existingUserIDs.append(UInt(u.id))
        userList.append(self.users[i])
      }
      else {
        userList.append(User(hotlineUser: u))
      }
    }
    
    if !existingUserIDs.isEmpty {
      self.users = self.users.filter { !existingUserIDs.contains($0.id) }
    }
    
    self.users = userList + self.users
  }
  
  func hotlineUserChanged(user: HotlineUser) {
    self.addOrUpdateHotlineUser(user)
  }
    
  func hotlineUserDisconnected(userID: UInt16) {
    if let existingUserIndex = self.users.firstIndex(where: { $0.id == UInt(userID) }) {
      let user = self.users.remove(at: existingUserIndex)
      self.chat.append(ChatMessage(text: "\(user.name) left", type: .status, date: Date()))
    }
  }
  
  func hotlineReceivedUserAccess(options: HotlineUserAccessOptions) {
    print("Hotline: got access options")
    print(options, options.contains(.canSendChat), options.contains(.canBroadcast))
    
    self.access = options
  }
  
  func hotlineReceivedError(message: String) {
    
  }
  
  // MARK: - Utilities
  
  func updateServerTitle() {
    self.serverTitle = self.serverName ?? self.server?.name ?? server?.address ?? "Server"
  }
  
  private func addOrUpdateHotlineUser(_ user: HotlineUser) {
    if let i = self.users.firstIndex(where: { $0.id == user.id }) {
      print("Hotline: updating user \(self.users[i].name)")
      self.users[i] = User(hotlineUser: user)
    }
    else {
      print("Hotline: added user: \(user.name)")
      self.users.append(User(hotlineUser: user))
      self.chat.append(ChatMessage(text: "\(user.name) joined", type: .status, date: Date()))
    }
  }
  
  private func findFile(in filesToSearch: [FileInfo], at path: [String]) -> FileInfo? {
    guard !path.isEmpty, !filesToSearch.isEmpty else { return nil }
    
    let currentName = path[0]
    
    for file in filesToSearch {
      if file.name == currentName {
        if path.count == 1 {
          return file
        }
        else if let subfiles = file.children {
          let remainingPath = Array(path[1...])
          return self.findFile(in: subfiles, at: remainingPath)
        }
      }
    }
    
    return nil
  }
  
  private func findNews(in newsToSearch: [NewsInfo], at path: [String]) -> NewsInfo? {
    guard !path.isEmpty, !newsToSearch.isEmpty else { return nil }
    
    let currentName = path[0]
    
    for news in newsToSearch {
      if news.name == currentName {
        if path.count == 1 {
          return news
        }
        else if !news.children.isEmpty {
          let remainingPath = Array(path[1...])
          return self.findNews(in: news.children, at: remainingPath)
        }
      }
    }
    
    return nil
  }
}
