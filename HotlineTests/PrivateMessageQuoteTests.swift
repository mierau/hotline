// PrivateMessageQuoteTests

import Testing
import Foundation
@testable import Hotline

/// Replies to private messages, which quote what they're replies to, as the protocol has them, and
/// what the server says a private message is.
struct PrivateMessageQuoteTests {
  private func message(_ text: String) -> InstantMessage {
    InstantMessage(direction: .incoming, senderName: "Halcyon", text: text, type: .message, date: .now)
  }

  @Test func whatTheServerSaysItIs() {
    #expect(HotlinePrivateMessageKind(options: 1) == .message)
    #expect(HotlinePrivateMessageKind(options: nil) == .message)
    #expect(HotlinePrivateMessageKind(options: 2) == .refusedMessage)
    #expect(HotlinePrivateMessageKind(options: 3) == .refusedChat)
    #expect(HotlinePrivateMessageKind(options: 4) == .automaticResponse)
  }

  @Test func onlyWhatSomeoneWroteCanBeRepliedTo() {
    #expect(self.message("Hi").canBeRepliedTo)
    let automatic = InstantMessage(direction: .incoming, senderName: "Halcyon", text: "Out to lunch", type: .automaticResponse, date: .now)
    #expect(!automatic.canBeRepliedTo)
    let refusal = InstantMessage(direction: .incoming, senderName: "Halcyon", text: "Halcyon does not accept private messages.", type: .refusal, date: .now)
    #expect(!refusal.canBeRepliedTo)
  }

  @Test func aReplyQuotesAllOfAShortMessage() {
    #expect(InstantMessage.quote(of: "  Have you seen the **new** links?\n\n- one\n") == "Have you seen the **new** links?\n\n- one")
  }

  @Test func aReplyQuotesAsMuchOfALongOneAsTheServerKeeps() {
    let long = String(repeating: "é", count: 3_000)
    let quote = InstantMessage.quote(of: long)
    #expect(quote.utf8.count <= InstantMessage.maximumQuoteLength)
    #expect(long.hasPrefix(quote))
  }

  @Test func aQuoteIsOfTheMessageItSays() {
    let original = self.message("Have you seen the new links?\nThey're in Files.")
    // As it comes back from the server, with returns.
    #expect(original.isQuoted(by: "Have you seen the new links?\rThey're in Files.\r"))
    #expect(!original.isQuoted(by: "Have you seen the new links?"))
    #expect(!original.isQuoted(by: ""))
  }

  @Test func aQuoteCutShortIsOfTheMessageItStarts() {
    let original = self.message(String(repeating: "word ", count: 1_000))
    #expect(original.isQuoted(by: InstantMessage.quote(of: original.text)))
  }
}
