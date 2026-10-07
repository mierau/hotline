import SwiftUI
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Message Board & News

extension HotlineState {

  // MARK: - Message Board

  /// Says in chat that someone posted to the board, and what about when Apple Intelligence can
  /// say, linking to the post. In the order they're posted, as saying what one's about takes a
  /// moment.
  func announceBoardPost(_ post: MessageBoardPost) {
    let previous = self.boardPostAnnouncement
    let link = self.boardLink(to: post)
    self.boardPostAnnouncement = Task { @MainActor [weak self] in
      // Long enough for the first one, while the model loads.
      let topic = await Self.boardPostTopic(post.body, within: .seconds(8))
      await previous?.value
      guard let self, !Task.isCancelled else {
        return
      }

      let name = post.username
      let about = topic.map { " about \($0)" } ?? ""
      var line = ChatMessage(text: "\(name ?? "Someone") posted to the board\(about)", type: .boardPost, date: Date())
      line.isAdmin = name.flatMap { name in self.users.first(where: { $0.name == name })?.isAdmin } ?? false
      if let link {
        line.metadata = ChatStore.EntryMetadata(link: link.absoluteString)
      }
      self.recordChatMessage(line)
    }
  }

  /// A hotline:// link to a post on this server's board.
  private func boardLink(to post: MessageBoardPost) -> URL? {
    guard let server = self.server else {
      return nil
    }
    var components = URLComponents()
    components.scheme = "hotline"
    components.host = server.address
    components.port = server.port == HotlinePorts.DefaultServerPort ? nil : server.port
    components.path = "/board"
    components.fragment = post.reference
    return components.url
  }

  /// What `boardPostTopic(_:)` comes up with in time, or nil.
  private static func boardPostTopic(_ body: String, within limit: Duration) async -> String? {
    final class Answer {
      var given = false
    }
    let answer = Answer()
    return await withCheckedContinuation { continuation in
      Task { @MainActor in
        let topic = await Self.boardPostTopic(body)
        if !answer.given {
          answer.given = true
          continuation.resume(returning: topic)
        }
      }
      Task { @MainActor in
        try? await Task.sleep(for: limit)
        if !answer.given {
          answer.given = true
          continuation.resume(returning: nil)
        }
      }
    }
  }

