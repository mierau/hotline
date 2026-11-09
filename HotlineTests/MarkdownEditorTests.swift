// MarkdownEditorTests

import Testing
import AppKit
@testable import Hotline

/// What the Format menu does to what's written: marks around what's selected, images, and lists
/// and quotes for whole lines, with what's selected after.
@MainActor
struct MarkdownEditorTests {
  /// An editor working through a text view with `text` in it, and `selected` selected in it, or
  /// where `|` is, which isn't kept.
  private func editor(_ text: String, selecting selected: String? = nil) -> (MarkdownEditor, NSTextView) {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    textView.allowsUndo = true
    let editor = MarkdownEditor()
    editor.textView = textView
    if let caret = text.range(of: "|"), selected == nil {
      let location = (String(text[..<caret.lowerBound]) as NSString).length
      textView.string = text.replacingOccurrences(of: "|", with: "")
      textView.setSelectedRange(NSRange(location: location, length: 0))
    }
    else {
      textView.string = text
      textView.setSelectedRange((text as NSString).range(of: selected ?? ""))
    }
    return (editor, textView)
  }

  private func selected(_ textView: NSTextView) -> String {
    (textView.string as NSString).substring(with: textView.selectedRange())
  }

  // MARK: Words

  @Test func boldGoesOnAndComesOff() {
    let (editor, textView) = self.editor("say hi now", selecting: "hi")
    editor.toggle(.bold)
    #expect(textView.string == "say **hi** now")
    #expect(self.selected(textView) == "hi")

    editor.toggle(.bold)
    #expect(textView.string == "say hi now")
    #expect(self.selected(textView) == "hi")
  }

  // MARK: Images

  @Test func anAddressBecomesAnImageNamedForItsFile() {
    let (editor, textView) = self.editor("look https://example.com/pics/cat.png", selecting: "https://example.com/pics/cat.png")
    editor.image()
    #expect(textView.string == "look ![cat](https://example.com/pics/cat.png)")
    #expect(self.selected(textView) == "cat")
  }

  @Test func wordsBecomeAnImageWithAnAddressToPasteOver() {
    let (editor, textView) = self.editor("a cat", selecting: "cat")
    editor.image()
    #expect(textView.string == "a ![cat](\(MarkdownEditor.imageAddress))")
    #expect(self.selected(textView) == MarkdownEditor.imageAddress)
  }

  @Test func anImageComesOffLeavingItsAddress() {
    let (editor, textView) = self.editor("look ![c|at](https://example.com/cat.png) here")
    editor.image()
    #expect(textView.string == "look https://example.com/cat.png here")
    #expect(self.selected(textView) == "https://example.com/cat.png")
  }

  // MARK: Lists and Quotes

  @Test func linesGoInABulletedListAndComeOut() {
    let text = "eggs\nmilk\nbread"
    let (editor, textView) = self.editor(text, selecting: text)
    editor.toggle(.bulletedList)
    #expect(textView.string == "- eggs\n- milk\n- bread")
    #expect(self.selected(textView) == "- eggs\n- milk\n- bread")

    editor.toggle(.bulletedList)
    #expect(textView.string == text)
  }

  @Test func aNumberedListCountsUpAndTakesOverABulletedOne() {
    let text = "- eggs\nmilk\n\n* bread"
    let (editor, textView) = self.editor(text, selecting: text)
    editor.toggle(.numberedList)
    // Lines with nothing on them stay as they are.
    #expect(textView.string == "1. eggs\n2. milk\n\n3. bread")
  }

  @Test func onlySomeLinesInTheListPutsTheRestInIt() {
    let text = "- eggs\nmilk"
    let (editor, textView) = self.editor(text, selecting: text)
    editor.toggle(.bulletedList)
    #expect(textView.string == "- eggs\n- milk")
  }

  @Test func aQuoteKeepsTheListInIt() {
    let text = "- eggs\n- milk"
    let (editor, textView) = self.editor(text, selecting: text)
    editor.toggle(.quote)
    #expect(textView.string == "> - eggs\n> - milk")

    // And a list in a quote is the list that changes.
    editor.toggle(.numberedList)
    #expect(textView.string == "> 1. eggs\n> 2. milk")

    editor.toggle(.quote)
    #expect(textView.string == "1. eggs\n2. milk")
  }

  @Test func whereYouAreTypingMovesWithTheWords() {
    let (editor, textView) = self.editor("first\nmi|lk\nlast")
    editor.toggle(.bulletedList)
    #expect(textView.string == "first\n- milk\nlast")
    #expect(textView.selectedRange() == NSRange(location: 6 + 4, length: 0))

    editor.toggle(.bulletedList)
    #expect(textView.string == "first\nmilk\nlast")
    #expect(textView.selectedRange() == NSRange(location: 6 + 2, length: 0))
  }

  @Test func anEmptyLineStartsAList() {
    let (editor, textView) = self.editor("eggs\n|")
    editor.toggle(.numberedList)
    #expect(textView.string == "eggs\n1. ")
    #expect(textView.selectedRange() == NSRange(location: 8, length: 0))
  }

  @Test func linesSelectedWithTheirLineBreakDoNotTakeTheNextLine() {
    let (editor, textView) = self.editor("eggs\nmilk\nbread", selecting: "eggs\nmilk\n")
    editor.toggle(.quote)
    #expect(textView.string == "> eggs\n> milk\nbread")
  }
}
