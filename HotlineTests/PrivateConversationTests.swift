// PrivateConversationTests

import Testing
import Foundation
@testable import Hotline

/// Private conversations, which are with someone, not with the user ID the server gives them while
/// they're connected, so they wait while they're gone and go on once they're back.
struct PrivateConversationTests {
  private func user(_ id: UInt16, _ name: String, icon: UInt = 128) -> User {
    User(id: id, name: name, iconID: icon, status: [])
  }

  private func message(_ text: String, from name: String = "Bob", at date: Date = .now) -> InstantMessage {
    InstantMessage(direction: .incoming, senderName: name, text: text, type: .message, date: date, isRead: false)
  }

  /// With Bob here as user 5, and a message from him you haven't seen.
  private func withBob() -> PrivateConversations {
    var conversations = PrivateConversations()
    conversations.follow([self.user(5, "Bob")])
    conversations.file(self.message("Hi"), with: 5, name: "Bob", iconID: 128, unseen: true)
    return conversations
  }

  @Test func itWaitsWhileTheyreGone() throws {
    var conversations = self.withBob()
    conversations.follow([])
    let waiting = try #require(conversations[5])
    #expect(waiting.userID == nil)
    #expect(waiting.messages.map(\.text) == ["Hi"])
    #expect(waiting.unread == 1)
  }

  @Test func itGoesOnWhenTheyComeBack() throws {
    var conversations = self.withBob()
    let id = try #require(conversations[5]?.id)
    conversations.follow([])
    conversations.follow([self.user(9, "Bob", icon: 200)])
    let back = try #require(conversations[9])
    #expect(back.id == id)
    #expect(back.userID == 9)
    #expect(back.iconID == 200)
    #expect(back.unread == 1)
    // What had their old ID, like the notification of their message, still finds it.
    #expect(conversations[5]?.id == id)
  }

  @Test func theyCanGoAndComeBackBetweenOneUserListAndTheNext() throws {
    // As the list read again has it: their old ID gone, and their new one here, at once.
    var conversations = self.withBob()
    let id = try #require(conversations[5]?.id)
    conversations.follow([self.user(9, "Bob")])
    #expect(conversations[9]?.id == id)
  }

  @Test func someoneHereAllAlongDoesntTakeIt() {
    var conversations = PrivateConversations()
    conversations.follow([self.user(5, "guest"), self.user(9, "guest")])
    conversations.file(self.message("Hi", from: "guest"), with: 5, name: "guest", iconID: 128)
    conversations.follow([self.user(9, "guest")])
    #expect(conversations[9] == nil)
  }

  @Test func itFollowsThemThroughARename() {
    var conversations = self.withBob()
    conversations.follow([self.user(5, "Robert", icon: 200)])
    #expect(conversations[5]?.name == "Robert")
    #expect(conversations[5]?.iconID == 200)
    #expect(conversations[5]?.userID == 5)
  }

  @Test func someoneWhoComesBackUnnamedGetsItOnceTheyreNamed() throws {
    var conversations = self.withBob()
    let id = try #require(conversations[5]?.id)
    conversations.follow([])
    conversations.follow([self.user(9, "unnamed")])
    #expect(conversations[9] == nil)
    conversations.follow([self.user(9, "Bob")])
    #expect(conversations[9]?.id == id)
  }

  @Test func anIDGivenToSomeoneElseIsntTheirs() {
    var conversations = self.withBob()
    conversations.follow([])
    conversations.follow([self.user(5, "Alice")])
    #expect(conversations[5] == nil)
    // A message from her is her own.
    let hers = conversations.file(self.message("Hello", from: "Alice"), with: 5, name: "Alice", iconID: 128)
    #expect(hers.messages.map(\.text) == ["Hello"])
  }

  @Test func theLatestOfThoseWithTheirNameIsTheirs() throws {
    var conversations = PrivateConversations()
    conversations.follow([self.user(5, "guest"), self.user(6, "guest")])
    conversations.file(self.message("Earlier", from: "guest", at: .now.addingTimeInterval(-60)), with: 5, name: "guest", iconID: 128)
    conversations.file(self.message("Later", from: "guest"), with: 6, name: "guest", iconID: 128)
    let later = try #require(conversations[6]?.id)
    conversations.follow([])
    conversations.follow([self.user(9, "guest")])
    #expect(conversations[9]?.id == later)
  }

  @Test func oneWithNothingSaidIsntTakenUp() {
    var conversations = PrivateConversations()
    conversations.follow([self.user(5, "Bob")])
    _ = conversations.start(with: 5, name: "Bob", iconID: 128)
    conversations.follow([])
    conversations.follow([self.user(9, "Bob")])
    #expect(conversations[9] == nil)
  }

  /// One of yours to Bob, on its way.
  private func sent(_ text: String = "Hi", at date: Date = .now) -> InstantMessage {
    InstantMessage(direction: .outgoing, senderName: "macro", text: text, type: .message, date: date, isRead: false, delivery: .sending)
  }

