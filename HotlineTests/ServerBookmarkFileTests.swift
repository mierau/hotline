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
}
