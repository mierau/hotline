import SwiftUI

@Observable
class Hotline: Equatable, HotlineClientDelegate, HotlineFileDownloadClientDelegate, HotlineFilePreviewClientDelegate, HotlineFileUploadClientDelegate {
  let id: UUID = UUID()
  let trackerClient: HotlineTrackerClient
  let client: HotlineClient
  
  static func == (lhs: Hotline, rhs: Hotline) -> Bool {
    return lhs.id == rhs.id
  }
  
  #if os(macOS)
  static func getClassicIcon(_ index: Int) -> NSImage? {
    return NSImage(named: "Classic/\(index)")
  }
  #elseif os(iOS)
  static func getClassicIcon(_ index: Int) -> UIImage? {
    return UIImage(named: "Classic/\(index)")
  }
  #endif
  
  // The icon ordering here was painsakenly pulled manually
  // from the original Hotline client to display the classic icons
  // in the same order as the original client.
  static let classicIconSet: [Int] = [
    141, 149, 150, 151, 172, 184, 204,
    2013, 2036, 2037, 2055, 2400, 2505, 2534,
    2578, 2592, 4004, 4015, 4022, 4104, 4131,
    4134, 4136, 4169, 4183, 4197, 4240, 4247,
    128, 129, 130, 131, 132, 133, 134,
    135, 136, 137, 138, 139, 140, 142,
    143, 144, 145, 146, 147, 148, 152,
    153, 154, 155, 156, 157, 158, 159,
    160, 161, 162, 163, 164, 165, 166,
    167, 168, 169, 170, 171, 173, 174,
    175, 176, 177, 178, 179, 180, 181,
    182, 183, 185, 186, 187, 188, 189,
    190, 191, 192, 193, 194, 195, 196,
    197, 198, 199, 200, 201, 202, 203,
    205, 206, 207, 208, 209, 212, 214,
    215, 220, 233, 236, 237, 243, 244,
    277, 410, 414, 500, 666, 1250, 1251,
    1968, 1969, 2000, 2001, 2002, 2003, 2004,
    2006, 2007, 2008, 2009, 2010, 2011, 2012,
    2014, 2015, 2016, 2017, 2018, 2019, 2020,
    2021, 2022, 2023, 2024, 2025, 2026, 2027,
    2028, 2029, 2030, 2031, 2032, 2033, 2034,
    2035, 2038, 2040, 2041, 2042, 2043, 2044,
    2045, 2046, 2047, 2048, 2049, 2050, 2051,
    2052, 2053, 2054, 2056, 2057, 2058, 2059,
    2060, 2061, 2062, 2063, 2064, 2065, 2066,
    2067, 2070, 2071, 2072, 2073, 2075, 2079,
    2098, 2100, 2101, 2102, 2103, 2104, 2105,
    2106, 2107, 2108, 2109, 2110, 2112, 2113,
    2115, 2116, 2117, 2118, 2119, 2120, 2121,
    2122, 2123, 2124, 2125, 2126, 4150, 2223,
    2401, 2402, 2403, 2404, 2500, 2501, 2502,
    2503, 2504, 2506, 2507, 2528, 2529, 2530,
    2531, 2532, 2533, 2535, 2536, 2537, 2538,
    2539, 2540, 2541, 2542, 2543, 2544, 2545,
    2546, 2547, 2548, 2549, 2550, 2551, 2552,
    2553, 2554, 2555, 2556, 2557, 2558, 2559,
    2560, 2561, 2562, 2563, 2564, 2565, 2566,
    2567, 2568, 2569, 2570, 2571, 2572, 2573,
    2574, 2575, 2576, 2577, 2579, 2580, 2581,
    2582, 2583, 2584, 2585, 2586, 2587, 2588,
    2589, 2590, 2591, 2593, 2594, 2595, 2596,
    2597, 2598, 2599, 2600, 4000, 4001, 4002,
    4003, 4005, 4006, 4007, 4008, 4009, 4010,
    4011, 4012, 4013, 4014, 4016, 4017, 4018,
    4019, 4020, 4021, 4023, 4024, 4025, 4026,
    4027, 4028, 4029, 4030, 4031, 4032, 4033,
    4034, 4035, 4036, 4037, 4038, 4039, 4040,
    4041, 4042, 4043, 4044, 4045, 4046, 4047,
    4048, 4049, 4050, 4051, 4052, 4053, 4054,
    4055, 4056, 4057, 4058, 4059, 4060, 4061,
    4062, 4063, 4064, 4065, 4066, 4067, 4068,
    4069, 4070, 4071, 4072, 4073, 4074, 4075,
    4076, 4077, 4078, 4079, 4080, 4081, 4082,
    4083, 4084, 4085, 4086, 4087, 4088, 4089,
    4090, 4091, 4092, 4093, 4094, 4095, 4096,
    4097, 4098, 4099, 4100, 4101, 4102, 4103,
    4105, 4106, 4107, 4108, 4109, 4110, 4111,
    4112, 4113, 4114, 4115, 4116, 4117, 4118,
    4119, 4120, 4121, 4122, 4123, 4124, 4125,
    4126, 4127, 4128, 4129, 4130, 4132, 4133,
    4135, 4137, 4138, 4139, 4140, 4141, 4142,
    4143, 4144, 4145, 4146, 4147, 4148, 4149,
    4151, 4152, 4153, 4154, 4155, 4156, 4157,
    4158, 4159, 4160, 4161, 4162, 4163, 4164,
    4165, 4166, 4167, 4168, 4170, 4171, 4172,
    4173, 4174, 4175, 4176, 4177, 4178, 4179,
    4180, 4181, 4182, 4184, 4185, 4186, 4187,
    4188, 4189, 4190, 4191, 4192, 4193, 4194,
    4195, 4196, 4198, 4199, 4200, 4201, 4202,
    4203, 4204, 4205, 4206, 4207, 4208, 4209,
    4210, 4211, 4212, 4213, 4214, 4215, 4216,
    4217, 4218, 4219, 4220, 4221, 4222, 4223,
    4224, 4225, 4226, 4227, 4228, 4229, 4230,
    4231, 4232, 4233, 4234, 4235, 4236, 4238,
    4241, 4242, 4243, 4244, 4245, 4246, 4248,
    4249, 4250, 4251, 4252, 4253, 4254, 31337,
    6001, 6002, 6003, 6004, 6005, 6008, 6009,
    6010, 6011, 6012, 6013, 6014, 6015, 6016,
    6017, 6018, 6023, 6025, 6026, 6027, 6028,
    6029, 6030, 6031, 6032, 6033, 6034, 6035
  ]
  
