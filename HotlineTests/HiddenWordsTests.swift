// HiddenWordsTests

import Testing
import AppKit
@testable import Hotline

struct HiddenWordsTests {
  /// A word that shouldn't be written out here, from ROT13.
  private func decoded(_ rot13: String) -> String {
    String(String.UnicodeScalarView(rot13.unicodeScalars.map { scalar in
      switch scalar {
      case "a"..."m": Unicode.Scalar(scalar.value + 13)!
      case "n"..."z": Unicode.Scalar(scalar.value - 13)!
      default: scalar
      }
    }))
  }

  @Test func swearingShowsAsCartoonCursing() {
    let text = "get the fuck outta here"
    let hidden = HiddenWords.hidden(text)
    #expect(hidden.count == text.count)
    #expect(hidden.hasPrefix("get the "))
    #expect(hidden.hasSuffix(" outta here"))
    let cursing = hidden.dropFirst(8).prefix(4)
    #expect(cursing.last == "!")
    #expect(cursing.allSatisfy { "#$%@&*!".contains($0) }, "\(cursing)")
  }

  @Test func theSameWordCursesTheSameEachTime() {
    #expect(HiddenWords.hidden("fuck this").prefix(4) == HiddenWords.hidden("oh, fuck").suffix(4))
  }

  @Test func cursingNeverHasTheSameSymbolTwiceInARow() {
    for length in 1...16 {
      let cursing = Array(HiddenWords.grawlix(for: "word \(length)", length: length))
      #expect(cursing.count == length)
      #expect(zip(cursing, cursing.dropFirst()).allSatisfy { $0 != $1 }, "\(String(cursing))")
    }
  }

  @Test func slursShowAsDots() {
    let slur = self.decoded("snttbg")
    #expect(HiddenWords.hidden("what a \(slur), huh") == "what a ••••••, huh")
  }

  @Test func onlyWholeWordsAreHidden() {
    let text = "A classic Scunthorpe cocktail, to assess the bass in Dickens' passage, spicy as a cocoon."
    #expect(HiddenWords.hidden(text) == text)
  }

  @Test func stretchedAndStandInSpellingsAreHiddenToo() {
    for word in ["fuuuck", "sh1t", "$hit", "@sshole", "FUCKING", "Bullshit", "sh!t"] {
      let text = "oh \(word)?"
      let hidden = HiddenWords.hidden(text)
      #expect(!hidden.contains(word), "\(word) shows as \(hidden)")
      #expect(hidden.count == text.count)
    }
  }

  @Test func whatsSetOnTextStaysWhereItWas() throws {
    let link = try #require(URL(string: "https://example.com"))
    let text = NSMutableAttributedString(string: "this shit is linked")
    text.addAttribute(.link, value: link, range: NSRange(location: 5, length: 4))
    HiddenWords.hide(in: text)
    #expect(text.length == 19)
    #expect(!text.string.contains("shit"))
    #expect(text.attribute(.link, at: 5, effectiveRange: nil) as? URL == link)
    #expect(text.attribute(.link, at: 10, effectiveRange: nil) == nil)
  }

  @Test func chatHidesThemOnlyWhenAskedTo() {
    let message = ChatMessage(text: "Someone: well, shit", type: .message, date: Date())
    let shown = ChatMessageRenderer.render(message, options: ChatMessageRenderer.Options()).string
    #expect(shown.contains("shit"))
    let hidden = ChatMessageRenderer.render(message, options: ChatMessageRenderer.Options(hidesWords: true)).string
    #expect(!hidden.contains("shit"))
    // Which shows chat again, as it's drawn anew when what it's drawn with changes.
    #expect(ChatMessageRenderer.Options() != ChatMessageRenderer.Options(hidesWords: true))
  }
}
