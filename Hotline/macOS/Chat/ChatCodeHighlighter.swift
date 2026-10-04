import AppKit

/// Colors code in a chat code block by its language, simply, the way a code editor would at a
/// glance: keywords, strings, comments, numbers, the names of types, and the keys in settings files. It doesn't know every
/// language, or every corner of the ones it does, just enough to make code pasted into chat easy
/// to read.
enum ChatCodeHighlighter {

  // MARK: Languages

  struct Language {
    var keywords: Set<String>
    /// Keywords match whatever their case, as in SQL.
    var keywordsIgnoreCase = false
    /// What starts a comment that runs to the end of the line. One that's a word, like BASIC's REM,
    /// starts one whatever its case, on its own.
    var lineComments: [String] = []
    var blockComments: [(open: String, close: String)] = []
    /// Strings that end at the end of the line.
    var quotes: [String] = ["\"", "'"]
    /// Strings that can run over lines, like """ in Swift or [[ in Lua.
    var longStrings: [(open: String, close: String)] = []
    /// Capitalized words are the names of types.
    var capitalizedTypes = true
    /// Words starting with $ are variables, as in shell scripts and PHP.
    var dollarVariables = false
    /// Lines starting with # are preprocessor directives, as in C.
    var preprocessor = false
    /// Lines that start with a name and this, like name: in YAML or name = in TOML, have the name
    /// colored as a key.
    var keySeparator: Character?
    /// Lines in brackets are sections, as in TOML and INI files.
    var sections = false
  }

  /// The language a code block names, like lua in ```lua.
  static func language(named name: String) -> Language? {
    switch name.lowercased() {
    case "lua": return self.lua
    case "swift": return self.swift
    case "python", "py": return self.python
    case "javascript", "js", "jsx", "typescript", "ts", "tsx": return self.javascript
    case "c", "h", "cpp", "c++", "cc", "hpp", "objc", "objective-c", "objectivec", "m", "mm": return self.cFamily
    case "java", "kotlin", "kt": return self.java
    case "go", "golang": return self.go
    case "rust", "rs": return self.rust
    case "ruby", "rb": return self.ruby
    case "php": return self.php
    case "sh", "bash", "zsh", "shell", "console", "terminal": return self.shell
    case "sql": return self.sql
    case "json": return self.json
    case "applescript", "osascript": return self.appleScript
    case "perl", "pl", "pm": return self.perl
    case "yaml", "yml": return self.yaml
    case "toml": return self.toml
    case "ini", "cfg", "conf", "properties": return self.ini
    case "basic", "bas", "qbasic", "quickbasic", "freebasic", "vb", "vba", "vbs", "vbscript", "visualbasic": return self.basic
    case "lisp", "cl", "common-lisp", "commonlisp", "elisp", "emacs-lisp", "scheme", "scm", "racket", "rkt", "clojure", "clj", "cljs": return self.lisp
    case "hypertalk", "hypercard", "livecode", "supertalk", "xtalk": return self.hyperTalk
    case "pascal", "pas", "delphi", "objectpascal", "object-pascal", "freepascal": return self.pascal
    default: return nil
    }
  }

  private static let lua = Language(
    keywords: ["and", "break", "do", "else", "elseif", "end", "false", "for", "function", "goto", "if", "in", "local", "nil", "not", "or", "repeat", "return", "then", "true", "until", "while"],
    lineComments: ["--"],
    blockComments: [("--[[", "]]")],
    longStrings: [("[[", "]]")],
    capitalizedTypes: false
  )