  var status: HotlineClientStatus = .disconnected
  var server: Server?  {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverVersion: UInt16 = 123
  var serverName: String? {
    didSet {
      self.updateServerTitle()
    }
  }
  var serverTitle: String = "Server"
  var username: String = "guest"
  var iconID: Int = 414
  var access: HotlineUserAccessOptions?
  var agreed: Bool = false
  var users: [User] = []
  var accounts: [HotlineAccount] = []
  var chat: [ChatMessage] = []
  var messageBoard: [String] = []
  var messageBoardLoaded: Bool = false
  var files: [FileInfo] = []
  var filesLoaded: Bool = false
  var news: [NewsInfo] = []
  private var newsLookup: [String:NewsInfo] = [:]
  var newsLoaded: Bool = false
  var accountsLoaded: Bool = false
  var instantMessages: [UInt16:[InstantMessage]] = [:]
  var transfers: [TransferInfo] = []
  var downloads: [HotlineTransferClient] = []
  var unreadInstantMessages: [UInt16:UInt16] = [:]
  var unreadPublicChat: Bool = false
  var errorDisplayed: Bool = false
  var errorMessage: String? = nil
  
  @ObservationIgnored var bannerClient: HotlineFilePreviewClient?
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
  
  @MainActor func getServerList(tracker: String, port: Int = HotlinePorts.DefaultTrackerPort) async -> [Server] {
    var servers: [Server] = []
    
    if let fetchedServers: [HotlineServer] = try? await self.trackerClient.fetchServers(address: tracker, port: port) {
      for s in fetchedServers {
        if let serverName = s.name {
          servers.append(Server(name: serverName, description: s.description, address: s.address, port: Int(s.port), users: Int(s.users)))
        }
      }
    }
    
    return servers
  }
  
  @MainActor func disconnectTracker() {
    self.trackerClient.close()
  }
  
  @MainActor func login(server: Server, username: String, iconID: Int, callback: ((Bool) -> Void)? = nil) {
    self.server = server
    self.serverName = server.name
    self.username = username
    self.iconID = iconID
    
    self.client.login(address: server.address, port: server.port, login: server.login, password: server.password, username: username, iconID: UInt16(iconID)) { [weak self] err, serverName, serverVersion in
      self?.serverVersion = serverVersion ?? 123
      if serverName != nil {
        self?.serverName = serverName
      }
      
      callback?(err == nil)
    }
  }
  
  @MainActor func sendUserInfo(username: String, iconID: Int, options: HotlineUserOptions = [], autoresponse: String? = nil) {
    self.username = username
    self.iconID = iconID
    
    self.client.sendSetClientUserInfo(username: username, iconID: UInt16(iconID), options: options, autoresponse: autoresponse)
  }
  
  @MainActor func getUserList() {
    self.client.sendGetUserList()
  }
  
  @MainActor func disconnect() {
    self.client.disconnect()
    self.bannerClient?.cancel()
  }
  
  @MainActor func sendAgree() {
    self.client.sendAgree(username: self.username, iconID: UInt16(self.iconID), options: .none)
  }
  
  @MainActor func sendInstantMessage(_ text: String, userID: UInt16) {
    let message = InstantMessage(direction: .outgoing, text: text.convertingLinksToMarkdown(), type: .message, date: Date())
    
    if self.instantMessages[userID] == nil {
      self.instantMessages[userID] = [message]
    }
    else {
      self.instantMessages[userID]!.append(message)
    }
    
    self.client.sendInstantMessage(message: text, userID: userID)
    
    if Prefs.shared.playPrivateMessageSound && Prefs.shared.playPrivateMessageSound {
      SoundEffectPlayer.shared.playSoundEffect(.chatMessage)
    }
  }
  
  func markPublicChatAsRead() {
    self.unreadPublicChat = false
  }
  
  func hasUnreadInstantMessages(userID: UInt16) -> Bool {
    return self.unreadInstantMessages[userID] != nil
  }
  
  func markInstantMessagesAsRead(userID: UInt16) {
    self.unreadInstantMessages.removeValue(forKey: userID)
  }
  
  @MainActor func sendChat(_ text: String, announce: Bool = false) {
    self.client.sendChat(message: text, announce: announce)
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
  
  @MainActor func postToMessageBoard(text: String) {
    self.client.sendPostMessageBoard(text: text)
  }
    
  @MainActor func getFileList(path: [String] = []) async -> [FileInfo] {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetFileList(path: path) { [weak self] files in
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
      }
    }
  }
  
  @MainActor func getNewsArticle(id articleID: UInt, at path: [String], flavor: String) async -> String? {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetNewsArticle(id: UInt32(articleID), path: path, flavor: flavor) { articleText in
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
      }
    }
    
  }
  
