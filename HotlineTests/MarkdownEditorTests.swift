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

  /// An editor working through a text view styled as Markdown's shown where it's written, with
  /// `text` in it, and where `|` is, where you're typing. The coordinator styling it is kept with it.
  private func styledEditor(_ text: String) -> (MarkdownEditor, NSTextView, MarkdownTextCoordinator) {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
    textView.allowsUndo = true
    let editor = MarkdownEditor()
    let coordinator = MarkdownTextCoordinator(editor: editor)
    coordinator.attach(textView)
    let caret = text.range(of: "|")!
    textView.string = text.replacingOccurrences(of: "|", with: "")
    textView.setSelectedRange(NSRange(location: (String(text[..<caret.lowerBound]) as NSString).length, length: 0))
    return (editor, textView, coordinator)
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

  @Test func boldIsOnOnceItsPutOnAndUntilItsTakenOff() {
    let (editor, textView, _) = self.styledEditor("say hi| now")
    textView.setSelectedRange((textView.string as NSString).range(of: "hi"))
    #expect(!editor.isOn(.bold))
    editor.toggle(.bold)
    #expect(editor.isOn(.bold))
    #expect(editor.activeStyles == [.bold])
    editor.toggle(.bold)
    #expect(!editor.isOn(.bold))
    #expect(textView.string == "say hi now")
  }

  @Test func boldComesOffFromTheMiddleOfItsWords() {
    let (editor, textView, _) = self.styledEditor("say **hel|lo there** now")
    #expect(editor.isOn(.bold))
    #expect(!editor.isOn(.italic))
    editor.toggle(.bold)
    #expect(textView.string == "say hello there now")
    #expect(textView.selectedRange() == NSRange(location: 7, length: 0))
  }

  @Test func italicComesOffBoldItalicAndLeavesItBold() {
    let (editor, textView, _) = self.styledEditor("***bo|th***")
    #expect(editor.activeStyles == [.bold, .italic])
    editor.toggle(.italic)
    #expect(textView.string == "**both**")
  }

  @Test func whatsAfterTheMarksIsNotOn() {
    let (editor, _, _) = self.styledEditor("**hi**| there")
    #expect(!editor.isOn(.bold))
    #expect(editor.activeStyles.isEmpty)
  }

  @Test func codeComesOffFromInsideIt() {
    let (editor, textView, _) = self.styledEditor("run `ls| -la` now")
    #expect(editor.activeStyles == [.code])
    editor.toggle(.code)
    #expect(textView.string == "run ls -la now")
    #expect(!self.styledEditor("run `ls -la`| now").0.isOn(.code))
  }

  @Test func betweenABoldsClosingMarksNothingsOn() {
    let (editor, textView, _) = self.styledEditor("Where are we? Can we be **better*|*?")
    #expect(editor.activeStyles.isEmpty)
    // Italic here puts its marks in, and doesn't take the bold's away.
    editor.toggle(.italic)
    #expect(textView.string.hasPrefix("Where are we? Can we be **better*"))
    #expect(textView.string.hasSuffix("*?"))
  }

  @Test func betweenABoldsOpeningMarksNothingsOn() {
    #expect(self.styledEditor("*|*better** now").0.activeStyles.isEmpty)
  }

  @Test func marksWithNothingInThemYetAreOn() {
    let (editor, textView, _) = self.styledEditor("say **|** now")
    #expect(editor.activeStyles == [.bold])
    editor.toggle(.bold)
    #expect(textView.string == "say  now")
    #expect(textView.selectedRange() == NSRange(location: 4, length: 0))
    #expect(self.styledEditor("say ***|*** now").0.activeStyles == [.bold, .italic])
    #expect(self.styledEditor("say ~~|~~ now").0.activeStyles == [.strikethrough])
    #expect(self.styledEditor("say `|` now").0.activeStyles == [.code])
  }

  @Test func marksRightAfterAWordAreNotOn() {
    // As they wouldn't be shown as marks once something's typed in them.
    #expect(self.styledEditor("hello*|*").0.activeStyles.isEmpty)
  }

  @Test func betweenTwoCodeSpansIsNotCode() {
    #expect(self.styledEditor("`a`|`b`").0.activeStyles.isEmpty)
  }

  @Test func aHeadingIsNotBold() {
    #expect(self.styledEditor("# Hea|ding").0.activeStyles.isEmpty)
  }

  @Test func escapedMarksAreNotOn() {
    #expect(self.styledEditor("\\*\\*no|t\\*\\*").0.activeStyles.isEmpty)
  }

  @Test func strikethroughsMarksInBoldLeaveItBold() {
    #expect(self.styledEditor("**a ~~b~|~ c**").0.activeStyles == [.bold])
  }

  @Test func theEndOfABoldsMarksSelectedIsNotItalic() {
    let (editor, textView, _) = self.styledEditor("**better**|")
    textView.setSelectedRange(NSRange(location: 0, length: 9))
    #expect(!editor.isOn(.italic))
    textView.setSelectedRange(NSRange(location: 1, length: 8))
    #expect(!editor.isOn(.italic))
    // All of it, with its marks, is bold.
    textView.setSelectedRange(NSRange(location: 0, length: 10))
    #expect(editor.activeStyles == [.bold])
  }

  @Test func aLinkIsOnInsideIt() {
    let (editor, _, _) = self.styledEditor("see [the ne|ws](https://example.com)")
    #expect(editor.inLink)
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

  // MARK: Words Alone

  @Test func wordsAloneHaveNoListsQuotesOrImages() {
    let (editor, _) = self.editor("say hi", selecting: "hi")
    #expect(editor.allowsLines && editor.allowsImage)
    editor.allowsBlocks = false
    #expect(!editor.allowsLines)
    #expect(!editor.allowsImage)
    #expect(editor.allowsLink)
    #expect(editor.allows(.bold))
  }

  @Test func codeOverLinesIsCodeOnThemWhereLinesAreWords() {
    let (editor, textView) = self.editor("one\ntwo", selecting: "one\ntwo")
    editor.allowsBlocks = false
    editor.toggle(.code)
    #expect(textView.string == "`one\ntwo`")
  }
}
