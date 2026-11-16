// NewsReadArticlesTests

import Testing
import Foundation
@testable import Hotline

/// The news articles read on each server, kept between visits, so only the ones you haven't read
/// show as unread when you're back.
struct NewsReadArticlesTests {
  /// A file in a scratch folder of its own, never the app's.
  private func makeFile() -> URL {
    URL.temporaryDirectory
      .appending(path: "NewsReadArticlesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      .appending(path: "Read News Articles.json", directoryHint: .notDirectory)
  }

  private let server = NewsReadArticles.server(address: "Hotline.example.com", port: 5500)
  private let posted = Date(timeIntervalSince1970: 1_790_000_000)

  @Test func readArticlesAreReadWhenYoureBack() {
    let file = self.makeFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let kept = NewsReadArticles(fileURL: file)
    kept.markRead(id: 2, posted: self.posted, in: "/General", on: self.server)
    kept.save()
    // Another time, from the file, with an article posted since.
    let again = NewsReadArticles(fileURL: file)
    let listed: [(id: UInt, posted: Date?)] = [(1, self.posted), (2, self.posted), (3, self.posted.addingTimeInterval(3600))]
    #expect(again.read(of: listed, in: "/General", on: self.server) == [2])
  }

  @Test func eachServerAndTopicHasItsOwn() {
    let kept = NewsReadArticles(fileURL: self.makeFile())
    kept.markRead(id: 2, posted: self.posted, in: "/General", on: self.server)
    let listed: [(id: UInt, posted: Date?)] = [(2, self.posted)]
    #expect(kept.read(of: listed, in: "/Releases", on: self.server).isEmpty)
    #expect(kept.read(of: listed, in: "/General", on: NewsReadArticles.server(address: "hotline.example.com", port: 5600)).isEmpty)
    // The same server, whatever its address's case.
    #expect(kept.read(of: listed, in: "/General", on: NewsReadArticles.server(address: "HOTLINE.EXAMPLE.COM", port: 5500)) == [2])
  }

  @Test func anArticleNumberedAgainIsntTakenForOneRead() {
    let kept = NewsReadArticles(fileURL: self.makeFile())
    kept.markRead(id: 2, posted: self.posted, in: "/General", on: self.server)
    // The server's news started over, and a new article numbered 2 was posted a month later.
    let renumbered: [(id: UInt, posted: Date?)] = [(2, self.posted.addingTimeInterval(30 * 24 * 60 * 60))]
    #expect(kept.read(of: renumbered, in: "/General", on: self.server).isEmpty)
    // And the one that was read is forgotten, as it's gone.
    let original: [(id: UInt, posted: Date?)] = [(2, self.posted)]
    #expect(kept.read(of: original, in: "/General", on: self.server).isEmpty)
  }

  @Test func aPostingTimeAnHourOffIsTheSameArticle() {
    let kept = NewsReadArticles(fileURL: self.makeFile())
    kept.markRead(id: 2, posted: self.posted, in: "/General", on: self.server)
    // As a server tells it in its own time zone, after daylight saving time starts or ends.
    let anHourOff: [(id: UInt, posted: Date?)] = [(2, self.posted.addingTimeInterval(3600))]
    #expect(kept.read(of: anHourOff, in: "/General", on: self.server) == [2])
    // Or without saying when.
    let unsaid: [(id: UInt, posted: Date?)] = [(2, nil)]
    #expect(kept.read(of: unsaid, in: "/General", on: self.server) == [2])
  }

  @Test func articlesNoLongerThereAreForgotten() {
    let file = self.makeFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
    let kept = NewsReadArticles(fileURL: file)
    kept.markRead(id: 1, posted: self.posted, in: "/General", on: self.server)
    kept.markRead(id: 2, posted: self.posted, in: "/General", on: self.server)
    // Article 1 was deleted from the server.
    let remaining: [(id: UInt, posted: Date?)] = [(2, self.posted)]
    #expect(kept.read(of: remaining, in: "/General", on: self.server) == [2])
    kept.save()
    let again = NewsReadArticles(fileURL: file)
    let both: [(id: UInt, posted: Date?)] = [(1, self.posted), (2, self.posted)]
    #expect(again.read(of: both, in: "/General", on: self.server) == [2])
  }

  @MainActor
  @Test func readingAnArticleKeepsItForItsServer() {
    let model = HotlineState()
    model.newsReadArticles = NewsReadArticles(fileURL: self.makeFile())
    model.server = Server(name: nil, description: nil, address: "Hotline.example.com", port: 5500)
    let article = NewsInfo(hotlineNewsArticle: HotlineNewsArticle(id: 7, parentID: 0, flags: 0, title: "Hello", username: "admin", date: self.posted, flavors: [("text/plain", 10)], path: ["General"]))
    model.markNewsArticleRead(article)
    #expect(article.read)
    let listed: [(id: UInt, posted: Date?)] = [(7, self.posted)]
    #expect(model.newsReadArticles.read(of: listed, in: "/General", on: self.server) == [7])
  }
}