  @MainActor func getAccounts() async -> [HotlineAccount] {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetAccounts() { articles in
        continuation.resume(returning: articles)
      }
    }
  }
  
  @MainActor func getNewsList(at path: [String] = []) async {
    return await withCheckedContinuation { [weak self] continuation in
      let parentNewsGroup = self?.findNews(in: self?.news ?? [], at: path)
      
      // Send a categories request for bundle paths or root (empty path)
      if path.isEmpty || parentNewsGroup?.type == .bundle {
        print("Hotline: Requesting categories at: /\(path.joined(separator: "/"))")
        
        self?.client.sendGetNewsCategories(path: path) { @MainActor [weak self] categories in
          // Create info for each category returned.
          var newCategoryInfos: [NewsInfo] = []
          
          // Transform hotline categories into NewsInfo objects.
          for category in categories {
            var newsCategoryInfo = NewsInfo(hotlineNewsCategory: category)
            
            if let lookupPath = newsCategoryInfo.lookupPath {
              // Merge returned category info with existing category info.
              if let existingCategoryInfo = self?.newsLookup[lookupPath] {
                print("Hotline: Merging category into existing category at \(lookupPath)")
                
                existingCategoryInfo.count = newsCategoryInfo.count
                existingCategoryInfo.name = newsCategoryInfo.name
                existingCategoryInfo.path = newsCategoryInfo.path
                existingCategoryInfo.categoryID = newsCategoryInfo.categoryID
                newsCategoryInfo = existingCategoryInfo
              }
              else {
                print("Hotline: New category added at \(lookupPath)")
                self?.newsLookup[lookupPath] = newsCategoryInfo
              }
            }
            
            newCategoryInfos.append(newsCategoryInfo)
          }
          
          if let parent = parentNewsGroup {
            parent.children = newCategoryInfos
          }
          else if path.isEmpty {
            self?.newsLoaded = true
            self?.news = newCategoryInfos
          }
          
          continuation.resume()
        }
      }
      else {
        print("Hotline: Requesting articles at: /\(path.joined(separator: "/"))")
        
        self?.client.sendGetNewsArticles(path: path) { @MainActor [weak self] articles in
          print("Hotline: Organizing news at \(path.joined(separator: "/"))")

          // Create info for each article returned.
          var newArticleInfos: [NewsInfo] = []
          
          for article in articles {
            var newsArticleInfo = NewsInfo(hotlineNewsArticle: article)
            
            if let lookupPath = newsArticleInfo.lookupPath {
              // Merge returned category info with existing category info.
              if let existingArticleInfo = self?.newsLookup[lookupPath] {
                print("Hotline: Merging article into existing article at \(lookupPath)")
                
                existingArticleInfo.count = newsArticleInfo.count
                existingArticleInfo.name = newsArticleInfo.name
                existingArticleInfo.path = newsArticleInfo.path
                existingArticleInfo.articleUsername = newsArticleInfo.articleUsername
                existingArticleInfo.articleDate = newsArticleInfo.articleDate
                existingArticleInfo.articleFlavors = newsArticleInfo.articleFlavors
                existingArticleInfo.articleID = newsArticleInfo.articleID
                newsArticleInfo = existingArticleInfo
              }
              else {
                print("Hotline: New article added at \(lookupPath)")
                self?.newsLookup[lookupPath] = newsArticleInfo
              }
            }
            
            newArticleInfos.append(newsArticleInfo)
          }
          
          let organizedNewsArticles: [NewsInfo] = self?.organizeNewsArticles(newArticleInfos) ?? []
          if let parent = parentNewsGroup {
            parent.children = organizedNewsArticles
          }
          
          continuation.resume()
        }
      }
    }
  }
  
  func organizeNewsArticles(_ flatArticles: [NewsInfo]) -> [NewsInfo] {
    // Place articles under their parent.
    var organized: [NewsInfo] = []
    for article in flatArticles {
      if let parentLookupPath = article.parentArticleLookupPath,
         let parentArticle = self.newsLookup[parentLookupPath] {
//        article.expanded = true
        if parentArticle.children.firstIndex(of: article) == nil {
          article.expanded = true
          parentArticle.children.append(article)
        }
      }
      else {
        organized.append(article)
      }
    }
    
    return organized
  }
  
  @MainActor func postNewsArticle(title: String, body: String, at path: [String], parentID: UInt32 = 0) async -> Bool {
    
    
    return await withCheckedContinuation { [weak self] continuation in
      guard let client = self?.client else {
        continuation.resume(returning: false)
        return
      }
      
      client.postNewsArticle(title: title, text: body, path: path, parentID: parentID, callback: { success in
        print("Hotline: News article posted? \(success)")
        continuation.resume(returning: success)
      })
    }
  }
  
