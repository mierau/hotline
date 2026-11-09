// PresenceRuleTests

import Testing
import Foundation
@testable import Hotline

/// When Hotline tells a server you're here, so it doesn't say you're idle while you're at your Mac.
struct PresenceRuleTests {
  /// Its answer, `activity` seconds since the server last heard from you, and `input` since you
  /// last used the Mac.
  private func ask(_ rule: inout PresenceRule, activity: Int, input: Int, locked: Bool = false, idle: Bool = false) -> Bool {
    rule.saysHere(sinceActivity: .seconds(activity), sinceInput: .seconds(input), isLocked: locked, isIdle: idle)
  }

  @Test func notWhileTheServerIsHearingFromYou() {
    var rule = PresenceRule()
    let says = self.ask(&rule, activity: 60, input: 1)
    #expect(!says)
  }

  @Test func onceItsBeenAWhileAndYouveUsedTheMac() {
    var rule = PresenceRule()
    let says = self.ask(&rule, activity: 180, input: 10)
    #expect(says)
  }

  @Test func notOnceYouveSteppedAway() {
    var rule = PresenceRule()
    // Not used since the server last heard from you.
    let unused = self.ask(&rule, activity: 200, input: 250)
    #expect(!unused)
    // Used, then locked.
    let locked = self.ask(&rule, activity: 200, input: 5, locked: true)
    #expect(!locked)
  }

  @Test func whenYouComeBack() {
    var rule = PresenceRule()
    // Away, and the server says you're idle, as it should.
    let away = self.ask(&rule, activity: 310, input: 400, idle: true)
    #expect(!away)
    #expect(rule.interval == PresenceRule.usualInterval)
    // Back.
    let back = self.ask(&rule, activity: 900, input: 2, idle: true)
    #expect(back)
    #expect(rule.interval == PresenceRule.usualInterval)
  }

  @Test func notJustAfterYouDidSomething() {
    var rule = PresenceRule()
    // You've just said something there, and the server hasn't said you're not idle yet.
    let says = self.ask(&rule, activity: 5, input: 1, idle: true)
    #expect(!says)
  }

  @Test func onceForAServerThatDoesntCountIt() {
    var rule = PresenceRule()
    let away = self.ask(&rule, activity: 400, input: 500, idle: true)
    let back = self.ask(&rule, activity: 900, input: 2, idle: true)
    #expect(!away)
    #expect(back)
    // Still idle after it, which it leaves until the usual time.
    let soon = self.ask(&rule, activity: 45, input: 1, idle: true)
    let later = self.ask(&rule, activity: 120, input: 1, idle: true)
    let usual = self.ask(&rule, activity: 180, input: 1, idle: true)
    #expect(!soon)
    #expect(!later)
    #expect(usual)
    #expect(rule.interval == PresenceRule.usualInterval)
  }

  @Test func moreOftenForAQuickerServer() {
    var rule = PresenceRule()
    let before = self.ask(&rule, activity: 135, input: 5)
    #expect(!before)
    // Idle after two and a half minutes, while you're here.
    let idle = self.ask(&rule, activity: 150, input: 5, idle: true)
    #expect(idle)
    #expect(rule.interval == .seconds(90))
    let soon = self.ask(&rule, activity: 80, input: 3)
    let after = self.ask(&rule, activity: 95, input: 3)
    #expect(!soon)
    #expect(after)
  }

  @Test func neverMoreOftenThanAMinute() {
    var rule = PresenceRule()
    let says = self.ask(&rule, activity: 40, input: 1, idle: true)
    #expect(says)
    #expect(rule.interval == PresenceRule.shortestInterval)
  }
}
