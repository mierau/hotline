import RegexBuilder

struct RegularExpressions {
  // Known TLD list for schemeless URL matching and email addresses.
  // URLs with an explicit scheme (http://, https://, hotline://) accept any TLD.
  private static let knownTLD = ChoiceOf {
    // Generic TLDs
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
    "app"
    "cc"
    "chat"
    "dev"
    "gg"
    "page"
    "site"
    "social"
    "tech"
    "world"
    "xyz"
    // Country code TLDs
    "ai"
    "au"
    "be"
    "br"
    "by"
    "ca"
    "co"
    "de"
    "er"
    "es"
    "fi"
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
    "no"
    "nz"
    "ps"
    "pt"
    "ja"
    "ru"
    "se"
    "st"
    "to"
    "tv"
    "uk"
    "us"
    "ws"
  }

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

  // MARK: - URL Components

  // Path character class including dot (used inside balanced delimiters)
  private static let pathCharClass = CharacterClass(
    .anyOf("#_-/.?=&%\\:+~@"),
    ("a"..."z"),
    ("0"..."9")
  )

  // Path character class without dot (prevents URLs from ending with a period)
  private static let pathCharNoDot = CharacterClass(
    .anyOf("#_-/?=&%\\:+~@"),
    ("a"..."z"),
    ("0"..."9")
  )

  // Path segment: balanced parens/brackets, dot-then-content, or regular path characters
  private static let pathSegment = Regex {
    ChoiceOf {
      Regex {
        "("
        ZeroOrMore { pathCharClass }
        ")"
      }
      Regex {
        "["
        ZeroOrMore { pathCharClass }
        "]"
      }
      Regex { "." ; pathCharNoDot }
      pathCharNoDot
    }
  }.ignoresCase()

  private static let domainLabel = Regex {
    OneOrMore {
      CharacterClass(
        .anyOf("-"),
        ("a"..."z"),
        ("0"..."9")
      )
    }
  }.ignoresCase()

  private static let domainName = Regex {
    domainLabel
    ZeroOrMore {
      "."
      domainLabel
    }
  }.ignoresCase()

  private static let portNumber = Regex {
    Optionally {
      ":"
      OneOrMore(.digit)
    }
  }

  // Any TLD: 2+ alpha characters (used when scheme is present)
  private static let anyTLD = Regex {
    Repeat(2...) {
      CharacterClass(("a"..."z"))
    }
  }.ignoresCase()

  // IPv4 address: four dot-separated octets (e.g. 73.132.202.107)
  private static let ipv4Address = Regex {
    Repeat(1...3) { .digit }
    "."
    Repeat(1...3) { .digit }
    "."
    Repeat(1...3) { .digit }
    "."
    Repeat(1...3) { .digit }
  }

  // URL with explicit scheme: accepts any TLD or IP address
  private static let schemeLink = Regex {
    ChoiceOf {
      "hotline://"
      "http://"
      "https://"
    }
    ChoiceOf {
      Regex { domainName; "."; anyTLD }
      ipv4Address
    }
    portNumber
    ZeroOrMore { pathSegment }
  }.ignoresCase()

  // URL without scheme: requires known TLD to avoid false positives
  private static let schemelessLink = Regex {
    domainName
    "."
    knownTLD
    portNumber
    ZeroOrMore { pathSegment }
  }.ignoresCase()

  // MARK: - Relaxed Link

  static let relaxedLink = Regex {
    ChoiceOf {
      Anchor.startOfLine
      Anchor.wordBoundary
    }
    Capture {
      ChoiceOf {
        schemeLink
        schemelessLink
      }
    }
    ChoiceOf {
      Anchor.endOfLine
      Anchor.wordBoundary
    }
  }
  .anchorsMatchLineEndings()
  .ignoresCase()

  // MARK: - Server Address

  /// An IP address and port, like 192.168.1.5:5500, the way Hotline servers are often written.
  static let serverAddress = Regex {
    Anchor.wordBoundary
    ipv4Address
    ":"
    Repeat(2...5) { .digit }
    Anchor.wordBoundary
  }

  // MARK: - Markdown Link

  /// A link already written in Markdown, [text](address).
  static let markdownLink = Regex {
    "["
    ZeroOrMore { CharacterClass.anyOf("]").inverted }
    "]("
    ZeroOrMore { CharacterClass(.anyOf(")"), .whitespace).inverted }
    ")"
  }

  // MARK: - Email Address

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
      knownTLD
    }
    ChoiceOf {
      Anchor.endOfLine
      Anchor.wordBoundary
    }
  }
  .anchorsMatchLineEndings()
  .ignoresCase()
}
