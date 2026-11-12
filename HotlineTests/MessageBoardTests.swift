// MessageBoardTests

import Testing
import Foundation
@testable import Hotline

struct MessageBoardTests {

  // MARK: - Divider Splitting (String-Based)

  @Test func cancelOnlyAsksAboutWhatsBeenWritten() {
    #expect(!"".isWritten())
    #expect(!"  \n\t ".isWritten())
    #expect("hi".isWritten())
    // Not a quote it opened with, alone, but with something written after it.
    let quote = "> **Halcyon** wrote:\n> hello"
    #expect(!quote.isWritten(besides: quote))
    #expect(!(quote + "\n\n").isWritten(besides: quote))
    #expect((quote + "\n\nme too").isWritten(besides: quote))
  }

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

  @Test func byteDataShortLineOfSeparatorsNotSplit() {
    // An underline in a post, or a drawing's, as new posts keep them, rather than two posts.
    let divider = String(repeating: "_", count: 47)
    let raw = "From Alice (Jan 1 12:00):\rMy drawing:\r  _____\r |_____|\rStill Alice's post\r\(divider)\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 2)
    #expect(posts[0].contains("_____\n |_____|\nStill Alice's post"))
    #expect(posts[1].hasPrefix("From Bob"))
    // As long as new posts' dividers are, it's one.
    let eleven = "From Alice (Jan 1 12:00):\rPost one\r\(String(repeating: "_", count: 11))\rFrom Bob (Jan 2 12:00):\rPost two"
    #expect(HotlineClient.parseMessageBoardData(Data(eleven.utf8)).posts.count == 2)
  }

  // MARK: - Boards of Other Shapes

  @Test func serversOwnDelimiterSplitsPosts() {
    // As Mobius writes posts, with a NewsDelimiter of its own that isn't separators.
    let raw = "From macro (Oct11 16:09):\r\rFirst post\r\r• • • • •\rFrom Halcyon (Oct10 09:00):\r\rSecond post\r\r• • • • •\rFrom mars (Oct09 12:00):\r\rThird post\r\r• • • • •\r"
    let board = HotlineClient.parseMessageBoardData(Data(raw.utf8))
    #expect(board.posts.count == 3)
    #expect(board.posts.allSatisfy { !$0.contains("•") })
    #expect(board.posts[1].hasPrefix("From Halcyon"))
    #expect(board.delimiter == "• • • • •")
    #expect(board.dividerSignature == nil)
  }

  @Test func serversOwnDelimiterOverDrawingsOfSeparators() {
    // Lines like dividers in a post, but the server's own between posts.
    let art = String(repeating: "_", count: 20)
    let raw = "From Artist (Oct11 16:09):\r\(art)\r|  box  |\r\(art)\r#####\rFrom Bob (Oct10 09:00):\rNice\r#####\rFrom Carol (Oct09 09:00):\rAgreed\r#####"
    let board = HotlineClient.parseMessageBoardData(Data(raw.utf8))
    #expect(board.posts.count == 3)
    #expect(board.posts[0].contains("|  box  |") && board.posts[0].contains(art))
    #expect(board.delimiter == "#####")
  }

