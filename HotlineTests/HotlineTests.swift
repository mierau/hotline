// HotlineTests

import Testing
import Foundation
@testable import Hotline

struct HotlineTests {
}

struct ServerAddressTests {
  private func parsed(_ address: String) -> String {
    let server = Server.parseServerAddress(address)
    return "\(server.host) \(server.port) \(server.login ?? "-") \(server.password ?? "-")"
  }

  @Test func addressesAndPorts() {
    #expect(self.parsed("Hotline.Example.com") == "hotline.example.com 5500 - -")
    #expect(self.parsed(" hotline.example.com:5600 ") == "hotline.example.com 5600 - -")
    #expect(self.parsed("192.168.1.5:5500") == "192.168.1.5 5500 - -")
  }

  @Test func loginsAndPasswordsTypedWithTheAddress() {
    #expect(self.parsed("mars@hotline.example.com") == "hotline.example.com 5500 mars -")
    #expect(self.parsed("mars:secret@hotline.example.com:5600") == "hotline.example.com 5600 mars secret")
    #expect(self.parsed("mars:p@ss@hotline.example.com") == "hotline.example.com 5500 mars p@ss")
    #expect(self.parsed("@hotline.example.com") == "hotline.example.com 5500 - -")
  }

  @Test func links() {
    #expect(self.parsed("hotline://mars:secret@hotline.example.com:5501/files/Maps") == "hotline.example.com 5501 mars secret")
  }

  @Test func ipv6() {
    #expect(self.parsed("[fe80::1]:5600") == "fe80::1 5600 - -")
    #expect(self.parsed("fe80::1") == "fe80::1 5500 - -")
    #expect(self.parsed("mars:secret@[fe80::1]:5600") == "fe80::1 5600 mars secret")
  }

  @Test func addressAndPortLeavesTheLoginOut() {
    let (host, port) = Server.parseServerAddressAndPort("mars:secret@hotline.example.com:5600")
    #expect(host == "hotline.example.com" && port == 5600)
  }
}

@MainActor
struct ChatKeepingTests {
  private func line(_ type: ChatMessageType) -> ChatMessage {
    ChatMessage(text: "someone", type: type, date: Date())
  }

  @Test func eachKindIsKeptApart() {
    let chat = [self.line(.message), self.line(.joined), self.line(.message), self.line(.left), self.line(.joined), self.line(.message)]
    // The oldest message, and the oldest connection, go.
    #expect(HotlineState.trimmed(chat, to: 2)?.map(\.id) == Array(chat.suffix(4)).map(\.id))
    #expect(HotlineState.trimmed(chat, to: 3) == nil)
  }

  @Test func lotsOfConnectionsDontPushOutMessages() {
    let chat = [self.line(.message)] + Array(repeating: self.line(.joined), count: 3)
    // Only the oldest connection goes, and not the message before it.
    #expect(HotlineState.trimmed(chat, to: 2)?.map(\.id) == [chat[0], chat[2], chat[3]].map(\.id))
  }

  @Test func whatsOverGoesDownByABatch() {
    let chat = Array(repeating: self.line(.message), count: 5) + [self.line(.joined)]
    let trimmed = HotlineState.trimmed(chat, to: 4, batch: 2)
    #expect(trimmed?.filter { !$0.isConnection }.count == 2)
    #expect(trimmed?.filter(\.isConnection).count == 1)
  }
}

struct ChatHistoryRetentionTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  @Test func keepsChatForAsLongAsItSays() {
    #expect(ChatHistoryRetention.never.cutoff(from: self.now) == self.now)
    #expect(ChatHistoryRetention.day.cutoff(from: self.now) == Calendar.current.date(byAdding: .day, value: -1, to: self.now))
    #expect(ChatHistoryRetention.week.cutoff(from: self.now) == Calendar.current.date(byAdding: .day, value: -7, to: self.now))
    #expect(ChatHistoryRetention.year.cutoff(from: self.now) == Calendar.current.date(byAdding: .year, value: -1, to: self.now))
    #expect(ChatHistoryRetention.forever.cutoff(from: self.now) == nil)
  }

  @Test func keepingItForLessIsAskedAbout() {
    #expect(ChatHistoryRetention.forever.keepsMore(than: .month))
    #expect(ChatHistoryRetention.week.keepsMore(than: .never))
    #expect(!ChatHistoryRetention.day.keepsMore(than: .week))
    #expect(!ChatHistoryRetention.month.keepsMore(than: .month))
  }

  @Test func savedLinesAreFoundWithoutCase() {
    #expect(ChatStore.searchText(body: "ÉCLAIR time", username: "Mars") == "mars\néclair time")
    #expect(ChatStore.searchText(body: "files/My%20Maps/", username: nil).contains("my maps"))
    #expect(ChatStore.folded("Zoë") == "zoë")
  }
}
