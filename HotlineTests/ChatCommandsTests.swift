// ChatCommandsTests

import Testing
import Foundation
@testable import Hotline

/// Commands typed in chat: what's read as one, who a name is, where the caret is for the list above
/// the field, and what's said when something's wrong, without a server.
struct ChatCommandsTests {
  private func user(_ id: UInt16, _ name: String, status: UserStatus = []) -> User {
    User(id: id, name: name, iconID: 128, status: status)
  }

  /// Everyone here: Maria, Mac, Mac Guy, two guests, Rae, who takes no private messages or chats,
  /// and you, Sam.
  private var people: [User] {
    [
      self.user(1, "Maria"),
      self.user(2, "Mac"),
      self.user(3, "Mac Guy"),
      self.user(4, "guest"),
      self.user(5, "guest"),
      self.user(6, "Rae", status: [.refusePrivateMessages, .refusePrivateChat]),
      self.user(9, "Sam"),
    ]
  }

  private static let everything: HotlineUserAccessOptions = [.canSendChat, .canSendMessages, .canCreateChat, .canGetClientInfo, .canBroadcast, .canDisconnectUsers]

  /// In the public chat, or a private one with Maria in it, as you, with an account that can do
  /// whatever's given.
  private func context(privateChat: Bool = false, access: HotlineUserAccessOptions = Self.everything, away: Bool = false, reply: String = "") -> ChatCommandContext {
    var context = ChatCommandContext()
    context.privateChatID = privateChat ? 7 : nil
    context.members = privateChat ? [1, 9] : []
    context.access = access
    context.people = self.people
    context.ownUserID = 9
    context.automaticResponseOn = away
    context.automaticResponse = reply
    return context
  }

  private func problem(_ result: Result<ChatCommandRequest, ChatCommandProblem>) -> ChatCommandProblem? {
    if case .failure(let problem) = result {
      return problem
    }
    return nil
  }

  // MARK: Reading

  @Test func itReadsACommandByItsNameOrAnother() {
    #expect(ChatCommandInput("/me waves", in: self.context()) == .command(.me, arguments: "waves"))
    #expect(ChatCommandInput("/PM Maria hi there", in: self.context()) == .command(.msg, arguments: "Maria hi there"))
    #expect(ChatCommandInput("/afk", in: self.context()) == .command(.away, arguments: ""))
    #expect(ChatCommandInput("/me   waves  ", in: self.context()) == .command(.me, arguments: "waves"))
  }

  @Test func itSendsWhatIsntACommandAsItIs() {
    #expect(ChatCommandInput("hello", in: self.context()) == .message("hello"))
    #expect(ChatCommandInput("/Uploads is full", in: self.context()) == .message("/Uploads is full"))
    #expect(ChatCommandInput("/r/swift is fun", in: self.context()) == .message("/r/swift is fun"))
    #expect(ChatCommandInput("/ hi", in: self.context()) == .message("/ hi"))
  }

  @Test func itTakesOneSlashOffTwo() {
    #expect(ChatCommandInput("//me waves", in: self.context()) == .message("/me waves"))
  }

  @Test func itAsksAboutWhatCouldBeACommand() {
    #expect(ChatCommandInput("/mgs Maria hi", in: self.context()) == .unknown("mgs", suggestions: [.msg]))
    #expect(ChatCommandInput("/inv Maria", in: self.context()) == .unknown("inv", suggestions: [.invite]))
    #expect(ChatCommandInput("/m hi", in: self.context()) == .unknown("m", suggestions: [.me, .msg]))
    #expect(ChatCommandInput("/kik Mac", in: self.context()) == .unknown("kik", suggestions: [.kick]))
    #expect(ChatCommandInput("/help", in: self.context()) == .help)
  }

  @Test func itDoesntSuggestWhatYouCantRun() {
    #expect(ChatCommandInput("/broadcas hi", in: self.context(access: [.canSendChat])) == .message("/broadcas hi"))
    #expect(ChatCommandInput("/leav", in: self.context()) == .message("/leav"))
    #expect(ChatCommandInput("/leav", in: self.context(privateChat: true)) == .unknown("leav", suggestions: [.leave]))
  }

