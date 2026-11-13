import AppKit

/// Swearing and slurs, hidden wherever others' words show, while Settings has them hidden: swearing
/// as a cartoon's cursing, a grawlix, like #$%!, and slurs as dots, since cartoon cursing would make
/// light of them. Only how they're shown changes. What's sent and kept is as it was.
///
/// Only whole words, so "classic" and "Scunthorpe" are left alone, however they're spelled: stretched
/// out, as "fuuuck" is, or with numbers and symbols for letters, as "sh1t" is.
enum HiddenWords {
  /// Whether they're hidden: as Settings has it, or until that's chosen, on a child's Mac, where
  /// Communication Safety is on.
  static var isOn: Bool {
    Prefs.shared.hideOffensiveWords ?? (SensitiveContent.intervention == .descriptive)
  }

  /// Hides them in text that's shown, which keeps its length, and what's set on each part of it, so
  /// a link with one in it still goes where it did.
  static func hide(in text: NSMutableAttributedString) {
    for (range, replacement) in self.replacements(in: text.string) {
      text.replaceCharacters(in: range, with: replacement)
    }
  }

  /// Plain text with them hidden, as a notification's.
  static func hidden(_ text: String) -> String {
    let hidden = NSMutableString(string: text)
    for (range, replacement) in self.replacements(in: text) {
      hidden.replaceCharacters(in: range, with: replacement)
    }
    return hidden as String
  }

  /// What goes where each one is, from the last back, so each range is still where it was.
  private static func replacements(in text: String) -> [(range: NSRange, replacement: String)] {
    let string = text as NSString
    let whole = NSRange(location: 0, length: string.length)
    var found = self.slurs.matches(in: text, range: whole).map { match in
      (range: match.range, replacement: String(repeating: "•", count: match.range.length))
    }
    for match in self.swearing.matches(in: text, range: whole) where !found.contains(where: { NSIntersectionRange($0.range, match.range).length > 0 }) {
      found.append((range: match.range, replacement: self.grawlix(for: string.substring(with: match.range), length: match.range.length)))
    }
    return found.sorted { $0.range.location > $1.range.location }
  }

  /// Cartoon cursing as long as a word: symbols that don't repeat side by side, ending with "!", the
  /// same for the same word each time, so a line doesn't change as it's shown again.
  static func grawlix(for word: String, length: Int) -> String {
    let symbols: [Character] = ["#", "$", "%", "@", "&", "*"]
    // Picked at random, but from the word, so each word has its own, the same each time.
    var state = word.lowercased().unicodeScalars.reduce(UInt32(2_166_136_261)) { ($0 ^ $1.value) &* 16_777_619 }
    var previous = -1
    return String((0..<length).map { index -> Character in
      if index == length - 1 && length > 2 {
        return "!"
      }
      state = state &* 1_664_525 &+ 1_013_904_223
      var pick = Int(state >> 16) % symbols.count
      if pick == previous {
        pick = (pick + 1) % symbols.count
      }
      previous = pick
      return symbols[pick]
    })
  }

  // MARK: Words

  /// Swearing, in ROT13, so this file doesn't spell it out. Not the plural of the third word on the
  /// fourth line, which, as its letters can be typed more than once, would hide "assess".
  private static let swearing = Self.expression(for: """
    shpx shpxf shpxrq shpxre shpxref shpxvat shpxva shpxurnq shpxurnqf shpxsnpr shpxjvg shpxjvgf
    shpxhc shpxhcf zbgureshpxre zbgureshpxref zbgureshpxvat zbgureshpxva pyhfgreshpx fuvg fuvgf
    fuvggl fuvggvat fuvggrq fuvgurnq fuvgurnqf fuvgsnpr ohyyfuvg ubefrfuvg qvcfuvg qvcfuvgf
    ncrfuvg ongfuvg phag phagf nffubyr nffubyrf nff qhzonff qhzonffrf wnpxnff wnpxnffrf
    fznegnff ovgpu ovgpurf ovgpul ovgpuvat fbabsnovgpu qvpx qvpxf qvpxurnq qvpxurnqf pbpx pbpxf
    pbpxfhpxre pbpxfhpxref chffl chffvrf onfgneq onfgneqf juber juberf fyhg fyhgf fyhggl gjng
    gjngf jnaxre jnaxref cevpx cevpxf qbhpur qbhpuront qbhpurontf
    """)

  /// Slurs about who people are: their race, where they're from, who they love, or how their minds
  /// work. In ROT13, as above.
  private static let slurs = Self.expression(for: """
    avttre avttref avttn avttnf puvax puvaxf tbbx tbbxf fcvp fcvpf xvxr xvxrf jrgonpx jrgonpxf
    enturnq enturnqf gbjryurnq gbjryurnqf ornare ornaref wnc wncf cnxv cnxvf pbba pbbaf snttbg
    snttbgf snt sntf qlxr qlxrf genaal genaavrf ergneq ergneqf ergneqrq gneq gneqf
    """)

  /// Any of some words in ROT13, whole, however they're spelled out, in any case.
  private static func expression(for rot13: String) -> NSRegularExpression {
    let words = rot13.split(whereSeparator: \.isWhitespace).map(self.decoded)
    let alternatives = words.map(self.pattern(for:)).joined(separator: "|")
    // Not after or before a letter or a number, which would make it part of another word.
    return try! NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])", options: [.caseInsensitive])
  }

  /// A word's letters, each as many times over as it's typed, or as what stands in for it.
  private static func pattern(for word: String) -> String {
    word.map { letter in
      switch letter {
      case "a": "[a@4]+"
      case "e": "[e3]+"
      case "i": "[i1!]+"
      case "o": "[o0]+"
      case "s": "[s$5]+"
      default: "\(letter)+"
      }
    }.joined()
  }

  private static func decoded(_ word: Substring) -> String {
    String(String.UnicodeScalarView(word.unicodeScalars.map { scalar in
      switch scalar {
      case "a"..."m": Unicode.Scalar(scalar.value + 13)!
      case "n"..."z": Unicode.Scalar(scalar.value - 13)!
      default: scalar
      }
    }))
  }
}

extension String {
  /// As it's shown, with swearing and slurs hidden while Settings has them hidden. A view showing it
  /// is shown again when that changes.
  var hidingOffensiveWords: String {
    HiddenWords.isOn ? HiddenWords.hidden(self) : self
  }
}

extension AttributedString {
  /// As it's shown, as a string is, keeping its links where they were, and going where they did.
  var hidingOffensiveWords: AttributedString {
    guard HiddenWords.isOn else {
      return self
    }
    let text = NSMutableAttributedString(self)
    HiddenWords.hide(in: text)
    return AttributedString(text)
  }
}
