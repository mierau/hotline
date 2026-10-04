// ChatFormattingTests

import Testing
import AppKit
@testable import Hotline

struct ChatFormattingTests {

  /// The text as chat shows it, with each formatted run marked: b bold, i italic, s strikethrough,
  /// u underline, c code, l link, k code block. ¶ is a paragraph break and ⏎ a line break.
  private func look(_ input: String) -> String {
    let text = ChatMessageRenderer.formattedText(input, paragraph: NSParagraphStyle())
    var out = ""
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
      var tags = ""
      if let font = attributes[.font] as? NSFont {
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) { tags += "b" }
        if traits.contains(.italic) { tags += "i" }
        if font.isFixedPitch { tags += "c" }
      }
      if attributes[.strikethroughStyle] != nil { tags += "s" }
      if attributes[.underlineStyle] != nil { tags += "u" }
      if attributes[.link] != nil { tags += "l" }
      if attributes[ChatMessageRenderer.codeBlockKey] != nil { tags += "k" }
      let piece = (text.string as NSString).substring(with: range)
        .replacingOccurrences(of: "\n", with: "¶")
        .replacingOccurrences(of: "\u{2028}", with: "⏎")
      out += tags.isEmpty ? piece : "[\(tags):\(piece)]"
    }
    return out
  }

  @Test func plainTextIsUnchanged() {
    #expect(look("just a plain message, nothing to see") == "just a plain message, nothing to see")
  }

  @Test func bold() {
    #expect(look("*bold* and **bold**") == "[b:bold] and [b:bold]")
  }

  @Test func italic() {
    #expect(look("_italic_ text") == "[i:italic] text")
  }

  @Test func strikethrough() {
    #expect(look("~gone~ and ~~gone~~") == "[s:gone] and [s:gone]")
  }

  @Test func underline() {
    #expect(look("__underlined__") == "[u:underlined]")
  }

  @Test func code() {
    #expect(look("run `make all` now") == "run [c:make all] now")
  }

  @Test func nothingInsideCode() {
    #expect(look("`*not bold*`") == "[c:*not bold*]")
  }

  @Test func boldAndItalicTogether() {
    #expect(look("*_both_*") == "[bi:both]")
  }

  @Test func marksInsideWordsStay() {
    #expect(look("snake_case_name and 2*3*4") == "snake_case_name and 2*3*4")
    #expect(look("mid*word*bold") == "mid*word*bold")
    #expect(look("file_name.txt is ready") == "file_name.txt is ready")
  }

  @Test func unmatchedMarksStay() {
    #expect(look("* not a list") == "* not a list")
    #expect(look("*unclosed and _also") == "*unclosed and _also")
    #expect(look("a ** b ** c") == "a ** b ** c")
  }

  @Test func formattingStaysOnOneLine() {
    #expect(look("*across\u{2028}lines*") == "*across⏎lines*")
  }

  @Test func marksNextToPunctuation() {
    #expect(look("*bold*, _italic_, ~strike~.") == "[b:bold], [i:italic], [s:strike].")
    #expect(look("(*parenthetical*)") == "([b:parenthetical])")
  }

  @Test func linksAreLeftAlone() {
    #expect(look("see example.com/a_b_c and *this*") == "see [l:example.com/a_b_c] and [b:this]")
    #expect(look("https://example.com/my*file*.zip") == "[l:https://example.com/my*file*.zip]")
  }

  @Test func noMarkdown() {
    #expect(look("# not a heading and 1. not a list") == "# not a heading and 1. not a list")
  }

  // MARK: Code blocks

  private let lineBreak = "\u{2028}"

  @Test func codeBlock() {
    #expect(look("```\(lineBreak)code here\(lineBreak)```") == "¶[ck:code here]")
  }

  @Test func codeBlockIsItsOwnParagraph() {
    #expect(look("look:\(lineBreak)```\(lineBreak)a\(lineBreak)b\(lineBreak)```\(lineBreak)nice") == "look:¶[ck:a⏎b][ck:¶]nice")
    #expect(look("before\(lineBreak)\(lineBreak)```x```\(lineBreak)\(lineBreak)after") == "before¶[ck:x][ck:¶]after")
  }

  @Test func codeBlockOnOneLine() {
    #expect(look("run ```ls -la``` now") == "run¶[ck:ls -la][ck:¶]now")
    #expect(look("```lua code```") == "¶[ck:lua code]")
  }

  @Test func codeBlocksInARow() {
    #expect(look("```a```\(lineBreak)```b```") == "¶[ck:a][ck:¶][ck:b]")
  }

  @Test func nothingInsideCodeBlocks() {
    #expect(look("```*not bold* `nor code` https://example.com```") == "¶[ck:*not bold* `nor code` https://example.com]")
    #expect(look("*bold* ```x``` _italic_") == "[b:bold]¶[ck:x][ck:¶][i:italic]")
  }

  @Test func unclosedCodeBlocksStay() {
    #expect(look("```lua\(lineBreak)local x") == "```lua⏎local x")
    #expect(look("`inline` and ``` alone") == "[c:inline] and ``` alone")
    #expect(look("``````") == "``````")
  }

  @Test func codeBlockKeepsItsBlankLinesAndIndents() {
    #expect(look("```lua\(lineBreak)\(lineBreak)  indented\(lineBreak)\(lineBreak)```") == "¶[ck:⏎  indented⏎]")
  }

  @Test func codeBlockIndents() {
    let message = NSMutableParagraphStyle()
    message.firstLineHeadIndent = 25
    message.headIndent = 41
    let text = ChatMessageRenderer.formattedText("hi ```x``` there", paragraph: message)
    let styles = [0, 3, text.length - 1].map { text.attribute(.paragraphStyle, at: $0, effectiveRange: nil) as? NSParagraphStyle }
    #expect(styles[0]?.firstLineHeadIndent == 25 && styles[0]?.headIndent == 41)
    #expect(styles[1]?.firstLineHeadIndent == 49 && styles[1]?.headIndent == 49 && styles[1]?.tailIndent == -8)
    #expect(styles[2]?.firstLineHeadIndent == 41 && styles[2]?.headIndent == 41)
  }

  @Test func codeBlockInAMessage() {
    let text = ChatMessageRenderer.render(ChatMessage(text: "mars: ```lua\nprint(1)\n```\nthat's it", type: .message, date: Date()))
    #expect(text.string == "mars: \nprint(1)\nthat's it")
    // Only the name's paragraph gets the icon.
    var sender = NSRange()
    _ = text.attribute(ChatMessageRenderer.senderNameKey, at: 0, longestEffectiveRange: &sender, in: NSRange(location: 0, length: text.length))
    #expect(sender == NSRange(location: 0, length: 7))
  }

  @Test func codeBlockWithNoName() {
    let text = ChatMessageRenderer.render(ChatMessage(text: "```\nx\n```", type: .message, date: Date()))
    #expect(text.string == "x")
  }

  @Test func codeBlocksKeepTheLanguageTheyName() {
    func language(_ input: String) -> String? {
      let text = ChatMessageRenderer.formattedText(input, paragraph: NSParagraphStyle())
      return text.attribute(ChatMessageRenderer.codeLanguageKey, at: (text.string as NSString).range(of: "x").location, effectiveRange: nil) as? String
    }
    #expect(language("```lua\(lineBreak)x\(lineBreak)```") == "lua")
    // Even one that isn't colored.
    #expect(language("```zig\(lineBreak)x\(lineBreak)```") == "zig")
    #expect(language("```\(lineBreak)x\(lineBreak)```") == nil)
    #expect(language("```x```") == nil)
  }

  @Test func codeBlocksMakeRoomForTheirLanguage() {
    func spaceBefore(_ input: String) -> CGFloat {
      let text = ChatMessageRenderer.formattedText(input, paragraph: NSParagraphStyle())
      let style = text.attribute(.paragraphStyle, at: (text.string as NSString).range(of: "x").location, effectiveRange: nil) as? NSParagraphStyle
      return style?.paragraphSpacingBefore ?? 0
    }
    #expect(spaceBefore("```zig\(lineBreak)x\(lineBreak)```") == spaceBefore("```\(lineBreak)x\(lineBreak)```") + ChatMessageRenderer.codeLanguageHeight)
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
    let text = ChatMessageRenderer.render(ChatMessage(text: "\r mars:  ```\rone\rtwo\r```", type: .message, date: Date()))
    #expect(text.string == "mars: \none\u{2028}two")
  }

  @Test func linksInCodeBlocksArentLinks() {
    let links = ChatMessageRenderer.links(in: "see https://example.com/a and\r```\rhttps://example.com/hidden\r```\rhotline://127.0.0.1:5500/files/Readme.txt")
    #expect(links.map(\.absoluteString) == ["https://example.com/a", "hotline://127.0.0.1:5500/files/Readme.txt"])
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
    #expect(icons.first === ChatMessageRenderer.folderIcon)
    #expect(icons.last !== ChatMessageRenderer.folderIcon)
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

  /// The code in a block named `language`, with each colored run marked by what it is.
  private func colors(_ language: String, _ code: String) -> String {
    let text = ChatMessageRenderer.formattedText("```\(language)\(lineBreak)\(code)\(lineBreak)```", paragraph: NSParagraphStyle())
    let names: [(ChatCodeHighlighter.Token, String)] = [(.keyword, "kw"), (.string, "str"), (.comment, "com"), (.number, "num"), (.type, "type")]
    var out = ""
    text.enumerateAttribute(.foregroundColor, in: NSRange(location: 1, length: text.length - 1)) { value, range, _ in
      let piece = (text.string as NSString).substring(with: range).replacingOccurrences(of: "\u{2028}", with: "⏎")
      if let name = names.first(where: { (value as AnyObject) === ChatCodeHighlighter.color(for: $0.0) })?.1 {
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