  @Test func aLetterOffIsOneMoreOneLessOneDifferentOrTwoSwapped() {
    #expect(ChatCommand.isALetterOff("mgs", "msg"))
    #expect(ChatCommand.isALetterOff("kik", "kick"))
    #expect(ChatCommand.isALetterOff("leave", "leve"))
    #expect(ChatCommand.isALetterOff("info", "inf0"))
    #expect(!ChatCommand.isALetterOff("me", "me"))
    #expect(!ChatCommand.isALetterOff("msg", "gsm"))
    #expect(!ChatCommand.isALetterOff("away", "a"))
  }

  // MARK: The List

  @Test func itListsWhatCanBeRunHere() {
    #expect(ChatCommand.matching("", in: self.context()) == [.me, .msg, .away, .rename, .icon, .invite, .info, .broadcast, .kick, .ban])
    #expect(ChatCommand.matching("", in: self.context(privateChat: true)) == [.me, .msg, .away, .rename, .icon, .invite, .topic, .leave, .info, .broadcast, .kick, .ban])
    #expect(ChatCommand.matching("", in: self.context(away: true)).contains(.back))
    #expect(ChatCommand.matching("", in: self.context(access: [.canSendChat])) == [.me, .away, .rename, .icon])
  }

  @Test func itListsWhatStartsWithWhatsTyped() {
    #expect(ChatCommand.matching("m", in: self.context()) == [.me, .msg])
    #expect(ChatCommand.matching("I", in: self.context()) == [.icon, .invite, .info])
    #expect(ChatCommand.matching("whois", in: self.context()) == [.info])
    #expect(ChatCommand.matching("nick", in: self.context()) == [.rename])
    #expect(ChatCommand.matching("x", in: self.context()).isEmpty)
  }

  @Test func itKnowsWhereTheCaretIs() {
    let context = self.context()
    #expect(ChatCommandPlace(text: "/m", caret: 2, in: context) == .name(typed: "m", range: NSRange(location: 1, length: 1)))
    #expect(ChatCommandPlace(text: "/", caret: 1, in: context) == .name(typed: "", range: NSRange(location: 1, length: 0)))
    #expect(ChatCommandPlace(text: "/msg Ma", caret: 7, in: context) == .person(.msg, typed: "Ma", range: NSRange(location: 5, length: 2)))
    #expect(ChatCommandPlace(text: "/msg ", caret: 5, in: context) == .person(.msg, typed: "", range: NSRange(location: 5, length: 0)))
    #expect(ChatCommandPlace(text: "/me wa", caret: 6, in: context) == .after(.me))
    #expect(ChatCommandPlace(text: "hello", caret: 5, in: context) == nil)
    #expect(ChatCommandPlace(text: "//me", caret: 4, in: context) == nil)
    #expect(ChatCommandPlace(text: "/msg Maria\nhi", caret: 13, in: context) == nil)
  }

  @Test func whoItsForIsTypedUntilItsAWholeNameAndASpace() {
    let context = self.context()
    #expect(ChatCommandPlace(text: "/msg Maria ", caret: 11, in: context) == .after(.msg))
    // Mac, though there's Mac Guy too.
    #expect(ChatCommandPlace(text: "/msg Mac ", caret: 9, in: context) == .after(.msg))
    #expect(ChatCommandPlace(text: "/msg Mac G", caret: 10, in: context) == .person(.msg, typed: "Mac G", range: NSRange(location: 5, length: 5)))
    // All of the name the caret's in, to put another in place of.
    #expect(ChatCommandPlace(text: "/msg Maria", caret: 7, in: context) == .person(.msg, typed: "Ma", range: NSRange(location: 5, length: 5)))
    // No one's name starts with it.
    #expect(ChatCommandPlace(text: "/msg Bob", caret: 8, in: context) == .after(.msg))
    // A word in a name.
    #expect(ChatCommandPlace(text: "/msg Gu", caret: 7, in: context) == .person(.msg, typed: "Gu", range: NSRange(location: 5, length: 2)))
  }

  @Test func itListsWhoNamesStartWithThenWhoHasAWordThatDoes() {
    let names = ChatCommand.people(matching: "gu", among: self.people).map(\.name)
    #expect(names == ["guest", "guest", "Mac Guy"])
    #expect(ChatCommand.people(matching: "", among: self.people).count == self.people.count)
  }

