// ChatFormattingTests

import Testing
import AppKit
@testable import Hotline

/// Chat messages as chat shows them: who sent them, with their name and icon on the first line, and
/// what they said, in Markdown, as it's shown everywhere, lined up under it.
struct ChatFormattingTests {

  /// The paragraphs of a message as chat shows it, each with where its first line starts, and where
  /// its wrapped lines do.
  private func paragraphs(_ text: NSAttributedString) -> [(text: String, first: CGFloat, head: CGFloat)] {
    let string = text.string as NSString
    var paragraphs: [(String, CGFloat, CGFloat)] = []
    var start = 0
    while start < string.length {
      let range = string.paragraphRange(for: NSRange(location: start, length: 0))
      let style = text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
      paragraphs.append((string.substring(with: range).trimmingCharacters(in: .newlines), style?.firstLineHeadIndent ?? -1, style?.headIndent ?? -1))
      start = NSMaxRange(range)
    }
    return paragraphs
  }

  private func render(_ text: String, continuing: Bool = false) -> NSAttributedString {
    ChatMessageRenderer.render(ChatMessage(text: text, type: .message, date: Date()), continuing: continuing)
  }

  /// Where a message's lines start, after the icon, and its wrapped lines, further in.
  private let start = ChatMessageRenderer.textIndent
  private let wrapped = ChatMessageRenderer.textIndent + ChatMessageRenderer.hangingIndent

  @Test func plainTextIsUnchanged() {
    #expect(self.render("mars: just a plain message").string == "mars: just a plain message")
  }

  @Test func messagesAreMarkdown() {
    let text = self.render("mars: *italic*, **bold** and __underlined__")
    #expect(text.string == "mars: italic, bold and underlined")
    let underlined = (text.string as NSString).range(of: "underlined")
    #expect(text.attribute(.underlineStyle, at: underlined.location, effectiveRange: nil) != nil)
  }

  @Test func namesAreNeverMarkdown() {
    #expect(self.render("*mars*: hello").string == "*mars*: hello")
  }

  @Test func eachLineIsAParagraphUnderTheFirst() {
    let lines = self.paragraphs(self.render("mars: one\rtwo"))
    #expect(lines.map(\.text) == ["mars: one", "two"])
    #expect(lines[0].first == self.start && lines[0].head == self.wrapped)
    #expect(lines[1].first == self.wrapped)
  }

  @Test func quotesAndListsGoAfterTheName() {
    let quote = self.paragraphs(self.render("mars: > hack the planet\nyes"))
    #expect(quote.map(\.text) == ["mars:", "hack the planet", "yes"])
    #expect(quote[1].first == self.wrapped + Markdown.quoteIndent)
    let list = self.paragraphs(self.render("mars: - eggs\n- milk"))
    #expect(list.map(\.text) == ["mars:", "• eggs", "• milk"])
  }

  @Test func messageGoingOnStartsUnderTheOneBefore() {
    let lines = self.paragraphs(self.render("mars: more", continuing: true))
    #expect(lines.map(\.text) == ["more"])
    #expect(lines[0].first == self.wrapped)
  }

  @Test func codeBlockInAMessage() {
    let text = self.render("mars: ```lua\nprint(1)\n```\nthat's it")
    #expect(text.string == "mars: \nprint(1)\nthat's it")
    // Only the name's paragraph gets the icon.
    var sender = NSRange()
    _ = text.attribute(ChatMessageRenderer.senderNameKey, at: 0, longestEffectiveRange: &sender, in: NSRange(location: 0, length: text.length))
    #expect(sender == NSRange(location: 0, length: 7))
    let code = (text.string as NSString).range(of: "print")
    #expect(text.attribute(Markdown.codeLanguageKey, at: code.location, effectiveRange: nil) as? String == "lua")
    let style = text.attribute(.paragraphStyle, at: code.location, effectiveRange: nil) as? NSParagraphStyle
    #expect(style?.firstLineHeadIndent == self.wrapped + ChatMessageRenderer.codeBlockPadding.width)
  }

  @Test func codeBlockWithNoName() {
    #expect(self.render("```\nx\n```").string == "x")
  }

  @Test func namesSayWhoSentTheMessage() {
    var message = ChatMessage(text: "mars: hello", type: .message, date: Date())
    message.iconID = 129
    let text = ChatMessageRenderer.render(message)
    var range = NSRange()
    let name = text.attribute(ChatMessageRenderer.userNameKey, at: 0, longestEffectiveRange: &range, in: NSRange(location: 0, length: text.length)) as? String
    #expect(name == "mars")
    #expect(range == NSRange(location: 0, length: 4))
    #expect((text.attribute(ChatMessageRenderer.iconIDKey, at: 0, effectiveRange: nil) as? NSNumber)?.uintValue == 129)
    // Not the message, and not a message going on from the one before.
    #expect(text.attribute(ChatMessageRenderer.userNameKey, at: (text.string as NSString).range(of: "hello").location, effectiveRange: nil) == nil)
    let continuing = ChatMessageRenderer.render(message, continuing: true)
    var marked = false
    continuing.enumerateAttribute(ChatMessageRenderer.userNameKey, in: NSRange(location: 0, length: continuing.length)) { value, _, _ in
      marked = marked || value != nil
    }
    #expect(!marked)
  }