  /// A few words on what a post is about, from Apple Intelligence, or nil without it: on an older
  /// system, a Mac without it, or a post it won't or can't say anything about, like one too short
  /// to be about anything.
  private static func boardPostTopic(_ body: String) async -> String? {
    #if canImport(FoundationModels)
    guard #available(macOS 26.0, iOS 26.0, *) else {
      return nil
    }
    guard case .available = SystemLanguageModel.default.availability,
          body.split(whereSeparator: \.isWhitespace).count >= 4 else {
      return nil
    }
    // Finishing a sentence, it writes the words as the line needs them, names capitalized. Asked
    // for lowercase, it lowercases names too.
    let session = LanguageModelSession(instructions: """
      Finish the sentence about the message board post with two to five words. Answer with only \
      the words that finish it, without quotes or a period.
      """)
    do {
      // Posts can be long, and the start says what they're about.
      let prompt = "\(body.prefix(1500))\n\nThe post is about"
      let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.2, maximumResponseTokens: 24))
      return Self.topic(from: response.content)
    }
    catch {
      return nil
    }
    #else
    return nil
    #endif
  }

  /// The topic as the line has it: its first line, without quotes, an ending, or words from the
  /// question it sometimes says again, and with "A server outage" as "a server outage", or nil for
  /// nothing, or too much to be a topic.
  private static func topic(from answer: String) -> String? {
    var topic = answer.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    topic = topic.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"'“”‘’.!?:;")))
    topic = topic.replacing(/^(topic:\s*|((the|this) )?post (is |was )?about\s+|.*posted to the board about\s+|about\s+)/.ignoresCase(), with: "")
    if let first = topic.split(separator: " ").first, ["A", "An", "The"].contains(first) {
      topic = first.lowercased() + topic.dropFirst(first.count)
    }
    let words = topic.split(separator: " ")
    guard !words.isEmpty, words.count <= 8, topic.count <= 60 else {
      return nil
    }
    return words.joined(separator: " ")
  }

  @MainActor
  @discardableResult
  func getMessageBoard() async throws -> [MessageBoardPost] {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    let result = try await client.getMessageBoard()
    self.messageBoard = MessageBoardPost.adjustDates(result.posts.map { MessageBoardPost.parse($0) })
    self.messageBoardSignature = result.dividerSignature
    self.messageBoardLoaded = true
    return self.messageBoard
  }

  @MainActor
  func postToMessageBoard(text: String) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.postMessageBoard(text)
  }

  // MARK: - News

  @MainActor
  func getNewsList(at path: [String] = []) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    let parentNewsGroup = self.findNews(in: self.news, at: path)

    // Send a categories request for bundle paths or root (empty path)
    if path.isEmpty || parentNewsGroup?.type == .bundle {
      print("HotlineState: Requesting categories at: /\(path.joined(separator: "/"))")

      let categories = try await client.getNewsCategories(path: path)

      // Create info for each category returned
      var newCategoryInfos: [NewsInfo] = []

      // Transform hotline categories into NewsInfo objects
      for category in categories {
        var newsCategoryInfo = NewsInfo(hotlineNewsCategory: category)

        if let lookupPath = newsCategoryInfo.lookupPath {
          // Merge returned category info with existing category info
          if let existingCategoryInfo = self.newsLookup[lookupPath] {
            print("HotlineState: Merging category into existing category at \(lookupPath)")

            existingCategoryInfo.count = newsCategoryInfo.count
            existingCategoryInfo.name = newsCategoryInfo.name
            existingCategoryInfo.path = newsCategoryInfo.path
            existingCategoryInfo.categoryID = newsCategoryInfo.categoryID
            newsCategoryInfo = existingCategoryInfo
          } else {
            print("HotlineState: New category added at \(lookupPath)")
            self.newsLookup[lookupPath] = newsCategoryInfo
          }
        }

        newCategoryInfos.append(newsCategoryInfo)
      }

      if let parent = parentNewsGroup {
        parent.children = newCategoryInfos
      } else if path.isEmpty {
        self.newsLoaded = true
        self.news = newCategoryInfos
      }
    } else {
      print("HotlineState: Requesting articles at: /\(path.joined(separator: "/"))")

      let articles = try await client.getNewsArticles(path: path)

      print("HotlineState: Organizing news at \(path.joined(separator: "/"))")

      // Create info for each article returned
      var newArticleInfos: [NewsInfo] = []

      for article in articles {
        var newsArticleInfo = NewsInfo(hotlineNewsArticle: article)

        if let lookupPath = newsArticleInfo.lookupPath {
          // Merge returned category info with existing category info
          if let existingArticleInfo = self.newsLookup[lookupPath] {
            print("HotlineState: Merging article into existing article at \(lookupPath)")

            existingArticleInfo.count = newsArticleInfo.count
            existingArticleInfo.name = newsArticleInfo.name
            existingArticleInfo.path = newsArticleInfo.path
            existingArticleInfo.articleUsername = newsArticleInfo.articleUsername
            existingArticleInfo.articleDate = newsArticleInfo.articleDate
            existingArticleInfo.articleFlavors = newsArticleInfo.articleFlavors
            existingArticleInfo.articleID = newsArticleInfo.articleID
            newsArticleInfo = existingArticleInfo
          } else {
            print("HotlineState: New article added at \(lookupPath)")
            self.newsLookup[lookupPath] = newsArticleInfo
          }
        }

        newArticleInfos.append(newsArticleInfo)
      }

      let organizedNewsArticles: [NewsInfo] = self.organizeNewsArticles(newArticleInfos)
      if let parent = parentNewsGroup {
        parent.children = organizedNewsArticles
      }
    }
  }

  @MainActor
  func getNewsArticle(id articleID: UInt, at path: [String], flavor: String = "text/plain") async throws -> String? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    return try await client.getNewsArticle(id: UInt32(articleID), path: path, flavor: flavor)
  }

  @discardableResult
  @MainActor
  func postNewsArticle(title: String, body: String, at path: [String], parentID: UInt32 = 0) async throws -> NewsInfo? {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.postNewsArticle(title: title, text: body, path: path, parentID: parentID)
    print("HotlineState: News article posted")

    // Refresh article list and parent category count
    try await self.getNewsList(at: path)
    let parentPath = path.count > 1 ? Array(path.dropLast()) : [String]()
    try await self.getNewsList(at: parentPath)

    // Expand the category so the new post is visible
    if let category = self.findNews(in: self.news, at: path) {
      category.expanded = true

      // Find and expand the parent article if this is a reply, then return the new post
      if parentID != 0 {
        if let parentArticle = self.findArticle(id: UInt(parentID), in: category.children) {
          parentArticle.expanded = true
          // The reply should be in the parent's children — find by title
          return parentArticle.children.first { $0.name == title }
        }
      }
      else {
        // New top-level post — find by title among direct children
        return category.children.first { $0.name == title }
      }
    }

    return nil
  }

  private func findArticle(id: UInt, in items: [NewsInfo]) -> NewsInfo? {
    for item in items {
      if item.articleID == id {
        return item
      }
      if let found = self.findArticle(id: id, in: item.children) {
        return found
      }
    }
    return nil
  }

  @MainActor
  func newNewsFolder(name: String, path: [String] = []) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.newNewsFolder(name: name, path: path)
    try await self.getNewsList(at: path)
  }

  @MainActor
  func newNewsCategory(name: String, path: [String] = []) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.newNewsCategory(name: name, path: path)
    try await self.getNewsList(at: path)
  }

  @MainActor
  func deleteNewsItem(path: [String]) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    let parentPath = path.count > 1 ? Array(path.dropLast()) : [String]()
    try await client.deleteNewsItem(path: path)
    try await self.getNewsList(at: parentPath)
  }

  @MainActor
  func deleteNewsArticle(id: UInt, path: [String]) async throws {
    guard let client = self.client else {
      throw HotlineClientError.notConnected
    }

    try await client.deleteNewsArticle(id: UInt32(id), path: path)
    try await self.getNewsList(at: path)

    // Refresh parent level to update article counts
    let parentPath = path.count > 1 ? Array(path.dropLast()) : [String]()
    try await self.getNewsList(at: parentPath)
  }

  // MARK: - News Helpers

  func organizeNewsArticles(_ flatArticles: [NewsInfo]) -> [NewsInfo] {
    // Place articles under their parent
    var organized: [NewsInfo] = []
    for article in flatArticles {
      if let parentLookupPath = article.parentArticleLookupPath,
         let parentArticle = self.newsLookup[parentLookupPath] {
        if parentArticle.children.firstIndex(of: article) == nil {
          article.expanded = true
          parentArticle.children.append(article)
        }
      } else {
        organized.append(article)
      }
    }

    return organized
  }

  private func findNews(in newsToSearch: [NewsInfo], at path: [String]) -> NewsInfo? {
    guard !path.isEmpty, !newsToSearch.isEmpty, let currentName = path.first else { return nil }

    for news in newsToSearch {
      if news.name == currentName {
        if path.count == 1 {
          return news
        } else if !news.children.isEmpty {
          let remainingPath = Array(path[1...])
          return self.findNews(in: news.children, at: remainingPath)
        }
      }
    }

    return nil
  }
}