  @Test func postsWithNothingBetweenThemSplitAtTheirHeaders() {
    let raw = "From Alice (Jan 1 12:00):\rPost one\r\rFrom Bob (Jan 2 12:00):\rPost two\rthanks!\rFrom Carol (Jan 3 12:00):\rPost three"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 3)
    // Not a line of the server's own, as it's before only one of them.
    #expect(posts[1].hasSuffix("thanks!"))
  }

  @Test func signatureBeforeTheOnlyOtherPostIsKept() {
    let raw = "From Alice (Jan 1 12:00):\rPost one\r-- Alice\rFrom Bob (Jan 2 12:00):\rPost two"
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts.count == 2)
    #expect(posts[0].hasSuffix("-- Alice"))
  }

  @Test func boardWithNoShapeIsShownAsItIs() {
    let raw = "Welcome to the board!\rPost whatever you like.\r\rNo dividers here."
    let posts = HotlineClient.parseMessageBoardData(Data(raw.utf8)).posts
    #expect(posts == ["Welcome to the board!\nPost whatever you like.\n\nNo dividers here."])
    #expect(MessageBoardPost.parse(posts[0]).username == nil)
  }

  @Test func datesWithTabsAreRead() {
    let post = MessageBoardPost.parse("From Alice (Nov 12,\t2025\t17:22 CET):\nHello")
    #expect(post.date != nil)
    #expect(post.rawDateString == "Nov 12,\t2025\t17:22 CET")
  }

  @Test func isoDatesAreRead() {
    let post = MessageBoardPost.parse("From Alice (2026-11-12 15:04):\nHello")
    #expect(post.date != nil)
    #expect(post.yearInferred == false)
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

  // MARK: - The Same as the Patterns They Replaced, Quickly

  /// The patterns posts were read with before, which took minutes on lines of a few thousand
  /// characters, to check what reads them now says the same, on lines short enough for them.
  private static let dividerPattern = /^[ \t]*([_\-=~*]{15,}|[_\-=~*]{5,}.+[_\-=~*]{5,})[ \t]*$/
  private static let headerPattern = /^From\s+(.+)\s*\(([^)]+)\)\s*:?\s*$/

  /// Lines made of `pieces`, chosen at random, but the same each run.
  private func lines(of pieces: [String], count: Int, length: ClosedRange<Int>, prefix: String = "") -> [String] {
    var generator = SeededGenerator(seed: 2400)
    return (0..<count).map { _ in
      prefix + (0..<Int.random(in: length, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
    }
  }

  @Test func dividersAreTheSameAsThePatternFound() {
    let pieces = ["-", "-", "-", "_", "=", "~", "*", " ", "\t", "x", "é", "-\u{301}", "\u{2028}", "\u{A0}", "\n"]
    // And lines like dividers, around the lengths that make them ones.
    var generator = SeededGenerator(seed: 5500)
    func some(_ pieces: [String], _ count: ClosedRange<Int>) -> String {
      (0..<Int.random(in: count, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
    }
    let separators = ["-", "_", "=", "~", "*"]
    let between = ["x", " ", "\t", "é", "-\u{301}", "\u{2028}", "\u{A0}", "-", " News ", "\n"]
    let alike = (0..<30_000).map { _ in
      some([" ", "\t"], 0...2) + some(separators, 3...16) + some(between, 0...3) + some(separators, 3...7) + some([" ", "\t"], 0...2)
    }
    var dividers = 0
    for line in self.lines(of: pieces, count: 30_000, length: 0...24) + alike {
      let found = line.wholeMatch(of: Self.dividerPattern) != nil
      dividers += found ? 1 : 0
      #expect(HotlineClient.isMessageBoardDivider(Substring(line)) == found, "\(line.debugDescription)")
    }
    // Enough of each to tell.
    #expect(dividers > 5_000)
  }

  @Test func headersAreTheSameAsThePatternFound() {
    let pieces = [" ", " ", "\t", "(", "(", ")", ")", ":", "x", "y", "é", "\u{301}", "\u{2028}", "\u{A0}", "\u{0B}", "\n"]
    // And lines like headers, with what's around the name and date at their edges.
    var generator = SeededGenerator(seed: 5600)
    func some(_ pieces: [String], _ count: ClosedRange<Int>) -> String {
      (0..<Int.random(in: count, using: &generator)).map { _ in pieces.randomElement(using: &generator)! }.joined()
    }
    let spaces = [" ", " ", "\t", "\u{2028}", "\u{A0}"]
    let alike = (0..<30_000).map { _ in
      "From" + some(spaces, 0...3) + some(["x", "Figgy", " ", "(", ")", "é", "\u{0B}", ":"], 0...4) + some(spaces, 0...2)
        + some(["("], 0...2) + some(["Nov 12", "x", " ", "(", ")"], 0...3) + some([")"], 0...2) + some([" ", ":", "\t", "x"], 0...3)
    }
    let lines = self.lines(of: pieces, count: 30_000, length: 0...16, prefix: "From")
      + self.lines(of: pieces + ["F", "r", "o", "m"], count: 2_000, length: 0...12)
      + alike
    var headers = 0
    for line in lines {
      let found = Substring(line).wholeMatch(of: Self.headerPattern).map { (String($0.1), String($0.2)) }
      headers += found == nil ? 0 : 1
      let header = HotlineClient.messageBoardHeader(in: Substring(line))
      #expect(header?.name == found?.0 && header?.date == found?.1, "\(line.debugDescription)")
    }
    // Enough of each to tell.
    #expect(headers > 2_000)
  }

  @Test func cleanedIsTheSameAsBefore() {
    // As it was before, but for what it's still made from.
    func before(_ text: String) -> String {
      var lines = text.components(separatedBy: .newlines)
      while let first = lines.first, first.isBlank {
        lines.removeFirst()
      }
      return lines.joined(separator: "\n").replacing(/\s+\z/, with: "")
    }
    let pieces = ["a", "b", " ", " ", "\t", "\n", "\r", "\r\n", "\u{A0}", "\u{2028}", "\u{3000}", "\u{301}"]
    for text in self.lines(of: pieces, count: 20_000, length: 0...20) {
      #expect(MessageBoardPost.cleaned(text) == before(text), "\(text.debugDescription)")
    }
  }

  @Test func longLinesAreQuick() {
    let start = Date()
    let spaces = String(repeating: " ", count: 20_000)
    #expect(!HotlineClient.isMessageBoardDivider(Substring(String(repeating: "-", count: 20_000) + "\u{2028}" + String(repeating: "-", count: 20_000))))
    #expect(HotlineClient.messageBoardHeader(in: Substring("From" + spaces + "x")) == nil)
    #expect(HotlineClient.messageBoardHeader(in: Substring("From" + spaces + String(repeating: "(", count: 20_000) + "x)"))?.date == "x")
    #expect(MessageBoardPost.parse("From someone (Nov 12 12:00):\n" + spaces + "b" + spaces).body == spaces + "b")
    #expect(MessageBoardPost.cleaned(String(repeating: "\n", count: 20_000) + "a").count == 1)
    #expect(MessageBoardPost.parse("From x (" + String(repeating: "\t", count: 20_000) + "y):\nbody").username == "x")
    let posts = (0..<2_000).map { "From someone \($0) (Nov 12 12:00):\r" + spaces.prefix(2_000) + "\r#####\r" }.joined()
    #expect(HotlineClient.parseMessageBoardData(Data(posts.utf8)).posts.count == 2_000)
    // Each of these took minutes, or hours, before.
    #expect(Date().timeIntervalSince(start) < 2)
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

/// Random numbers that are the same each run, so a line that fails fails again.
private struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    self.state = seed
  }

  mutating func next() -> UInt64 {
    // SplitMix64
    self.state &+= 0x9E3779B97F4A7C15
    var z = self.state
    z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
    z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
    return z ^ (z >> 31)
  }
}
