// MessageBoardTests

import Testing
import Foundation
@testable import Hotline

struct MessageBoardTests {

  // MARK: - Divider Splitting (String-Based)

  @Test func dividerBetweenHeaderedPosts() {
    let text = "From Alice (Jan 1 12:00):\rPost one body\r_______________________________________________\rFrom Bob (Jan 2 12:00):\rPost two body"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 2)
    #expect(posts[0].hasPrefix("From Alice"))
    #expect(posts[1].hasPrefix("From Bob"))
  }

  @Test func embeddedTextDividerSplitsPosts() {
    let text = "From Alice (Jan 1 12:00):\rPost one\r_______________ [ higher intellect ] ___________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 2)
  }

  @Test func dashDividerSplitsPosts() {
    let text = "From Alice (Jan 1 12:00):\rPost one\r-----------------------------------------------\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 2)
  }

  @Test func multipleDividersSplitMultiplePosts() {
    let text = "From A (Jan 1 12:00):\rPost 1\r____________________\rFrom B (Jan 2 12:00):\rPost 2\r____________________\rFrom C (Jan 3 12:00):\rPost 3"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 3)
  }

  @Test func leadingDividerBeforeFirstPost() {
    let text = "____________________\rFrom Alice (Jan 1 12:00):\rPost after divider"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 1)
    #expect(posts[0].hasPrefix("From Alice"))
  }

  @Test func trailingDividerDiscarded() {
    let text = "From Alice (Jan 1 12:00):\rPost body\r_______________________________________________"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 1)
    #expect(!posts[0].contains("________"))
  }

  @Test func shortDividerNotSplit() {
    let text = "From Alice (Jan 1 12:00):\rPost one\r_____\rStill post one"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 1)
  }

  @Test func noDividerReturnsSinglePost() {
    let text = "Just a single post with no dividers"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 1)
    #expect(posts[0] == text)
  }

  @Test func emptyTextReturnsNoPosts() {
    let posts = HotlineClient.parseMessageBoard("").posts
    #expect(posts.isEmpty)
  }

  // MARK: - ASCII Art / False Divider Protection

  @Test func asciiArtUnderscoresDoNotSplitPost() {
    let text = """
    From Artist (Jan 1 12:00):\r\
    Check out my art:\r\
    _______________________________________________\r\
    |                                             |\r\
    |               HOTLINE ART                   |\r\
    |_____________________________________________|\r\
    _______________________________________________\r\
    From Bob (Jan 2 12:00):\r\
    Nice art!
    """
    let posts = HotlineClient.parseMessageBoard(text).posts
    // Pure dividers split even without a header, so the art box
    // becomes its own post between the two headered posts.
    #expect(posts.count == 3)
    #expect(posts[0].hasPrefix("From Artist"))
    #expect(posts[1].contains("HOTLINE ART"))
    #expect(posts[2].hasPrefix("From Bob"))
  }

  @Test func pureDividerSplitsWithoutHeader() {
    // Pure dividers (only separator chars) always split when there's content.
    let text = "From Alice (Jan 1 12:00):\rPart one\r_______________________________________________\rPart two is a separate post"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 2)
    #expect(posts[0].contains("Part one"))
    #expect(posts[1].contains("Part two"))
  }

  @Test func fromInBodyTextCausesSplitOnPureDivider() {
    // Pure dividers split unconditionally, so "From my perspective"
    // becomes its own post.
    let text = "From Alice (Jan 1 12:00):\rSome text\r_______________________________________________\rFrom my perspective, this is great.\r_______________________________________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 3)
    #expect(posts[0].contains("Some text"))
    #expect(posts[1].contains("From my perspective"))
    #expect(posts[2].hasPrefix("From Bob"))
  }

  @Test func headerlessPostsSplitOnPureDivider() {
    // Pure dividers split headerless posts into separate entries.
    let text = "From Alice (Jan 1 12:00):\rPost one\r_______________________________________________\rBookmark us: hotline.example.com\r_______________________________________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 3)
    #expect(posts[0].hasPrefix("From Alice"))
    #expect(posts[1].contains("Bookmark us"))
    #expect(posts[2].hasPrefix("From Bob"))
  }

  @Test func decoratedDividerSplitsPosts() {
    // Decorated dividers using the canonical separator char split posts.
    let text = "From Alice (Jan 1 12:00):\rPost one\r_______________ [ server name ] ___________________\rStill Alice's post"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 2)
    #expect(posts[0].contains("Post one"))
    #expect(posts[1] == "Still Alice's post")
  }

  @Test func nonCanonicalDividerKeptAsContent() {
    // A divider using a different separator char than the canonical one
    // is kept as post content.
    let text = "From Alice (Jan 1 12:00):\rPost one\r_______________________________________________\rFrom Bob (Jan 2 12:00):\rSome text\r-----------------------------------------------\rStill Bob's post"
    let posts = HotlineClient.parseMessageBoard(text).posts
    #expect(posts.count == 2)
    #expect(posts[0].hasPrefix("From Alice"))
    // The dash divider doesn't match the canonical underscore, so Bob's post stays intact
    #expect(posts[1].contains("-------"))
    #expect(posts[1].contains("Still Bob's post"))
  }

  // MARK: - Divider Signature Extraction

  @Test func dividerSignatureExtractedFromDecoratedDivider() {
    let text = "From Alice (Jan 1 12:00):\rPost one\r_______________ [ higher intellect ] ___________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let result = HotlineClient.parseMessageBoard(text)
    #expect(result.dividerSignature == "[ higher intellect ]")
  }

  @Test func dividerSignatureNilForPureDividers() {
    let text = "From Alice (Jan 1 12:00):\rPost one\r_______________________________________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let result = HotlineClient.parseMessageBoard(text)
    #expect(result.dividerSignature == nil)
  }

  @Test func dividerSignatureNilForNoDividers() {
    let text = "Just a single post"
    let result = HotlineClient.parseMessageBoard(text)
    #expect(result.dividerSignature == nil)
  }

  @Test func byteDataDividerSignatureExtracted() {
    let raw = "From Alice (Jan 1 12:00):\rPost one\r_______________ [ higher intellect ] ___________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let result = HotlineClient.parseMessageBoardData(Data(raw.utf8))
    #expect(result.dividerSignature == "[ higher intellect ]")
  }

  // MARK: - Byte-Level Divider Parsing (parseMessageBoardData)

  @Test func byteDataSplitsPosts() {
    let raw = "From Alice (Jan 1 12:00):\rPost one\r_______________________________________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 2)
    #expect(posts[0].hasPrefix("From Alice"))
    #expect(posts[1].hasPrefix("From Bob"))
  }

  @Test func byteDataEmbeddedTextDivider() {
    let raw = "From Alice (Jan 1 12:00):\rPost one\r_______________ [ higher intellect ] ___________________\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 2)
  }

  @Test func byteDataEmptyReturnsNoPosts() {
    let posts = HotlineClient.parseMessageBoardData(Data()).posts
    #expect(posts.isEmpty)
  }

  @Test func byteDataMixedEncodingPerPostDecoding() {
    // Post 1: UTF-8 "From A (Jan 1 12:00):\nTheBrick™" (™ = E2 84 A2)
    // Divider: 47 underscores
    // Post 2: Mac OS Roman "From B (Jan 2 12:00):\nHi™" (™ = AA)
    var data = Data()
    data.append(contentsOf: Array("From A (Jan 1 12:00):".utf8))
    data.append(0x0D) // \r
    data.append(contentsOf: [0x54, 0x68, 0x65, 0x42, 0x72, 0x69, 0x63, 0x6B, 0xE2, 0x84, 0xA2]) // TheBrick™ (UTF-8)
    data.append(0x0D) // \r
    data.append(contentsOf: Array(repeating: UInt8(0x5F), count: 47)) // _______________________________________________
    data.append(0x0D) // \r
    data.append(contentsOf: Array("From B (Jan 2 12:00):".utf8))
    data.append(0x0D) // \r
    data.append(contentsOf: [0x48, 0x69, 0xAA]) // Hi™ (Mac OS Roman)
    let posts = HotlineClient.parseMessageBoardData(data).posts
    #expect(posts.count == 2)
    #expect(posts[0].contains("TheBrick™"))
    #expect(posts[1].contains("Hi™"))
  }

  @Test func byteDataCRLFLineEndings() {
    let raw = "From Alice (Jan 1 12:00):\r\nPost one\r\n_______________________________________________\r\nFrom Bob (Jan 2 12:00):\r\nPost two"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 2)
  }

  @Test func byteDataPureDividerSplitsWithoutHeader() {
    let raw = "From Artist (Jan 1 12:00):\rMy art:\r_______________________________________________\rCool right?\r_______________________________________________\rFrom Bob (Jan 2 12:00):\rNice!"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 3)
    #expect(posts[0].hasPrefix("From Artist"))
    #expect(posts[1] == "Cool right?")
    #expect(posts[2].hasPrefix("From Bob"))
  }

  @Test func byteDataTrailingDividerDiscarded() {
    let raw = "From Alice (Jan 1 12:00):\rPost body\r_______________________________________________"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 1)
    #expect(!posts[0].contains("________"))
  }

  @Test func byteDataMacRomanUsernameInHeader() {
    // "Hålø" in Mac OS Roman: H=48, å=8C, l=6C, ø=9D
    var data = Data()
    data.append(contentsOf: Array("From Alice (Jan 1 12:00):".utf8))
    data.append(0x0D)
    data.append(contentsOf: Array("Hello from Sweden".utf8))
    data.append(0x0D)
    data.append(contentsOf: Array(repeating: UInt8(0x5F), count: 58))
    data.append(0x0D)
    // "From Hålø 8 (Aug09 21:49):" in Mac OS Roman
    data.append(contentsOf: [0x46, 0x72, 0x6F, 0x6D, 0x20]) // "From "
    data.append(contentsOf: [0x48, 0x8C, 0x6C, 0x9D, 0x20, 0x38]) // "Hålø 8"
    data.append(contentsOf: Array(" (Aug09 21:49):".utf8))
    data.append(0x0D)
    data.append(contentsOf: Array("Second post body".utf8))
    let posts = HotlineClient.parseMessageBoardData(data).posts
    #expect(posts.count == 2)
    #expect(posts[0].contains("Hello from Sweden"))
    #expect(posts[1].contains("Second post body"))
  }

  // MARK: - Header Parsing (Username + Date)

  @Test func standardHeaderWithColon() {
    let post = MessageBoardPost.parse("From eleisa (Thursday November 13, 2025 at 17:22 CET):\nSome message")
    #expect(post.username == "eleisa")
    #expect(post.body == "Some message")
    #expect(post.date != nil)
  }

  @Test func headerWithoutTrailingColon() {
    let post = MessageBoardPost.parse("From Px (Friday November 20, 2015 at 07:24)\nSome message")
    #expect(post.username == "Px")
    #expect(post.body == "Some message")
    #expect(post.date != nil)
  }

  @Test func compactDateHeader() {
    let post = MessageBoardPost.parse("From ONiX (Dec23 20:41):\nHello")
    #expect(post.username == "ONiX")
    #expect(post.date != nil)
    #expect(post.yearInferred == true)
  }

  @Test func unixStyleDateHeader() {
    let post = MessageBoardPost.parse("From TheMrKocour (Wed Nov 12 09:07:18 2025):\nContent here")
    #expect(post.username == "TheMrKocour")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
  }

  @Test func noSpaceBeforeParen() {
    let post = MessageBoardPost.parse("From 0x2400(Sun Mar  9 19:32:30 2025):\nTest")
    #expect(post.username == "0x2400")
    #expect(post.date != nil)
  }

  @Test func multiWordUsername() {
    let post = MessageBoardPost.parse("From Adam Hinkley (Nov04 12:05):\nHello")
    #expect(post.username == "Adam Hinkley")
    #expect(post.date != nil)
  }

  @Test func usernameWithParentheses() {
    let post = MessageBoardPost.parse("From Figgy (macOS 7) (Oct24 04:22):\nHello")
    #expect(post.username == "Figgy (macOS 7)")
    #expect(post.rawDateString == "Oct24 04:22")
    #expect(post.date != nil)
  }

  @Test func noHeaderReturnsBodyOnly() {
    let post = MessageBoardPost.parse("Just some text without a From header")
    #expect(post.username == nil)
    #expect(post.date == nil)
    #expect(post.body == "Just some text without a From header")
  }

  @Test func emptyBodyAfterHeader() {
    let post = MessageBoardPost.parse("From user (Feb 10 12:00):")
    #expect(post.username == "user")
    #expect(post.body == "")
  }

  @Test func bodyIsTrimmed() {
    // But for the spaces its first line starts with, which a drawing can start with.
    let post = MessageBoardPost.parse("From user (Feb 10 12:00):\n  \n  Hello world  \n  ")
    #expect(post.body == "  Hello world")
  }

  @Test func drawingKeepsItsFirstLinesSpaces() {
    let post = MessageBoardPost.parse("From user (Feb 10 12:00):\n   ___\n  / _ \\\n | (_) |\n  \\___/\n")
    #expect(post.body == "   ___\n  / _ \\\n | (_) |\n  \\___/")
  }

  @Test func referenceIsTheSameWithTheFirstLinesSpaces() {
    // As it was when the body was trimmed of them, so links made then still find the post.
    let post = MessageBoardPost.parse("From user (Feb 10 12:00):\n   ___\n  |_|")
    let trimmed = MessageBoardPost(username: "user", date: nil, rawDateString: "Feb 10 12:00", body: "___\n  |_|", yearInferred: false)
    #expect(post.reference == trimmed.reference)
  }

  @Test func bodyWithoutHeaderIsTrimmed() {
    let post = MessageBoardPost.parse("  \n  Just some text  \n  ")
    #expect(post.body == "Just some text")
  }

  // MARK: - Date Format Variants

  @Test func fullDateWithTimezone() {
    let post = MessageBoardPost.parse("From user (Tuesday February 17, 2026 at 18:37 CET):\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
  }

  @Test func fullDateWithoutTimezone() {
    let post = MessageBoardPost.parse("From user (Tuesday February 17, 2026 at 18:37):\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
  }

  @Test func dateWithCESTTimezone() {
    let post = MessageBoardPost.parse("From user (Saturday October 4, 2025 at 23:15 CEST):\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
  }

  @Test func shortMonthDayTimeNoYear() {
    let post = MessageBoardPost.parse("From user (Dec23 20:41):\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == true)
  }

  @Test func commaDelimitedDateWith12HourTime() {
    // "Friday, August 28, 2015, 9:34:22 PM"
    let post = MessageBoardPost.parse("From user (Friday, August 28, 2015, 9:34:22 PM)\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
    let components = Calendar.current.dateComponents([.year, .month, .day], from: post.date!)
    #expect(components.year == 2015)
    #expect(components.month == 8)
    #expect(components.day == 28)
  }

  @Test func commaDelimitedDateWithoutSeconds() {
    let post = MessageBoardPost.parse("From user (Friday, August 28, 2015, 9:34 PM)\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
  }

  @Test func slashDateWith12HourTime() {
    // "Sunday 27/Mar/2016 11:36:16 PM"
    let post = MessageBoardPost.parse("From user (Sunday 27/Mar/2016 11:36:16 PM)\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
    let components = Calendar.current.dateComponents([.year, .month, .day], from: post.date!)
    #expect(components.year == 2016)
    #expect(components.month == 3)
    #expect(components.day == 27)
  }

  @Test func slashDateWith24HourTime() {
    let post = MessageBoardPost.parse("From user (Sunday 27/Mar/2016 23:36:16)\nBody")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
  }

  @Test func dateOnlyFullMonth() {
    // "July 16, 2015" (after ordinal stripping from "July 16th, 2015")
    let post = MessageBoardPost.parse("From user (July 16, 2015)\nBody")
    #expect(post.date != nil)
    let components = Calendar.current.dateComponents([.year, .month, .day], from: post.date!)
    #expect(components.year == 2015)
    #expect(components.month == 7)
    #expect(components.day == 16)
  }

  @Test func ordinalSuffixStripped() {
    let post = MessageBoardPost.parse("From user (July 16th, 2015)\nBody")
    #expect(post.date != nil)
    let components = Calendar.current.dateComponents([.year, .month, .day], from: post.date!)
    #expect(components.month == 7)
    #expect(components.day == 16)
  }

  @Test func ordinalSuffixStNdRd() {
    let post1 = MessageBoardPost.parse("From user (January 1st, 2020)\nBody")
    #expect(post1.date != nil)
    let post2 = MessageBoardPost.parse("From user (January 2nd, 2020)\nBody")
    #expect(post2.date != nil)
    let post3 = MessageBoardPost.parse("From user (January 3rd, 2020)\nBody")
    #expect(post3.date != nil)
  }

  @Test func unparsableDateStoresRawString() {
    let post = MessageBoardPost.parse("From user (some garbage date):\nBody")
    #expect(post.date == nil)
    #expect(post.rawDateString == "some garbage date")
    #expect(post.username == "user")
  }

  // MARK: - Date Adjustment (Reverse Chronological Order)

  @Test func yearInferredDatesAdjustedToReverseOrder() {
    let post1 = MessageBoardPost(
      username: "A", date: makeDate(year: 2025, month: 8, day: 15),
      rawDateString: nil, body: "", yearInferred: false
    )
    let post2 = MessageBoardPost(
      username: "B", date: makeDate(year: 2026, month: 2, day: 8),
      rawDateString: nil, body: "", yearInferred: true
    )
    let adjusted = MessageBoardPost.adjustDates([post1, post2])
    #expect(adjusted[1].date! < adjusted[0].date!)
  }

  @Test func explicitYearDatesNotAdjusted() {
    let post1 = MessageBoardPost(
      username: "A", date: makeDate(year: 2025, month: 8, day: 15),
      rawDateString: nil, body: "", yearInferred: false
    )
    let post2 = MessageBoardPost(
      username: "B", date: makeDate(year: 2026, month: 1, day: 1),
      rawDateString: nil, body: "", yearInferred: false
    )
    let adjusted = MessageBoardPost.adjustDates([post1, post2])
    #expect(adjusted[1].date == post2.date)
  }

  @Test func adjustmentSkipsPostsWithoutDates() {
    let post1 = MessageBoardPost(
      username: "A", date: makeDate(year: 2025, month: 8, day: 15),
      rawDateString: nil, body: "", yearInferred: false
    )
    let post2 = MessageBoardPost(
      username: "B", date: nil,
      rawDateString: "bad date", body: "", yearInferred: false
    )
    let post3 = MessageBoardPost(
      username: "C", date: makeDate(year: 2026, month: 2, day: 8),
      rawDateString: nil, body: "", yearInferred: true
    )
    let adjusted = MessageBoardPost.adjustDates([post1, post2, post3])
    #expect(adjusted[2].date! < adjusted[0].date!)
  }

  // MARK: - Helpers

  private func makeDate(year: Int, month: Int, day: Int) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = 12
    components.timeZone = TimeZone.current
    return Calendar.current.date(from: components)!
  }
}