  @Test func theServersAnswerSaysWhetherItGotToThem() {
    var conversations = self.withBob()
    let sent = self.sent()
    conversations.file(sent, with: 5, name: "Bob", iconID: 128)
    let delivered = conversations.deliver(sent.id, with: 5, as: .delivered)
    #expect(delivered?.delivery == .delivered)
    #expect(conversations[5]?.messages.last?.delivery == .delivered)
    // Said once, as a later answer, for a message sent again, is for that.
    let again = conversations.deliver(sent.id, with: 5, as: .unconfirmed)
    #expect(again == nil)
  }

  @Test func theyDontTakePrivateMessages() {
    // Said by the server whether it answers that it has it first, as the original server does, or
    // after, as Mobius does.
    for answeredFirst in [true, false] {
      var conversations = self.withBob()
      let sent = self.sent()
      conversations.file(sent, with: 5, name: "Bob", iconID: 128)
      if answeredFirst {
        conversations.deliver(sent.id, with: 5, as: .delivered)
      }
      let refused = conversations.refuse(latestTo: 5, reason: "Bob does not accept private messages.")
      #expect(refused?.id == sent.id)
      if !answeredFirst {
        conversations.deliver(sent.id, with: 5, as: .delivered)
      }
      #expect(conversations[5]?.messages.last?.delivery == .notDelivered("Bob does not accept private messages."), "answered first: \(answeredFirst)")
    }
  }

  @Test func aRefusalWithNothingJustSentStandsOnItsOwn() {
    var conversations = self.withBob()
    let withNothingSent = conversations.refuse(latestTo: 5, reason: "Bob does not accept private messages.")
    #expect(withNothingSent == nil)
    // Nor one of yours from long ago.
    var old = self.sent(at: .now.addingTimeInterval(-600))
    old.delivery = .delivered
    conversations.file(old, with: 5, name: "Bob", iconID: 128)
    let withOneLongAgo = conversations.refuse(latestTo: 5, reason: "Bob does not accept private messages.")
    #expect(withOneLongAgo == nil)
  }

  @Test func whetherItGotToThemIsSaved() {
    for delivery: InstantMessageDelivery in [.delivered, .unconfirmed, .notDelivered("Bob isn't on the server anymore."), .notDelivered(nil)] {
      #expect(InstantMessageDelivery(saved: delivery.saved, reason: delivery.reason) == delivery)
    }
    // On its way as it was saved, so its answer came to a visit that's over, if it came.
    #expect(InstantMessageDelivery(saved: "sending", reason: nil) == .unconfirmed)
    // From before it was asked.
    #expect(InstantMessageDelivery(saved: nil, reason: nil) == nil)
  }

  @Test func followingSaysWhetherAnythingChanged() {
    var conversations = self.withBob()
    let same = conversations.follow([self.user(5, "Bob")])
    #expect(!same)
    var idle = self.user(5, "Bob")
    idle.status = .idle
    let idled = conversations.follow([idle])
    #expect(!idled)
    let renamed = conversations.follow([self.user(5, "Robert")])
    #expect(renamed)
  }

  @Test @MainActor func whereTheyAreNow() {
    let hotline = HotlineState()
    hotline.users = [self.user(5, "Bob")]
    hotline.followConversations()
    hotline.conversations.file(self.message("Hi"), with: 5, name: "Bob", iconID: 128)
    #expect(hotline.currentUserID(of: 5) == 5)
    hotline.users = []
    hotline.followConversations()
    #expect(hotline.currentUserID(of: 5) == nil)
    hotline.users = [self.user(9, "Bob")]
    hotline.followConversations()
    #expect(hotline.currentUserID(of: 5) == 9)
    #expect(hotline.currentUserID(of: 9) == 9)
  }

  @Test @MainActor func whyItDidntGetToThem() {
    #expect(HotlineState.undeliveredReason(for: HotlineClientError.serverError(code: 1, message: "You are not allowed to send private messages."), to: "Bob") == "You are not allowed to send private messages.")
    // No answer, once they'd gone, as Mobius gives none for a user ID nobody has.
    #expect(HotlineState.undeliveredReason(for: HotlineClientError.timeout, to: "Bob") == "Bob isn't on the server anymore.")
    #expect(HotlineState.undeliveredReason(for: HotlineClientError.timeout, to: "") == "They aren't on the server anymore.")
    // Not known, as when the connection's lost.
    #expect(HotlineState.undeliveredReason(for: HotlineClientError.notConnected, to: "Bob") == nil)
  }

  @Test @MainActor func aMessageBeforeTheUserListWaitsForIt() {
    let hotline = HotlineState()
    hotline.heldUserEvents = []
    hotline.handlePrivateMessage(userID: 5, name: "Bob", message: "Hi")
    #expect(hotline.conversations[5] == nil)
    #expect(hotline.heldUserEvents?.count == 1)
  }
}
