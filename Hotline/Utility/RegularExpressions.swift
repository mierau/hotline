import RegexBuilder

struct RegularExpressions {
  static let messageBoardDivider = Regex {
    Capture {
      OneOrMore {
        CharacterClass(.newlineSequence)
      }
      ZeroOrMore {
        CharacterClass(.whitespace, .newlineSequence)
      }
      Repeat(2...) {
        CharacterClass(.anyOf("_-"))
      }
      ZeroOrMore {
        CharacterClass(.whitespace)
      }
      OneOrMore {
        CharacterClass(.newlineSequence)
      }
    }
  }
}
