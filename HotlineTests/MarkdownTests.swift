// MarkdownTests

import Testing
import AppKit
@testable import Hotline

struct MarkdownTests {

  /// The text as it's shown, with each styled run marked: b bold, i italic, u underline,
  /// s strikethrough, c code's font, l link, k a code block's line, with its place, and the
  /// language it names, q a quote's line, h a heading, with its size, r a line across, F a link to a
  /// file, P an image's preview. ¶ is a paragraph break, ⏎ a line break, and ▢ an attachment.
  private func look(_ input: String, previews: Int = 3) -> String {
    let text = Markdown.shownText(input, layout: Markdown.Layout(imagePreviews: previews))
    var out = ""
    text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, range, _ in
      var tags = ""
      if let font = attributes[.font] as? NSFont {
        let traits = font.fontDescriptor.symbolicTraits
        if traits.contains(.bold) && font.pointSize <= Markdown.font.pointSize { tags += "b" }
        if traits.contains(.italic) { tags += "i" }
        if font.isFixedPitch { tags += "c" }
        if font.pointSize > Markdown.font.pointSize { tags += "h\(Int(font.pointSize))" }
      }
      if attributes[.underlineStyle] != nil { tags += "u" }
      if attributes[.strikethroughStyle] != nil { tags += "s" }
      if attributes[.link] != nil { tags += "l" }
      if let line = attributes[Markdown.codeLineKey] as? Int { tags += "k\(line)" }
      if attributes[Markdown.quoteLineKey] != nil { tags += "q" }
      if attributes[Markdown.ruleKey] != nil { tags += "r" }
      if attributes[Markdown.fileLinkKey] != nil { tags += "F" }
      if attributes[.attachment] is ImageAttachment { tags += "P" }
      if let language = attributes[Markdown.codeLanguageKey] as? String { tags += "=\(language)" }
      let piece = (text.string as NSString).substring(with: range)
        .replacingOccurrences(of: "\n", with: "¶")
        .replacingOccurrences(of: "\u{2028}", with: "⏎")
        .replacingOccurrences(of: "\u{FFFC}", with: "▢")
      out += tags.isEmpty ? piece : "[\(tags):\(piece)]"
    }
    return out
  }

  // MARK: Words

  @Test func plainTextIsUnchanged() {
    #expect(look("just a plain message, nothing to see") == "just a plain message, nothing to see")
  }

  @Test func italicBoldAndBoth() {
    #expect(look("*italic* and **bold** and ***both***") == "[i:italic] and [b:bold] and [bi:both]")
  }

  @Test func underlineWithUnderscores() {
    #expect(look("_italic_ and __underline__ and ___both___") == "[i:italic] and [u:underline] and [iu:both]")
  }

  @Test func strikethrough() {
    #expect(look("~gone~ and ~~gone~~") == "[s:gone] and [s:gone]")
  }

  @Test func code() {
    #expect(look("run `make all` now") == "run [c:make all] now")
    #expect(look("`*not italic*`") == "[c:*not italic*]")
    #expect(look("run ```ls -la``` now") == "run [c:ls -la] now")
  }

  @Test func marksOnlyAtTheEdgesOfWords() {
    #expect(look("snake_case_name and file_name.txt") == "snake_case_name and file_name.txt")
    #expect(look("2*3*4 and mid*word*bold") == "2*3*4 and mid*word*bold")
    #expect(look("~5-~10 minutes") == "~5-~10 minutes")
    #expect(look("*word*'s and (*paren*) and *this*!") == "[i:word]'s and ([i:paren]) and [i:this]!")
  }

  @Test func unmatchedMarksStay() {
    #expect(look("*unclosed and _also") == "*unclosed and _also")
    #expect(look("a ** b ** c") == "a ** b ** c")
  }

  @Test func formattingInsideCodeKeepsItsFont() {
    #expect(look("**bold `code` bold**") == "[b:bold ][bc:code][b: bold]")
  }

  @Test func backslashesKeepMarksAsTheyAre() {
    #expect(look("\\*not italic\\*") == "*not italic*")
    #expect(look("\\# not a heading") == "# not a heading")
  }

  @Test func links() {
    #expect(look("see example.com/a_b_c and *this*") == "see [l:example.com/a_b_c] and [i:this]")
    #expect(look("[the stream](https://example.com/stream)") == "[l:the stream]")
    #expect(look("`https://example.com` isn't a link in code") == "[c:https://example.com] isn't a link in code")
  }

  @Test func longLinksShowShorter() {
    let link = "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabcdefghijklmnopqrstuvwxyz0123456789&index=12&t=42s"
    let text = Markdown.shownText(link, layout: .board)
    #expect(text.string == "https://www.youtube.com/watch?v=dQw4w9WgXcQ\u{2026}")
    #expect(Markdown.plainText(text) == link)
  }

  // MARK: Lines

  @Test func quotes() {
    #expect(look("> quoted\n> more") == "[q:quoted¶more]")
    #expect(look("> quoted\n>\n> after a blank") == "[q:quoted¶¶after a blank]")
    #expect(look(">_< and >.< stay") == ">_< and >.< stay")
  }

  @Test func lists() {
    #expect(look("- one\n- two") == "• one¶• two")
    #expect(look("1. first\n2) second") == "1. first¶2) second")
    #expect(look("- **bold** item") == "• [b:bold] item")
  }

  @Test func headings() {
    #expect(look("# Big\n## Smaller\n#### Same size\n#hashtag") == "[h20:Big¶][h17:Smaller¶][b:Same size¶]#hashtag")
    #expect(look("# **Bold** heading") == "[h20:Bold heading]")
  }

  @Test func linesAcross() {
    #expect(look("above\n---\nbelow") == "above¶[r:---][r:¶]below")
  }

  @Test func classicLineBreaksStay() {
    #expect(look("one\rtwo\r\rthree") == "one¶two¶¶three")
    #expect(look("NEWS\r=====") == "NEWS¶=====")
  }

  @Test func drawingsKeepTheirShape() {
    #expect(look(" +------+\n | box  |\n +------+") == "[c: +------+¶ | box  |¶ +------+]")
  }

  // MARK: Code Blocks

  @Test func codeBlocks() {
    #expect(look("```\ncode here\n```") == "[ck3:code here]")
    #expect(look("look:\n```lua\na\nb\n```\nnice") == "look:¶[ck0=lua:a¶][ck2:b¶]nice")
  }

  @Test func codeBlockAfterWords() {
    #expect(look("here: ```\nlet x = 1\n```") == "here:¶[ck3:let x = 1]")
  }

  @Test func codeBlockWithCodeOnItsFences() {
    #expect(look("```let x = 1\nlet y = 2```") == "[ck0:let x = 1¶][ck2:let y = 2]")
  }

  @Test func unclosedCodeBlocksStay() {
    #expect(look("```lua\nlocal x") == "```lua¶local x")
    #expect(look("``````") == "``````")
  }

  @Test func emptyCodeBlocksGo() {
    #expect(look("```\n```") == "")
    #expect(look("text\n```\n```\nmore") == "text¶more")
  }

  @Test func blankLinesNextToCodeBlocksGo() {
    #expect(look("before\n\n```\ncode\n```\n\nafter") == "before¶[ck3:code¶]after")
  }

  // MARK: Images and Files

  @Test func imagesShowAsTheirPreviews() {
    #expect(look("![a cat](https://example.com/cat.png)") == "[P:▢]")
    #expect(look("look ![a cat](https://example.com/cat.png) here") == "look  here⏎[P:▢]")
    #expect(look("![a cat](https://example.com/cat.png)", previews: 0) == "[l:a cat]")
  }

  @Test func linksToImagesHavePreviews() {
    #expect(look("https://example.com/cat.png") == "[l:https://example.com/cat.png]⏎[P:▢]")
    #expect(look("[my cat](https://example.com/cat.png)") == "[l:my cat]⏎[P:▢]")
    #expect(look("two https://example.com/a.png https://example.com/b.png") == "two [l:https://example.com/a.png] [l:https://example.com/b.png]⏎[P:▢]⏎[P:▢]")
  }

  @Test func imagesCopyAsTheirLinks() {
    let text = Markdown.shownText("![a cat](https://example.com/cat.png)", layout: .board)
    #expect(Markdown.plainText(text) == "https://example.com/cat.png")
  }

  @Test func linksToFiles() {
    #expect(look("hotline://127.0.0.1:5500/files/Maps/Readme.txt") == "[lF:▢][lF:Readme.txt]")
    #expect(look("see [the map](hotline://127.0.0.1:5500/files/Maps/Marathon/) now") == "see [lF:▢][lF:the map] now")
  }

  @Test func linksOutsideCode() {
    let links = Markdown.links(in: "see https://example.com/a and\r```\rhttps://example.com/hidden\r```\rhotline://127.0.0.1:5500/files/Readme.txt")
    #expect(links.map(\.absoluteString) == ["https://example.com/a", "hotline://127.0.0.1:5500/files/Readme.txt"])
  }
}