//  @MainActor func getNewsCategories(at path: [String] = []) async -> [NewsInfo] {
//    return await withCheckedContinuation { [weak self] continuation in
//      guard let client = self?.client else {
//        continuation.resume(returning: [])
//        return
//      }
//      
//      client.sendGetNewsCategories(path: path) { [weak self] categories in
//        let parentNews = self?.findNews(in: self?.news ?? [], at: path)
//        
//        var newCategories: [NewsInfo] = []
//        for category in categories {
//          let categoryInfo: NewsInfo = NewsInfo(hotlineNewsCategory: category)
//          newCategories.append(categoryInfo)
//          self?.newsLookup[categoryInfo.path.joined(separator: "/")] = categoryInfo
//        }
//        
//        DispatchQueue.main.async {
//          if let parent = parentNews {
//            parent.children = newCategories
//          }
//          else if path.isEmpty {
//            self?.news = newCategories
//          }
//          
//          continuation.resume(returning: newCategories)
//        }
//      }
//    }
//  }
  
  @MainActor func getArticles(at path: [String]) async -> [NewsInfo] {
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetNewsArticles(path: path) { articles in
        continuation.resume(returning: [])
      }
    }
  }
  
  @MainActor func downloadFile(_ fileName: String, path: [String], complete callback: ((TransferInfo, URL) -> Void)? = nil) {
    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }
    
    self.client.sendDownloadFile(name: fileName, path: fullPath) { [weak self] success, downloadReferenceNumber, downloadTransferSize, downloadFileSize, downloadWaitingCount in
      print("GOT DOWNLOAD REPLY:")
      print("\tSUCCESS?", success)
      print("\tTRANSFER SIZE: \(downloadTransferSize.debugDescription)")
      print("\tFILE SIZE: \(downloadFileSize.debugDescription)")
      print("\tREFERENCE NUM: \(downloadReferenceNumber.debugDescription)")
      print("\tWAITING COUNT: \(downloadWaitingCount.debugDescription)")
      
      if
        let self = self,
//        let server = self.server,
        let address = self.server?.address,
        let port = self.server?.port,
        let referenceNumber = downloadReferenceNumber,
        let transferSize = downloadTransferSize {
        
        let fileClient = HotlineFileDownloadClient(address: address, port: UInt16(port), reference: referenceNumber, size: UInt32(transferSize))
//        let previewClient = HotlineFilePreviewClient(server: self.server, reference: referenceNumber, size: UInt32(transferSize), type: .fileDownload)
//        let fileClient = HotlineFileClient(address: address, port: UInt16(port), reference: referenceNumber, size: UInt32(transferSize), type: .fileDownload)
        fileClient.delegate = self
        self.downloads.append(fileClient)
        
        let transfer = TransferInfo(id: referenceNumber, title: fileName, size: UInt(transferSize))
        transfer.downloadCallback = callback
        self.transfers.append(transfer)
        
        fileClient.start()
      }
    }
  }
  
  @MainActor func downloadFileTo(url fileURL: URL, fileName: String, path: [String], progress progressCallback: ((TransferInfo, Double) -> Void)? = nil, complete callback: ((TransferInfo, URL) -> Void)? = nil) {
    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }
    
    self.client.sendDownloadFile(name: fileName, path: fullPath) { [weak self] success, downloadReferenceNumber, downloadTransferSize, downloadFileSize, downloadWaitingCount in
      print("GOT DOWNLOAD REPLY:")
      print("\tSUCCESS?", success)
      print("\tTRANSFER SIZE: \(downloadTransferSize.debugDescription)")
      print("\tFILE SIZE: \(downloadFileSize.debugDescription)")
      print("\tREFERENCE NUM: \(downloadReferenceNumber.debugDescription)")
      print("\tWAITING COUNT: \(downloadWaitingCount.debugDescription)")
      
      if
        let self = self,
        let address = self.server?.address,
        let port = self.server?.port,
        let referenceNumber = downloadReferenceNumber,
        let transferSize = downloadTransferSize {
        
        let fileClient = HotlineFileDownloadClient(address: address, port: UInt16(port), reference: referenceNumber, size: UInt32(transferSize))
        fileClient.delegate = self
        self.downloads.append(fileClient)
        
        let transfer = TransferInfo(id: referenceNumber, title: fileName, size: UInt(transferSize))
        transfer.downloadCallback = callback
        transfer.progressCallback = progressCallback
        self.transfers.append(transfer)
        
        fileClient.start(to: fileURL)
      }
    }
  }
  
  @MainActor func uploadFile(url fileURL: URL, path: [String], complete callback: ((TransferInfo) -> Void)? = nil) {
    let fileName = fileURL.lastPathComponent
    
    guard fileURL.isFileURL, !fileName.isEmpty else {
      print("NOT A FILE URL?")
      return
    }
    
    let filePath = fileURL.path(percentEncoded: false)
    
    var fileIsDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: filePath, isDirectory: &fileIsDirectory),
          fileIsDirectory.boolValue == false else {
      print("FILE IS A DIRECTORY?")
      return
    }
    
    var fileSize: UInt = 0
    
    // Data size
    let fileAttributes = try? FileManager.default.attributesOfItem(atPath: filePath)
    if let sizeAttribute = fileAttributes?[.size] as? NSNumber {
      print("DATA SIZE \(sizeAttribute.uintValue)")
      fileSize += sizeAttribute.uintValue
    }
    
    // Resource size
    let resourceURL = fileURL.appendingPathComponent("..namedfork/rsrc")
    
    
    print("RESOURCE PATH \(resourceURL)")
    let resourceAttributes = try? FileManager.default.attributesOfItem(atPath: resourceURL.path(percentEncoded: false))
    if let sizeAttribute = resourceAttributes?[.size] as? NSNumber {
      print("RESOURCE SIZE \(sizeAttribute.uintValue)")
      fileSize += sizeAttribute.uintValue
    }
    
    print("FILE SIZE? \(fileSize)")
    
    guard fileSize > 0 else {
      print("FILE IS EMPTY??")
      return
    }
    
    print("FILE SIZE: \(fileSize) NAME: \(fileName) PATH: \(path)")
    
    self.client.sendUploadFile(name: fileName, path: path) { [weak self] success, uploadReferenceNumber in
      print("UPLOAD REFERENCE: \(String(describing: uploadReferenceNumber))")
      
      if let self = self,
         let address = self.server?.address,
         let port = self.server?.port,
         let referenceNumber = uploadReferenceNumber,
         let fileClient = HotlineFileUploadClient(upload: fileURL, address: address, port: UInt16(port), reference: referenceNumber) {
        
        print("GOING TO UPLOAD")
        
        fileClient.delegate = self
        self.downloads.append(fileClient)
        
        let transfer = TransferInfo(id: referenceNumber, title: fileName, size: fileSize)
        transfer.uploadCallback = callback
        self.transfers.append(transfer)
        
        fileClient.start()
      }
    }
    
  }
    
  @MainActor func getFileDetails(_ fileName: String, path: [String]) async -> FileDetails? {
    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }
    
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendGetFileInfo(name: fileName, path: fullPath) { info in
        continuation.resume(returning: info)
      }
    }
  }
  
  @MainActor func deleteFile(_ fileName: String, path: [String]) async -> Bool {
    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }
    
    return await withCheckedContinuation { [weak self] continuation in
      self?.client.sendDeleteFile(name: fileName, path: fullPath) { success in
        continuation.resume(returning: success)
      }
    }
  }
  
  @MainActor func previewFile(_ fileName: String, path: [String], complete callback: ((PreviewFileInfo?) -> Void)? = nil) {
    var fullPath: [String] = []
    if path.count > 1 {
      fullPath = Array(path[0..<path.count-1])
    }
    
    self.client.sendDownloadFile(name: fileName, path: fullPath, preview: true) { [weak self] success, downloadReferenceNumber, downloadTransferSize, downloadFileSize, downloadWaitingCount in
      guard success else {
        callback?(nil)
        return
      }
      
      print("GOT DOWNLOAD REPLY:")
      print("SUCCESS?", success)
      print("TRANSFER SIZE: \(downloadTransferSize.debugDescription)")
      print("FILE SIZE: \(downloadFileSize.debugDescription)")
      print("REFERENCE NUM: \(downloadReferenceNumber.debugDescription)")
      print("WAITING COUNT: \(downloadWaitingCount.debugDescription)")
      
      var info: PreviewFileInfo? = nil
      
      if
        let address = self?.server?.address,
        let port = self?.server?.port,
        let referenceNumber = downloadReferenceNumber,
        let transferSize = downloadTransferSize {
        
        info = PreviewFileInfo(id: referenceNumber, address: address, port: port, size: transferSize, name: fileName)
      }
      
      callback?(info)
    }
  }
  
  @MainActor func deleteTransfer(id: UInt32) {
    if let b = self.bannerClient, b.referenceNumber == id {
      b.cancel()
      self.bannerClient = nil
      return
    }
    
    if let i = self.transfers.firstIndex(where: { $0.id == id }) {
      self.transfers.remove(at: i)
    }
    
    if let i = self.downloads.firstIndex(where: { $0.referenceNumber == id }) {
      let fileClient = self.downloads.remove(at: i)
      fileClient.cancel()
    }
  }
  
  @MainActor func deleteAllTransfers() {
    self.transfers = []
    
    let downloads = self.downloads
    self.downloads = []
    
    for fileClient in downloads {
      fileClient.cancel()
    }
  }
  
  @MainActor func downloadBanner(force: Bool = false) {
    guard self.serverVersion >= 150 else {
      return
    }
    
    if self.bannerClient != nil || force {
      self.bannerClient?.delegate = nil
      self.bannerClient?.cancel()
      self.bannerClient = nil
      
      if force {
        self.bannerImage = nil
      }
    }
    
    if self.bannerImage != nil {
      return
    }
    
    self.client.sendDownloadBanner { [weak self] success, downloadReferenceNumber, downloadTransferSize in
      if !success {
        return
      }
      
      if
        let self = self,
        let address = self.server?.address,
        let port = self.server?.port,
        let referenceNumber = downloadReferenceNumber,
        let transferSize = downloadTransferSize {
        self.bannerClient = HotlineFilePreviewClient(address: address, port: UInt16(port), reference: referenceNumber, size: UInt32(transferSize))
        self.bannerClient?.delegate = self
        self.bannerClient?.start()
      }
    }
  }
  
  // MARK: - Hotline Delegate
  
  @MainActor func hotlineStatusChanged(status: HotlineClientStatus) {
    print("Hotline: Connection status changed to: \(status)")
    
    if status == .disconnected {
      self.serverVersion = 123
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
        b.cancel()
        self.bannerClient = nil
      }
      
      self.deleteAllTransfers()
    }
    else if status == .loggedIn {
      if Prefs.shared.playSounds && Prefs.shared.playLoggedInSound {
        SoundEffectPlayer.shared.playSoundEffect(.loggedIn)
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
    
  func hotlineReceivedNewsPost(message: String) {
    let messageBoardRegex = /([\s\r\n]*[_\-]+[\s\r\n]+)/
    let matches = message.matches(of: messageBoardRegex)

    if matches.count == 1 {
      let range = matches[0].range
      self.messageBoard.insert(String(message[message.startIndex..<range.lowerBound]), at: 0)
    } else {
      self.messageBoard.insert(message, at: 0)
    }
    
    SoundEffectPlayer.shared.playSoundEffect(.newNews)
  }
  
  func hotlineReceivedServerMessage(message: String) {
    if Prefs.shared.playChatSound && Prefs.shared.playChatSound {
      SoundEffectPlayer.shared.playSoundEffect(.serverMessage)
    }
    
    print("Hotline: received server message:\n\(message)")
    self.chat.append(ChatMessage(text: message, type: .server, date: Date()))
  }
  
  func hotlineReceivedPrivateMessage(userID: UInt16, message: String) {
    if let existingUserIndex = self.users.firstIndex(where: { $0.id == UInt(userID) }) {
      let user = self.users[existingUserIndex]
      print("Hotline: received private message from \(user.name): \(message)")
      
      if Prefs.shared.playPrivateMessageSound && Prefs.shared.playPrivateMessageSound {
        if self.unreadInstantMessages[userID] == nil {
          SoundEffectPlayer.shared.playSoundEffect(.serverMessage)
        }
        else {
          SoundEffectPlayer.shared.playSoundEffect(.chatMessage)
        }
      }
      
      let instantMessage = InstantMessage(direction: .incoming, text: message.convertingLinksToMarkdown(), type: .message, date: Date())
      if self.instantMessages[userID] == nil {
        self.instantMessages[userID] = [instantMessage]
      }
      else {
        self.instantMessages[userID]!.append(instantMessage)
      }
      self.unreadInstantMessages[userID] = userID
    }
  }
  
  func hotlineReceivedChatMessage(message: String) {
    if Prefs.shared.playSounds && Prefs.shared.playChatSound {
      SoundEffectPlayer.shared.playSoundEffect(.chatMessage)
    }
    self.chat.append(ChatMessage(text: message, type: .message, date: Date()))
    self.unreadPublicChat = true
  }
  
  func hotlineReceivedUserList(users: [HotlineUser]) {
    var existingUserIDs: [UInt16] = []
    var userList: [User] = []
    
    for u in users {
      if let i = self.users.firstIndex(where: { $0.id == u.id }) {
        // If a user is already in the user list we have to assume
        // they changed somehow before we received the user list
        // which means let's keep their existing info.
        existingUserIDs.append(u.id)
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
      
      if Prefs.shared.showJoinLeaveMessages {
        self.chat.append(ChatMessage(text: "\(user.name) left", type: .status, date: Date()))
      }
      
      if Prefs.shared.playSounds && Prefs.shared.playLeaveSound {
        SoundEffectPlayer.shared.playSoundEffect(.userLogout)
      }
    }
  }
  
  func hotlineReceivedUserAccess(options: HotlineUserAccessOptions) {
    print("Hotline: got access options")
    HotlineUserAccessOptions.printAccessOptions(options)
    
    self.access = options
  }
  
  func hotlineReceivedErrorMessage(code: UInt32, message: String?) {
    print("Hotline: received error message \(code)", message.debugDescription)
    
    self.errorDisplayed = (message != nil) // Show error if there is a message to display.
    self.errorMessage = message
    
    if self.errorDisplayed,
       Prefs.shared.playSounds && Prefs.shared.playErrorSound {
      SoundEffectPlayer.shared.playSoundEffect(.error)
    }
  }
  
  // MARK: - Hotline Transfer Delegate
  
  func hotlineTransferStatusChanged(client: HotlineTransferClient, reference: UInt32, status: HotlineTransferStatus, timeRemaining: TimeInterval) {
    switch status {
    case .unconnected:
      break
    case .connecting:
      break
    case .connected:
      break
    case .progress(let progress):
      if let transfer = self.transfers.first(where: { $0.id == reference }) {
        transfer.progress = progress
        transfer.timeRemaining = timeRemaining
        transfer.progressCallback?(transfer, progress)
      }
    case .failed(_):
      if let i = self.downloads.firstIndex(where: { $0.referenceNumber == reference }) {
        self.downloads.remove(at: i)
      }
      if let transfer = self.transfers.first(where: { $0.id == reference }) {
        transfer.failed = true
        transfer.timeRemaining = 0.0
      }
      if let b = self.bannerClient, b.referenceNumber == reference {
        b.delegate = nil
        self.bannerClient = nil
      }
    case .completing:
      break
    case .completed:
      if let transfer = self.transfers.first(where: { $0.id == reference }) {
        transfer.completed = true
        transfer.timeRemaining = 0.0
      }
    }
  }
  
  func hotlineFileDownloadReceivedInfo(client: HotlineFileDownloadClient, reference: UInt32, info: HotlineFileInfoFork) {
    if let transfer = self.transfers.first(where: { $0.id == reference }) {
      transfer.title = info.name
    }
  }
  
  func hotlineFilePreviewComplete(client: HotlineFilePreviewClient, reference: UInt32, data: Data) {
    if let b = self.bannerClient, b.referenceNumber == reference {
      #if os(macOS)
      self.bannerImage = NSImage(data: data)
      #elseif os(iOS)
      self.bannerImage = UIImage(data: data)
      #endif
    }
    else
    if let i = self.transfers.firstIndex(where: { $0.id == reference }) {
      let transfer = self.transfers[i]
      transfer.previewCallback?(transfer, data)
      self.transfers.remove(at: i)
    }
    
    if let i = self.downloads.firstIndex(where: { $0.referenceNumber == reference }) {
      self.downloads.remove(at: i)
    }
  }
    
  func hotlineFileDownloadComplete(client: HotlineFileDownloadClient,  reference: UInt32, at: URL) {
    if let i = self.transfers.firstIndex(where: { $0.id == reference }) {
      let transfer = self.transfers[i]
      transfer.fileURL = at
      transfer.downloadCallback?(transfer, at)
      if Prefs.shared.playSounds && Prefs.shared.playFileTransferCompleteSound {
        SoundEffectPlayer.shared.playSoundEffect(.transferComplete)
      }
    }
    
    if let i = self.downloads.firstIndex(where: { $0.referenceNumber == reference }) {
      self.downloads.remove(at: i)
    }
  }
  
  func hotlineFileUploadComplete(client: HotlineFileUploadClient, reference: UInt32) {
    if let i = self.transfers.firstIndex(where: { $0.id == reference }) {
      let transfer = self.transfers[i]
      transfer.uploadCallback?(transfer)
      if Prefs.shared.playSounds && Prefs.shared.playFileTransferCompleteSound {
        SoundEffectPlayer.shared.playSoundEffect(.transferComplete)
      }
    }
    
    if let i = self.downloads.firstIndex(where: { $0.referenceNumber == reference }) {
      self.downloads.remove(at: i)
    }
  }
  
  // MARK: - Utilities
  
  func updateServerTitle() {
    self.serverTitle = self.serverName ?? self.server?.name ?? server?.address ?? "Server"
  }
  
  private func addOrUpdateHotlineUser(_ user: HotlineUser) {
    print("Hotline: users: \n\(self.users)")
    if let i = self.users.firstIndex(where: { $0.id == user.id }) {
      print("Hotline: updating user \(self.users[i].name)")
      self.users[i] = User(hotlineUser: user)
    }
    else {
      if !self.users.isEmpty {
        if Prefs.shared.playSounds && Prefs.shared.playJoinSound {
          SoundEffectPlayer.shared.playSoundEffect(.userLogin)
        }
      }
      
      print("Hotline: added user: \(user.name)")
      self.users.append(User(hotlineUser: user))
      if Prefs.shared.showJoinLeaveMessages {
        self.chat.append(ChatMessage(text: "\(user.name) joined", type: .status, date: Date()))
      }
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
    guard !path.isEmpty, !newsToSearch.isEmpty, let currentName = path.first else { return nil }
    
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
  
  private func findNewsArticle(id articleID: UInt32, at path: [String]) -> NewsInfo? {
    guard let parent = self.findNews(in: self.news, at: path), !parent.children.isEmpty else {
      return nil
    }
    
    return parent.children.first { child in
      guard let childArticleID = child.articleID else {
        return false
      }
              
      return child.type == .article && child.articleID == childArticleID
    }
  }
}
