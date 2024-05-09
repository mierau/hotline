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
  
  static let supportedLinkScheme = Regex {
    Anchor.startOfLine
    ChoiceOf {
      "hotline"
      "http"
      "https"
    }
    "://"
  }.ignoresCase().anchorsMatchLineEndings()
  
  static let relaxedLink = Regex {
    ChoiceOf {
      Anchor.startOfLine
      Anchor.wordBoundary
    }
    Capture {
      // scheme (optional)
      Optionally {
        ChoiceOf {
          "hotline://"
          "http://"
          "https://"
        }
      }
      // domain name
      OneOrMore {
        CharacterClass(
          .anyOf(".-@"),
          ("a"..."z"),
          ("0"..."9")
        )
      }
      // top-level domain name
      "."
      ChoiceOf {
        "com"
        "net"
        "org"
        "edu"
        "gov"
        "mil"
        "aero"
        "asia"
        "biz"
        "cat"
        "coop"
        "info"
        "int"
        "jobs"
        "mobi"
        "museum"
        "name"
        "pizza"
        "post"
        "pro"
        "red"
        "tel"
        "today"
        "travel"
        "garden"
        "online"
        "ai"
        "be"
        "by"
        "ca"
        "co"
        "de"
        "er"
        "es"
        "fr"
        "gs"
        "ie"
        "im"
        "in"
        "io"
        "is"
        "it"
        "jp"
        "la"
        "ly"
        "ma"
        "md"
        "me"
        "my"
        "nl"
        "ps"
        "pt"
        "ja"
        "st"
        "to"
        "tv"
        "uk"
        "ws"
      }
      // Port
      Optionally {
        ":"
        OneOrMore {
          CharacterClass(.digit)
        }
      }
      // path
      ZeroOrMore {
        CharacterClass(
          .anyOf("#_-/.?=&%\\()[]"),
          ("a"..."z"),
          ("0"..."9")
        )
      }
    }
    ChoiceOf {
      Anchor.endOfLine
      Anchor.wordBoundary
    }
  }
  .anchorsMatchLineEndings()
  .ignoresCase()
  
  static let emailAddress = Regex {
    ChoiceOf {
      Anchor.startOfLine
      Anchor.wordBoundary
    }
    Capture {
      // username
      OneOrMore {
        CharacterClass(
          .anyOf(".-_"),
          ("a"..."z"),
          ("0"..."9")
        )
      }
      "@"
      // domain name
      OneOrMore {
        CharacterClass(
          .anyOf(".-"),
          ("a"..."z"),
          ("0"..."9")
        )
      }
      // top-level domain name
      "."
      ChoiceOf {
        "com"
        "net"
        "org"
        "edu"
        "gov"
        "mil"
        "aero"
        "asia"
        "biz"
        "cat"
        "coop"
        "info"
        "int"
        "jobs"
        "mobi"
        "museum"
        "name"
        "pizza"
        "post"
        "pro"
        "red"
        "tel"
        "today"
        "travel"
        "garden"
        "online"
        "ai"
        "be"
        "by"
        "ca"
        "co"
        "de"
        "er"
        "es"
        "fr"
        "gs"
        "ie"
        "im"
        "in"
        "io"
        "is"
        "it"
        "jp"
        "la"
        "ly"
        "ma"
        "md"
        "me"
        "my"
        "nl"
        "ps"
        "pt"
        "ja"
        "st"
        "to"
        "tv"
        "uk"
        "ws"
      }
    }
    ChoiceOf {
      Anchor.endOfLine
      Anchor.wordBoundary
    }
  }
  .anchorsMatchLineEndings()
  .ignoresCase()
}