  @Test func classicLineBreaks() {
    #expect(self.render("\r mars:  ```\rone\rtwo\r```").string == "mars: \none\ntwo")
  }

  @Test func imagePreviewsUnderTheirLine() {
    var options = ChatMessageRenderer.Options()
    options.previewsImages = true
    let text = ChatMessageRenderer.render(ChatMessage(text: "mars: look https://example.com/cat.png", type: .message, date: Date()), options: options)
    #expect(text.string == "mars: look https://example.com/cat.png\u{2028}\u{FFFC}")
    options.previewsImages = false
    #expect(ChatMessageRenderer.render(ChatMessage(text: "mars: look https://example.com/cat.png", type: .message, date: Date()), options: options).string == "mars: look https://example.com/cat.png")
  }

  // MARK: Emotes

  @Test func emoteWithALinkIsAnEmote() {
    let message = ChatMessage(text: "\r *** macro what in the world https://apple.com okay", type: .message, date: Date())
    #expect(message.isEmote)
    #expect(message.username == nil)
    let text = ChatMessageRenderer.render(message)
    #expect(text.string == "macro what in the world https://apple.com okay")
    let link = text.attribute(.link, at: (text.string as NSString).range(of: "apple.com").location, effectiveRange: nil) as? URL
    #expect(link?.absoluteString == "https://apple.com")
  }

  @Test func messageWithALinkKeepsItsSender() {
    let message = ChatMessage(text: "macro: see https://apple.com", type: .message, date: Date())
    #expect(!message.isEmote)
    #expect(message.username == "macro")
    #expect(message.text == "see https://apple.com")
  }

  @Test func savedEmoteWithALinkIsPutBack() {
    // As one was saved before emotes were told apart first, split at the link's colon.
    let entry = ChatStore.Entry(id: UUID(), body: "//apple.com okay", username: "*** macro what in the world https", type: "message", date: Date())
    let message = ChatMessage(entry: entry)
    #expect(message?.isEmote == true)
    #expect(message?.text == "*** macro what in the world https://apple.com okay")
  }

  // MARK: Links to files