  @Test func itListsWhoseNameIsTypedFirst() {
    // Mac Guy spoke last, but it's Mac that's typed.
    let names = ChatCommand.people(matching: "mac", among: [self.user(3, "Mac Guy"), self.user(2, "Mac")]).map(\.name)
    #expect(names == ["Mac", "Mac Guy"])
  }

  @Test func itListsWhoACommandCanBeFor() {
    // You too, last.
    #expect(ChatCommand.msg.candidates(in: self.context()).map(\.id) == [1, 2, 3, 4, 5, 6, 9])
    #expect(ChatCommand.info.candidates(in: self.context()).contains { $0.id == 9 })
    #expect(!ChatCommand.kick.candidates(in: self.context()).contains { $0.id == 9 })
    let invitable = ChatCommand.invite.candidates(in: self.context(privateChat: true)).map(\.id)
    #expect(!invitable.contains(1) && !invitable.contains(9))
  }

  @Test func whoItsForIsTypedOneNameAfterAnotherForAnInvitation() {
    let context = self.context()
    #expect(ChatCommandPlace(text: "/invite ", caret: 8, in: context) == .person(.invite, typed: "", range: NSRange(location: 8, length: 0)))
    #expect(ChatCommandPlace(text: "/invite Maria Ma", caret: 16, in: context) == .person(.invite, typed: "Ma", range: NSRange(location: 14, length: 2)))
    #expect(ChatCommandPlace(text: "/invite Maria, Ma", caret: 17, in: context) == .person(.invite, typed: "Ma", range: NSRange(location: 15, length: 2)))
    // Still Maria, until there's a space after her.
    #expect(ChatCommandPlace(text: "/invite Maria", caret: 13, in: context) == .person(.invite, typed: "Maria", range: NSRange(location: 8, length: 5)))
    // Nothing typed after someone, which could be a subject.
    #expect(ChatCommandPlace(text: "/invite Maria ", caret: 14, in: context) == .after(.invite))
    #expect(ChatCommandPlace(text: "/invite Mac G", caret: 13, in: context) == .person(.invite, typed: "Mac G", range: NSRange(location: 8, length: 5)))
    #expect(ChatCommandPlace(text: "/invite Mac Maria", caret: 17, in: context) == .person(.invite, typed: "Maria", range: NSRange(location: 12, length: 5)))
    #expect(ChatCommandPlace(text: "/invite Maria Lunch pl", caret: 22, in: context) == .after(.invite))
  }

  @Test func itKnowsWhereAnIconsNumberIs() {
    let context = self.context()
    #expect(ChatCommandPlace(text: "/icon ", caret: 6, in: context) == .icon(typed: "", range: NSRange(location: 6, length: 0)))
    #expect(ChatCommandPlace(text: "/icon 14", caret: 8, in: context) == .icon(typed: "14", range: NSRange(location: 6, length: 2)))
    #expect(ChatCommandPlace(text: "/icon x", caret: 7, in: context) == .after(.icon))
  }

  // MARK: Who It's For

  @Test func itFindsTheLongestName() throws {
    let guy = try #require(ChatCommand.person(in: "Mac Guy hi there", among: self.people))
    #expect(guy.name == "Mac Guy" && guy.length == 7 && guy.rest == "hi there")
    let mac = try #require(ChatCommand.person(in: "mac hi", among: self.people))
    #expect(mac.name == "Mac" && mac.rest == "hi")
    let maria = try #require(ChatCommand.person(in: "Maria", among: self.people))
    #expect(maria.people.map(\.id) == [1] && maria.rest.isEmpty)
  }

  @Test func itTakesANameInQuotes() throws {
    let guy = try #require(ChatCommand.person(in: "\"mac guy\" hi", among: self.people))
    #expect(guy.name == "Mac Guy" && guy.length == 9 && guy.rest == "hi")
  }

  @Test func itNeedsAWholeName() {
    #expect(ChatCommand.person(in: "Mari hi", among: self.people) == nil)
    #expect(ChatCommand.person(in: "Mariana hi", among: self.people) == nil)
  }

  @Test func itTakesACommaAfterAName() throws {
    let maria = try #require(ChatCommand.person(in: "Maria, are you there?", among: self.people))
    #expect(maria.name == "Maria" && maria.length == 5 && maria.rest == "are you there?")
  }