  private static let swift = Language(
    keywords: ["actor", "any", "as", "associatedtype", "async", "await", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "lazy", "let", "mutating", "nil", "nonisolated", "open", "operator", "override", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "Self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "weak", "where", "while"],
    lineComments: ["//"],
    blockComments: [("/*", "*/")],
    quotes: ["\""],
    longStrings: [("\"\"\"", "\"\"\"")]
  )

  private static let python = Language(
    keywords: ["False", "None", "True", "and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal", "not", "or", "pass", "raise", "return", "self", "try", "while", "with", "yield"],
    lineComments: ["#"],
    longStrings: [("\"\"\"", "\"\"\""), ("'''", "'''")]
  )

  private static let javascript = Language(
    keywords: ["async", "await", "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "function", "get", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "set", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "with", "yield"],
    lineComments: ["//"],
    blockComments: [("/*", "*/")],
    longStrings: [("`", "`")]
  )

  private static let cFamily = Language(
    keywords: ["auto", "bool", "break", "case", "char", "class", "const", "continue", "default", "delete", "do", "double", "else", "enum", "extern", "false", "float", "for", "goto", "id", "if", "inline", "int", "long", "namespace", "new", "nil", "nullptr", "private", "protected", "public", "register", "return", "self", "short", "signed", "sizeof", "static", "struct", "super", "switch", "template", "this", "true", "typedef", "typename", "union", "unsigned", "using", "virtual", "void", "volatile", "while", "NO", "YES", "NULL"],
    lineComments: ["//"],
    blockComments: [("/*", "*/")],
    preprocessor: true
  )

  private static let java = Language(
    keywords: ["abstract", "assert", "boolean", "break", "byte", "case", "catch", "char", "class", "const", "continue", "data", "default", "do", "double", "else", "enum", "extends", "false", "final", "finally", "float", "for", "fun", "if", "implements", "import", "instanceof", "int", "interface", "long", "native", "new", "null", "object", "package", "private", "protected", "public", "return", "sealed", "short", "static", "super", "switch", "synchronized", "this", "throw", "throws", "transient", "true", "try", "val", "var", "void", "volatile", "when", "while"],
    lineComments: ["//"],
    blockComments: [("/*", "*/")],
    longStrings: [("\"\"\"", "\"\"\"")]
  )

  private static let go = Language(
    keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "false", "for", "func", "go", "goto", "if", "import", "interface", "map", "nil", "package", "range", "return", "select", "struct", "switch", "true", "type", "var"],
    lineComments: ["//"],
    blockComments: [("/*", "*/")],
    longStrings: [("`", "`")]
  )

  private static let rust = Language(
    keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"],
    lineComments: ["//"],
    blockComments: [("/*", "*/")],
    quotes: ["\""]
  )

  private static let ruby = Language(
    keywords: ["BEGIN", "END", "alias", "and", "begin", "break", "case", "class", "def", "do", "else", "elsif", "end", "ensure", "false", "for", "if", "in", "module", "next", "nil", "not", "or", "redo", "rescue", "retry", "return", "self", "super", "then", "true", "undef", "unless", "until", "when", "while", "yield"],
    lineComments: ["#"]
  )

  private static let php = Language(
    keywords: ["abstract", "and", "array", "as", "break", "case", "catch", "class", "clone", "const", "continue", "default", "do", "echo", "else", "elseif", "empty", "extends", "false", "final", "finally", "fn", "for", "foreach", "function", "global", "if", "implements", "include", "instanceof", "interface", "isset", "list", "match", "namespace", "new", "null", "or", "print", "private", "protected", "public", "readonly", "require", "return", "static", "switch", "throw", "trait", "true", "try", "unset", "use", "var", "while", "xor", "yield"],
    lineComments: ["//", "#"],
    blockComments: [("/*", "*/")],
    dollarVariables: true
  )

  private static let shell = Language(
    keywords: ["alias", "case", "declare", "do", "done", "echo", "elif", "else", "esac", "exit", "export", "fi", "for", "function", "if", "in", "local", "readonly", "return", "set", "source", "then", "unset", "until", "while"],
    lineComments: ["#"],
    capitalizedTypes: false,
    dollarVariables: true
  )

  private static let sql = Language(
    keywords: ["add", "all", "alter", "and", "as", "asc", "avg", "between", "by", "case", "count", "create", "default", "delete", "desc", "distinct", "drop", "else", "end", "exists", "foreign", "from", "group", "having", "in", "index", "inner", "insert", "into", "is", "join", "key", "left", "like", "limit", "max", "min", "not", "null", "offset", "on", "or", "order", "outer", "primary", "references", "right", "select", "set", "sum", "table", "then", "union", "unique", "update", "values", "when", "where"],
    keywordsIgnoreCase: true,
    lineComments: ["--"],
    blockComments: [("/*", "*/")],
    quotes: ["'", "\""],
    capitalizedTypes: false
  )

  private static let json = Language(
    keywords: ["true", "false", "null"],
    quotes: ["\""],
    capitalizedTypes: false
  )

  private static let appleScript = Language(
    keywords: ["and", "considering", "else", "end", "error", "every", "false", "get", "global", "if", "ignoring", "in", "is", "it", "local", "my", "not", "of", "on", "or", "property", "repeat", "return", "script", "set", "tell", "the", "then", "to", "true", "try", "whose", "with"],
    lineComments: ["--", "#"],
    blockComments: [("(*", "*)")],
    quotes: ["\""],
    capitalizedTypes: false
  )

  private static let perl = Language(
    keywords: ["and", "cmp", "continue", "defined", "delete", "die", "do", "each", "else", "elsif", "eq", "eval", "exists", "for", "foreach", "ge", "gt", "if", "keys", "last", "le", "local", "lt", "my", "ne", "next", "no", "not", "or", "our", "package", "print", "printf", "qw", "redo", "ref", "require", "return", "say", "shift", "sub", "undef", "unless", "until", "use", "values", "while", "xor"],
    lineComments: ["#"],
    capitalizedTypes: false,
    dollarVariables: true
  )

  private static let yaml = Language(
    keywords: ["false", "no", "null", "off", "on", "true", "yes"],
    keywordsIgnoreCase: true,
    lineComments: ["#"],
    capitalizedTypes: false,
    keySeparator: ":"
  )

  private static let toml = Language(
    keywords: ["false", "true"],
    lineComments: ["#"],
    longStrings: [("\"\"\"", "\"\"\""), ("'''", "'''")],
    capitalizedTypes: false,
    keySeparator: "=",
    sections: true
  )

  private static let ini = Language(
    keywords: ["false", "no", "off", "on", "true", "yes"],
    keywordsIgnoreCase: true,
    lineComments: [";", "#"],
    quotes: ["\""],
    capitalizedTypes: false,
    keySeparator: "=",
    sections: true
  )

  private static let basic = Language(
    keywords: ["and", "as", "boolean", "byref", "byval", "call", "case", "class", "cls", "const", "data", "declare", "def", "dim", "do", "double", "each", "else", "elseif", "end", "exit", "false", "for", "function", "gosub", "goto", "if", "in", "input", "integer", "is", "let", "long", "loop", "mod", "new", "next", "not", "nothing", "on", "or", "print", "private", "public", "read", "redim", "restore", "return", "select", "set", "single", "step", "stop", "string", "sub", "then", "to", "true", "until", "wend", "while", "with", "xor"],
    keywordsIgnoreCase: true,
    lineComments: ["'", "rem"],
    quotes: ["\""],
    capitalizedTypes: false
  )

  /// Common Lisp, Scheme, and Clojure, which share their comments and most of their forms.
  private static let lisp = Language(
    keywords: ["and", "case", "cond", "def", "defclass", "defconstant", "defgeneric", "define", "defmacro", "defmethod", "defn", "defparameter", "defstruct", "defun", "defvar", "do", "dolist", "dotimes", "else", "false", "fn", "if", "lambda", "let", "loop", "nil", "not", "or", "progn", "quote", "recur", "return", "setf", "setq", "t", "true", "unless", "when"],
    keywordsIgnoreCase: true,
    lineComments: [";"],
    blockComments: [("#|", "|#")],
    quotes: ["\""],
    capitalizedTypes: false
  )

  /// HyperCard's scripts, and LiveCode's.
  private static let hyperTalk = Language(
    keywords: ["after", "and", "answer", "ask", "background", "before", "bg", "btn", "button", "card", "cd", "char", "contains", "div", "do", "else", "empty", "end", "exit", "false", "field", "fld", "for", "function", "get", "global", "go", "if", "in", "into", "is", "it", "item", "line", "me", "mod", "next", "not", "of", "on", "or", "pass", "put", "repeat", "return", "send", "set", "stack", "the", "then", "times", "to", "true", "until", "while", "with", "word"],
    keywordsIgnoreCase: true,
    lineComments: ["--"],
    quotes: ["\""],
    capitalizedTypes: false
  )

  /// Pascal and Object Pascal, as in THINK Pascal and Delphi, with types capitalized, as the Mac
  /// Toolbox's are.
  private static let pascal = Language(
    keywords: ["and", "array", "as", "asm", "begin", "case", "class", "const", "constructor", "destructor", "div", "do", "downto", "else", "end", "except", "exit", "external", "false", "file", "finally", "for", "forward", "function", "goto", "if", "implementation", "in", "inherited", "inline", "interface", "is", "label", "mod", "nil", "not", "object", "of", "on", "or", "override", "packed", "private", "procedure", "program", "property", "protected", "public", "published", "raise", "record", "repeat", "self", "set", "shl", "shr", "string", "then", "to", "true", "try", "type", "unit", "until", "uses", "var", "virtual", "while", "with", "xor"],
    keywordsIgnoreCase: true,
    lineComments: ["//"],
    blockComments: [("{", "}"), ("(*", "*)")],
    quotes: ["'"]
  )

  // MARK: Colors

  enum Token {
    case keyword, string, comment, number, type
  }

  /// Like Xcode's default theme, in light and dark.
  static func color(for token: Token) -> NSColor {
    switch token {
    case .keyword: return self.keywordColor
    case .string: return self.stringColor
    case .comment: return self.commentColor
    case .number: return self.numberColor
    case .type: return self.typeColor
    }
  }

  private static let keywordColor = Self.color(light: 0x9B2393, dark: 0xFC5FA3)
  private static let stringColor = Self.color(light: 0xC41A16, dark: 0xFC6A5D)
  private static let commentColor = Self.color(light: 0x5D6C79, dark: 0x7F8C98)
  private static let numberColor = Self.color(light: 0x1C00CF, dark: 0xD0BF69)
  private static let typeColor = Self.color(light: 0x3E8087, dark: 0x5DD8FF)

  private static func color(light: Int, dark: Int) -> NSColor {
    func rgb(_ value: Int) -> NSColor {
      NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    return NSColor(name: nil) { $0.isDark ? rgb(dark) : rgb(light) }
  }

  // MARK: Highlighting

  /// Colors the code in `range` of `text`.
  static func highlight(_ text: NSMutableAttributedString, in range: NSRange, as language: Language) {
    let string = text.string as NSString
    let end = NSMaxRange(range)
    var index = range.location

    // Tokens as UTF-16, to compare with the text without making strings of it.
    let blockComments = language.blockComments.map { (open: Array($0.open.utf16), close: $0.close) }
    let lineComments = language.lineComments.map { (units: Array($0.utf16), word: $0.first?.isLetter == true ? $0.lowercased() : nil) }
    let keySeparator = language.keySeparator?.utf16.first
    let longStrings = language.longStrings.map { (open: Array($0.open.utf16), close: $0.close) }
    let quotes = language.quotes.map { Array($0.utf16) }

    func starts(_ token: [unichar], at position: Int) -> Bool {
      guard position + token.count <= end else {
        return false
      }
      for (offset, unit) in token.enumerated() where string.character(at: position + offset) != unit {
        return false
      }
      return true
    }
    func isLineBreak(_ position: Int) -> Bool {
      let character = string.character(at: position)
      return character == 0x0A || character == 0x0D || character == 0x2028
    }
    func lineEnd(from position: Int) -> Int {
      var position = position
      while position < end && !isLineBreak(position) {
        position += 1
      }
      return position
    }
    func isWordCharacter(_ position: Int) -> Bool {
      guard position >= range.location, position < end, let scalar = Unicode.Scalar(string.character(at: position)) else {
        return false
      }
      return CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
    }
    func color(_ from: Int, _ to: Int, _ token: Token) {
      text.addAttribute(.foregroundColor, value: self.color(for: token), range: NSRange(location: from, length: to - from))
    }
    func isSpace(_ position: Int) -> Bool {
      position < end && [0x20, 0x09].contains(string.character(at: position))
    }
    /// Whether a comment that runs to the end of the line starts at `position`. One that's a word,
    /// like BASIC's REM, does whatever its case, on its own. A # comment starts a word, unlike the #
    /// in ${#list[@]}.
    func startsLineComment(at position: Int) -> Bool {
      lineComments.contains { marker in
        let length = marker.units.count
        if let word = marker.word {
          return position + length <= end && !isWordCharacter(position - 1) && !isWordCharacter(position + length)
            && string.substring(with: NSRange(location: position, length: length)).lowercased() == word
        }
        return starts(marker.units, at: position)
          && (marker.units != [0x23] || !(isWordCharacter(position - 1) || (position > range.location && [0x24, 0x7B].contains(string.character(at: position - 1)))))
      }
    }
    /// Where the key a line starts with ends, if it starts with one: a name of letters, digits,
    /// spaces, and _ - and ., then the separator, which for a : has a space or the end of the line
    /// after it, so a URL isn't a key.
    func keyEnd(from position: Int, separator: unichar) -> Int? {
      var at = position
      while at < end && !isLineBreak(at) {
        let character = string.character(at: at)
        if character == separator {
          if separator == 0x3A, at + 1 < end, !isLineBreak(at + 1), !isSpace(at + 1) {
            return nil
          }
          var keyEnd = at
          while keyEnd > position && isSpace(keyEnd - 1) {
            keyEnd -= 1
          }
          return keyEnd > position ? keyEnd : nil
        }
        guard isWordCharacter(at) || isSpace(at) || character == 0x2D || character == 0x2E else {
          return nil
        }
        at += 1
      }
      return nil
    }

    var atLineStart = true
    while index < end {
      if isLineBreak(index) {
        atLineStart = true
        index += 1
        continue
      }
      let wasAtLineStart = atLineStart
      if !(string.character(at: index) == 0x20 || string.character(at: index) == 0x09) {
        atLineStart = false
      }

      // Comments, longest first, since Lua's --[[ starts like its --.
      if let block = blockComments.first(where: { starts($0.open, at: index) }) {
        let start = index + block.open.count
        let close = string.range(of: block.close, options: .literal, range: NSRange(location: start, length: end - start))
        let stop = close.location == NSNotFound ? end : NSMaxRange(close)
        color(index, stop, .comment)
        index = stop
        continue
      }
      if startsLineComment(at: index) {
        let stop = lineEnd(from: index)
        color(index, stop, .comment)
        index = stop
        continue
      }
      if language.preprocessor && wasAtLineStart && string.character(at: index) == 0x23 {
        let stop = lineEnd(from: index)
        color(index, stop, .keyword)
        index = stop
        continue
      }

      // Keys and sections in settings files, at the start of a line.
      if let separator = keySeparator, wasAtLineStart, !isSpace(index) {
        // After the - of an item in a YAML list.
        if string.character(at: index) == 0x2D && isSpace(index + 1) {
          atLineStart = true
          index += 2
          continue
        }
        if let stop = keyEnd(from: index, separator: separator) {
          color(index, stop, .type)
          index = stop
          continue
        }
      }
      if language.sections && wasAtLineStart && string.character(at: index) == 0x5B {
        // To the last ] on the line, for TOML's [[tables]] too.
        let stop = lineEnd(from: index)
        var close = stop
        while close > index + 1 && string.character(at: close - 1) != 0x5D {
          close -= 1
        }
        let sectionEnd = close > index + 1 ? close : stop
        color(index, sectionEnd, .keyword)
        index = sectionEnd
        continue
      }

      // Strings. One that isn't closed by the end of its line ends there.
      if let long = longStrings.first(where: { starts($0.open, at: index) }) {
        let start = index + long.open.count
        let close = string.range(of: long.close, options: .literal, range: NSRange(location: start, length: end - start))
        let stop = close.location == NSNotFound ? end : NSMaxRange(close)
        color(index, stop, .string)
        index = stop
        continue
      }
      if let quote = quotes.first(where: { starts($0, at: index) }) {
        var position = index + quote.count
        while position < end && !isLineBreak(position) {
          if string.character(at: position) == 0x5C && position + 1 < end && !isLineBreak(position + 1) {
            position += 2
            continue
          }
          position += 1
          if starts(quote, at: position - 1) {
            break
          }
        }
        color(index, position, .string)
        index = position
        continue
      }

      // Variables, numbers, and words.
      if language.dollarVariables && string.character(at: index) == 0x24 && isWordCharacter(index + 1) {
        var position = index + 1
        while isWordCharacter(position) {
          position += 1
        }
        color(index, position, .type)
        index = position
        continue
      }
      let scalar = Unicode.Scalar(string.character(at: index))
      if let scalar, CharacterSet.decimalDigits.contains(scalar), !isWordCharacter(index - 1) {
        var position = index + 1
        while position < end, let next = Unicode.Scalar(string.character(at: position)),
              CharacterSet.alphanumerics.contains(next) || next == "." || next == "_" {
          position += 1
        }
        color(index, position, .number)
        index = position
        continue
      }
      if isWordCharacter(index) {
        var position = index + 1
        while isWordCharacter(position) {
          position += 1
        }
        let word = string.substring(with: NSRange(location: index, length: position - index))
        if language.keywords.contains(language.keywordsIgnoreCase ? word.lowercased() : word) {
          color(index, position, .keyword)
        }
        else if language.capitalizedTypes, let first = word.unicodeScalars.first, CharacterSet.uppercaseLetters.contains(first) {
          color(index, position, .type)
        }
        index = position
        continue
      }
      index += 1
    }
  }
}
