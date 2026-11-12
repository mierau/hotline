// ServerBookmarkFileTests

import Testing
import Foundation
@testable import Hotline

/// Server bookmark files someone's put up in a server's files: which are, and what they're called
/// as bookmarks.
struct ServerBookmarkFileTests {
  private func file(_ name: String, type: String) -> FileInfo {
    FileInfo(hotlineFile: HotlineFile(type: type, creator: "HTLC", fileSize: 460, fileName: name))
  }

  @Test func byTypeOrExtension() {
    #expect(self.file("The Mobius Strip", type: "HTbm").isServerBookmark)
    // From somewhere that doesn't keep types.
    #expect(self.file("Mobius.hlbm", type: "????").isServerBookmark)
    #expect(!self.file("README.md", type: "TEXT").isServerBookmark)
    #expect(!self.file("Bookmarks", type: "fldr").isServerBookmark)
  }

  @Test func namedWithoutTheirExtension() {
    #expect(self.file("The Mobius Strip", type: "HTbm").serverBookmarkName == "The Mobius Strip")
    #expect(self.file("Mobius.hlbm", type: "????").serverBookmarkName == "Mobius")
    #expect(self.file("Mobius.HLBM", type: "HTbm").serverBookmarkName == "Mobius")
  }

  @Test func theFilesDataIsTheBookmark() throws {
    let bookmark = Bookmark(type: .server, name: "Ignored", address: "mobius.trtphotl.com", port: 5500, login: "guest", password: "pw")
    let data = try #require(bookmark.bookmarkFileData())
    let read = try #require(Bookmark(fileData: data, name: "The Mobius Strip"))
    #expect(read.name == "The Mobius Strip")
    #expect(read.server?.address == "mobius.trtphotl.com")
    #expect(read.server?.port == 5500)
    #expect(read.server?.login == "guest")
  }

  @Test func aSecureBookmarksFileKeepsItsTLSPort() throws {
    let bookmark = Bookmark(type: .server, name: "The Mobius Strip", address: "mobius.trtphotl.com", port: 5500, tlsPort: 5600)
    let data = try #require(bookmark.bookmarkFileData())
    #expect(try #require(Bookmark(fileData: data)).tlsPort == 5600)
    // In the reserved bytes, after the magic and version.
    #expect(Array(data[6..<12]) == [0x54, 0x4C, 0x53, 0x20, 0x15, 0xE0])
  }

  @Test func filesStayTheShapeHotlinesOwnClientReads() throws {
    let bookmark = Bookmark(type: .server, name: "The Mobius Strip", address: "mobius.trtphotl.com", port: 5500, tlsPort: 5600, login: "guest", password: "pw")
    let data = try #require(bookmark.bookmarkFileData())
    // As long as the original's, with the login, password and address where it reads them.
    #expect(data.count == 460)
    #expect(Array(data[134..<136]) == [0, 5])
    #expect(String(decoding: data[136..<141], as: UTF8.self) == "guest")
    #expect(Array(data[202..<204]) == [0, 19])
    #expect(String(decoding: data[204..<223], as: UTF8.self) == "mobius.trtphotl.com")
  }

  @Test func otherFilesHaveNoTLSPort() throws {
    let bookmark = Bookmark(type: .server, name: "MacDomain", address: "hotline.system7today.com", port: 5500)
    let data = try #require(bookmark.bookmarkFileData())
    // All zero, as every other client leaves them.
    #expect(data[6..<134].allSatisfy { $0 == 0 })
    #expect(try #require(Bookmark(fileData: data)).tlsPort == nil)
  }

  @Test func longFieldsDontShiftTheRest() throws {
    let bookmark = Bookmark(type: .server, name: "Long", address: String(repeating: "a", count: 300) + ".com", port: 5500, login: String(repeating: "l", count: 40), password: String(repeating: "p", count: 40))
    let data = try #require(bookmark.bookmarkFileData())
    #expect(data.count == 460)
    #expect(Bookmark(fileData: data) != nil)
  }
}