  @Test func itFindsNamesOneAfterAnother() {
    let named = ChatCommand.names(in: "Maria, \"mac guy\" Mac Lunch plans", among: self.people)
    #expect(named.names.map(\.name) == ["Maria", "Mac Guy", "Mac"])
    #expect(named.names.map(\.range) == [NSRange(location: 0, length: 5), NSRange(location: 7, length: 9), NSRange(location: 17, length: 3)])
    #expect(named.restStart == 21)
  }

  // MARK: Running

  @Test func itSendsAPrivateMessage() {
    let result = ChatCommand.msg.request("Maria running late", in: self.context())
    guard case .success(.privateMessage(let user, let message)) = result else {
      Issue.record("Not a private message: \(result)")
      return
    }
    #expect(user.id == 1 && message == "running late")
  }

  @Test func itAsksWhichOfEveryoneWithTheNameItsFor() throws {
    let problem = try #require(self.problem(ChatCommand.msg.request("guest hi", in: self.context())))
    #expect(problem.message == "2 people are named “guest”. Choose one.")
    #expect(problem.people.map(\.id) == [4, 5] && problem.nameLength == 5)
    let chosen = ChatCommand.msg.request("guest hi", in: self.context(), chosen: [5])
    guard case .success(.privateMessage(let user, _)) = chosen else {
      Issue.record("Not a private message: \(chosen)")
      return
    }
    #expect(user.id == 5)
  }

  @Test func itSaysWhoIsntHere() throws {
    let problem = try #require(self.problem(ChatCommand.msg.request("Ma hi", in: self.context())))
    #expect(problem.message == "No one named “Ma” is here.")
    #expect(problem.people.map(\.name) == ["Maria", "Mac", "Mac Guy"] && problem.nameLength == 2)
    let noOne = try #require(self.problem(ChatCommand.info.request("", in: self.context())))
    #expect(noOne.message == "Type whose info to get after /info.")
  }

  @Test func itMessagesYouButNotSomeoneWhoDoesntTakeThem() throws {
    guard case .success(.privateMessage(let you, let message)) = ChatCommand.msg.request("Sam note to self", in: self.context()) else {
      Issue.record("Not a private message")
      return
    }
    #expect(you.id == 9 && message == "note to self")
    #expect(self.problem(ChatCommand.msg.request("Rae hi", in: self.context()))?.message == "Rae isn’t accepting private messages.")
    #expect(self.problem(ChatCommand.msg.request("Maria", in: self.context()))?.message == "Type a message for Maria after their name.")
    #expect(self.problem(ChatCommand.invite.request("Rae", in: self.context()))?.message == "Rae isn’t accepting private chat invitations.")
  }

  /// Who's invited, by their IDs, and the subject.
  private struct Invitation: Equatable {
    var people: [UInt16]
    var subject = ""
  }

  /// What /invite does with what's typed after it, when it's an invitation.
  private func invitation(_ arguments: String, privateChat: Bool = false, chosen: Set<UInt16> = []) -> Invitation? {
    if case .success(.invite(let people, let subject)) = ChatCommand.invite.request(arguments, in: self.context(privateChat: privateChat), chosen: chosen) {
      return Invitation(people: people.map(\.id), subject: subject)
    }
    return nil
  }

  @Test func itInvitesSeveralPeopleWithASubject() {
    #expect(self.invitation("Maria Mac Guy Lunch plans") == Invitation(people: [1, 3], subject: "Lunch plans"))
    #expect(self.invitation("Maria, Mac Guy") == Invitation(people: [1, 3]))
    #expect(self.invitation("Maria Mac") == Invitation(people: [1, 2]))
    #expect(self.invitation("\"Mac Guy\" Maria Maria") == Invitation(people: [3, 1]))
  }

  @Test func itStartsAChatWithNoOneButYou() {
    #expect(self.invitation("") == Invitation(people: []))
    #expect(self.invitation("Sam") == Invitation(people: []))
    #expect(self.invitation("Sam Lunch") == Invitation(people: [], subject: "Lunch"))
  }

  @Test func aWordThatIsntAfterANameIsntASubject() throws {
    let bob = try #require(self.problem(ChatCommand.invite.request("Bob", in: self.context())))
    #expect(bob.message == "No one named “Bob” is here." && bob.nameStart == 0 && bob.nameLength == 3)
    #expect(self.invitation("Maria Bob") == Invitation(people: [1], subject: "Bob"))
  }