  @Test func linksToFoldersShowAFolder() {
    let text = ChatMessageRenderer.render(ChatMessage(text: "mars: see hotline://127.0.0.1:5500/files/Maps/Marathon/ and hotline://127.0.0.1:5500/files/Maps/Readme.txt", type: .message, date: Date()))
    var icons: [NSImage] = []
    text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length)) { value, _, _ in
      if let image = (value as? NSTextAttachment)?.image {
        icons.append(image)
      }
    }
    #expect(icons.count == 2)
    #expect(icons.first === Markdown.folderIcon)
    #expect(icons.last !== Markdown.folderIcon)
    #expect(text.string.contains("Marathon") && text.string.contains("Readme.txt") && !text.string.contains("hotline://"))
  }

  @Test func fileIconsHaveRoomAfterThem() {
    let text = ChatMessageRenderer.render(ChatMessage(text: "mars: see hotline://127.0.0.1:5500/files/Maps/Readme.txt", type: .message, date: Date()))
    let name = (text.string as NSString).range(of: "Readme.txt")
    let icon = text.attribute(.attachment, at: name.location - 1, effectiveRange: nil) as? NSTextAttachment
    // TextKit 2 doesn't kern attachments, so the room is part of the icon.
    #expect(icon?.bounds.width == 20)
    #expect(icon?.image?.size == NSSize(width: 20, height: 16))
  }

  // MARK: Highlighting

  private let lineBreak = "\n"

  /// The code in a block named `language`, with each colored run marked by what it is. ⏎ is a line
  /// break.
  private func colors(_ language: String, _ code: String) -> String {
    let text = Markdown.shownText("```\(language)\n\(code)\n```", layout: .board)
    let names: [(CodeHighlighter.Token, String)] = [(.keyword, "kw"), (.string, "str"), (.comment, "com"), (.number, "num"), (.type, "type")]
    var out = ""
    text.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: text.length)) { value, range, _ in
      let piece = (text.string as NSString).substring(with: range).replacingOccurrences(of: "\n", with: "⏎")
      if let name = names.first(where: { (value as AnyObject) === CodeHighlighter.color(for: $0.0) })?.1 {
        out += "{\(name):\(piece)}"
      }
      else {
        out += piece
      }
    }
    return out
  }

  @Test func highlightsLua() {
    #expect(colors("lua", "local s = \"hi\" .. [[long]] -- note\(lineBreak)--[[ block\(lineBreak)comment ]] return 0x1F")
      == "{kw:local} s = {str:\"hi\"} .. {str:[[long]]} {com:-- note}⏎{com:--[[ block⏎comment ]]} {kw:return} {num:0x1F}")
  }

  @Test func highlightsSwift() {
    #expect(colors("swift", "let x: Int = 42 // answer\(lineBreak)print(\"a \\\"b\\\" c\")")
      == "{kw:let} x: {type:Int} = {num:42} {com:// answer}⏎print({str:\"a \\\"b\\\" c\"})")
  }

  @Test func highlightsShell() {
    #expect(colors("bash", "echo ${#list[@]} # count\(lineBreak)export PATH=$HOME/bin")
      == "{kw:echo} ${#list[@]} {com:# count}⏎{kw:export} PATH={type:$HOME}/bin")
  }

  @Test func highlightsSQLWhateverTheCase() {
    #expect(colors("sql", "SELECT name FROM users WHERE id = 1 -- first")
      == "{kw:SELECT} name {kw:FROM} users {kw:WHERE} id = {num:1} {com:-- first}")
  }

  @Test func highlightsC() {
    #expect(colors("c", "#include <stdio.h>\(lineBreak)int main(void) { return 0; } /* done */")
      == "{kw:#include <stdio.h>}⏎{kw:int} main({kw:void}) { {kw:return} {num:0}; } {com:/* done */}")
  }

  @Test func highlightsPerl() {
    #expect(colors("perl", "my $name = \"hi\"; # greet\(lineBreak)print $#list")
      == "{kw:my} {type:$name} = {str:\"hi\"}; {com:# greet}⏎{kw:print} $#list")
  }

  @Test func highlightsYAMLKeys() {
    #expect(colors("yaml", "server:\(lineBreak)  name: \"Hotline\" # mine\(lineBreak)  users:\(lineBreak)    - name: mars\(lineBreak)  enabled: yes\(lineBreak)  url: http://example.com/a:b")
      == "{type:server}:⏎  {type:name}: {str:\"Hotline\"} {com:# mine}⏎  {type:users}:⏎    - {type:name}: mars⏎  {type:enabled}: {kw:yes}⏎  {type:url}: http://example.com/a:b")
  }

  @Test func highlightsTOMLAndINISections() {
    #expect(colors("toml", "[server]\(lineBreak)port = 5500 # mine\(lineBreak)[[users]]\(lineBreak)admin = true")
      == "{kw:[server]}⏎{type:port} = {num:5500} {com:# mine}⏎{kw:[[users]]}⏎{type:admin} = {kw:true}")
    #expect(colors("ini", "[General]\(lineBreak); settings\(lineBreak)Name = My Server\(lineBreak)Enabled=yes")
      == "{kw:[General]}⏎{com:; settings}⏎{type:Name} = My Server⏎{type:Enabled}={kw:yes}")
  }

  @Test func highlightsBASICWithREMOnItsOwn() {
    #expect(colors("basic", "10 PRINT \"HI\" : REM greet\(lineBreak)20 x = REMOVE ' not REM")
      == "{num:10} {kw:PRINT} {str:\"HI\"} : {com:REM greet}⏎{num:20} x = REMOVE {com:' not REM}")
  }

  @Test func highlightsLisp() {
    #expect(colors("lisp", "(defun greet (name) ; say hi\(lineBreak)  (format t \"hi ~a\" name)) #| block |#")
      == "({kw:defun} greet (name) {com:; say hi}⏎  (format {kw:t} {str:\"hi ~a\"} name)) {com:#| block |#}")
  }

  @Test func highlightsHyperTalk() {
    #expect(colors("hypertalk", "on mouseUp -- click\(lineBreak)  put \"hi\" into field 1\(lineBreak)end mouseUp")
      == "{kw:on} mouseUp {com:-- click}⏎  {kw:put} {str:\"hi\"} {kw:into} {kw:field} {num:1}⏎{kw:end} mouseUp")
  }

  @Test func highlightsPascalWithBothBlockComments() {
    #expect(colors("pascal", "program Hello; { greet } (* twice *)\(lineBreak)var name: Str255;\(lineBreak)begin WriteLn('hi') // done\(lineBreak)end.")
      == "{kw:program} {type:Hello}; {com:{ greet }} {com:(* twice *)}⏎{kw:var} name: {type:Str255};⏎{kw:begin} {type:WriteLn}({str:'hi'}) {com:// done}⏎{kw:end}.")
  }

  @Test func unclosedStringEndsWithItsLine() {
    #expect(colors("swift", "let s = \"unclosed\(lineBreak)next") == "{kw:let} s = {str:\"unclosed}⏎next")
  }

  @Test func otherLanguagesArePlain() {
    #expect(colors("unknownlang", "let x = 1") == "let x = 1")
    #expect(colors("", "let x = 1") == "let x = 1")
  }
}