  @Test func itAsksWhichGuestToInvite() throws {
    let problem = try #require(self.problem(ChatCommand.invite.request("Maria guest", in: self.context())))
    #expect(problem.message == "2 people are named “guest”. Choose one.")
    #expect(problem.people.map(\.id) == [4, 5] && problem.nameStart == 6 && problem.nameLength == 5)
    #expect(self.invitation("Maria guest", chosen: [5]) == Invitation(people: [1, 5]))
  }

  @Test func itInvitesOnlyWhoIsntInTheChat() throws {
    #expect(self.problem(ChatCommand.invite.request("Maria", in: self.context(privateChat: true)))?.message == "Maria is already in this chat.")
    #expect(self.problem(ChatCommand.invite.request("Sam", in: self.context(privateChat: true)))?.message == "You’re in this chat already.")
    #expect(self.invitation("Mac, Mac Guy", privateChat: true) == Invitation(people: [2, 3]))
    // No subject in a private chat, which has /topic.
    let bob = try #require(self.problem(ChatCommand.invite.request("Mac Bob", in: self.context(privateChat: true))))
    #expect(bob.message == "No one named “Bob” is here." && bob.nameStart == 4 && bob.nameLength == 3)
    // With no one, the sheet to choose from.
    guard case .success(.chooseWhoToInvite) = ChatCommand.invite.request("", in: self.context(privateChat: true)) else {
      Issue.record("Not the sheet")
      return
    }
  }

  @Test func itBansSomeoneButNotYou() {
    guard case .success(.ban(let user)) = ChatCommand.ban.request("Mac Guy", in: self.context()) else {
      Issue.record("Not a ban")
      return
    }
    #expect(user.id == 3)
    #expect(self.problem(ChatCommand.ban.request("Sam", in: self.context()))?.message == "That’s you.")
    #expect(self.problem(ChatCommand.ban.request("", in: self.context()))?.message == "Type who to ban after /ban.")
    #expect(self.problem(ChatCommand.ban.request("Mac", in: self.context(access: [.canSendChat])))?.message == "Your account can’t ban people.")
    guard case .success(.kick(let kicked)) = ChatCommand.kick.request("Mac", in: self.context()) else {
      Issue.record("Not a kick")
      return
    }
    #expect(kicked.id == 2)
  }

  @Test func itChangesYourNameAndIcon() {
    #expect(ChatCommandInput("/nick Sammy", in: self.context()) == .command(.rename, arguments: "Sammy"))
    guard case .success(.rename(let name)) = ChatCommand.rename.request("Sammy J", in: self.context()),
          case .success(.icon(let icon)) = ChatCommand.icon.request("141", in: self.context()) else {
      Issue.record("Not a name and an icon")
      return
    }
    #expect(name == "Sammy J" && icon == 141)
    #expect(self.problem(ChatCommand.rename.request("", in: self.context()))?.message == "Type your new name after /name.")
    #expect(self.problem(ChatCommand.icon.request("", in: self.context())) != nil)
    #expect(self.problem(ChatCommand.icon.request("abc", in: self.context())) != nil)
    #expect(self.problem(ChatCommand.icon.request("70000", in: self.context())) != nil)
  }

  @Test func awayRepliesWithWhatsTypedOrTheReplyYouHave() {
    guard case .success(.away(let typed)) = ChatCommand.away.request("brb", in: self.context(reply: "Back soon")),
          case .success(.away(let saved)) = ChatCommand.away.request("", in: self.context(reply: "Back soon")) else {
      Issue.record("Not away")
      return
    }
    #expect(typed == "brb" && saved == "Back soon")
    #expect(self.problem(ChatCommand.away.request("", in: self.context()))?.message == "Type what to reply with after /away, like “/away Back in 10”.")
    #expect(self.problem(ChatCommand.back.request("", in: self.context()))?.message == "Auto-reply is already off.")
  }

  @Test func onlyAPrivateChatCanBeLeftOrHaveASubject() {
    #expect(self.problem(ChatCommand.leave.request("", in: self.context())) != nil)
    #expect(self.problem(ChatCommand.topic.request("Plans", in: self.context())) != nil)
    #expect(self.problem(ChatCommand.leave.request("", in: self.context(privateChat: true))) == nil)
    #expect(self.problem(ChatCommand.broadcast.request("hi", in: self.context(access: [.canSendChat])))?.message == "Your account can’t broadcast.")
  }
}
