import AppKit

/// Hands out the layout fragments for what Markdown's text can't draw on its own: code blocks'
/// backgrounds, with the language each names above it, quotes' bars and lines across, and the link
/// under the pointer, underlined. As a post's written, in the editor, where a code block's ```
/// lines are in it, or as it's shown, where they're gone.
class MarkdownFragments: NSObject, NSTextLayoutManagerDelegate {
  /// For the board's editor, where a code block's ``` lines are in it, and room enough above and
  /// below its code, and links aren't links yet.
  static func editor() -> MarkdownFragments {
    MarkdownFragments(codePadding: NSSize(width: Markdown.codePadding, height: Markdown.codeEditorPadding), underlinesLinks: false)
  }

  /// The link under the pointer, in characters, which the fragment holding it underlines.
  var hoveredLink: NSRange?
  /// The color of code blocks' languages, quotes' bars and lines across, in place of the system's
  /// tertiary color, as a server's theme has it.
  var tertiaryColor: NSColor = .tertiaryLabelColor
  /// Behind code blocks, as a server's theme has it, or the system's.
  var codeBackground: NSColor = Markdown.Colors.codeBlock

  /// Draws in a server's theme's colors, or the system's.
  func apply(_ colors: Markdown.Colors) {
    self.tertiaryColor = colors.tertiary
    self.codeBackground = colors.codeBlock
  }

  /// How far a code block's background reaches past its code: across, and above and below it.
  let codePadding: NSSize
  private let underlinesLinks: Bool

  init(codePadding: NSSize, underlinesLinks: Bool = true) {
    self.codePadding = codePadding
    self.underlinesLinks = underlinesLinks
  }

  /// For Markdown shown as `layout` has it.
  convenience init(layout: Markdown.Layout) {
    self.init(codePadding: layout.codePadding)
  }

  func textLayoutManager(_ textLayoutManager: NSTextLayoutManager, textLayoutFragmentFor location: any NSTextLocation, in textElement: NSTextElement) -> NSTextLayoutFragment {
    self.fragment(for: textElement) ?? NSTextLayoutFragment(textElement: textElement, range: textElement.elementRange)
  }

  /// The fragment for a paragraph with something to draw, or nil, for one with nothing.
  func fragment(for textElement: NSTextElement) -> MarkdownLineFragment? {
    guard let paragraph = textElement as? NSTextParagraph, paragraph.attributedString.length > 0 else {
      return nil
    }
    let attributes = paragraph.attributedString.attributes(at: 0, effectiveRange: nil)
    let fragment: MarkdownLineFragment
    if let line = (attributes[Markdown.codeLineKey] as? Int).flatMap(Markdown.CodeLine.init) {
      fragment = MarkdownCodeLineFragment(textElement: textElement, range: textElement.elementRange, line: line, language: attributes[Markdown.codeLanguageKey] as? String)
    }
    else if attributes[Markdown.quoteLineKey] != nil {
      fragment = MarkdownQuoteLineFragment(textElement: textElement, range: textElement.elementRange)
    }
    else if attributes[Markdown.ruleKey] != nil {
      fragment = MarkdownRuleFragment(textElement: textElement, range: textElement.elementRange)
    }
    else if self.underlinesLinks {
      fragment = MarkdownLineFragment(textElement: textElement, range: textElement.elementRange)
    }
    else {
      return nil
    }
    fragment.provider = self
    return fragment
  }
}

/// A paragraph of Markdown, which underlines the link under the pointer, if it's in it. TextKit 2
/// doesn't draw underlines added as rendering attributes, only colors, so the fragment draws its
/// own.
class MarkdownLineFragment: NSTextLayoutFragment {
  weak var provider: MarkdownFragments?

  /// How far in from the container's edges text starts.
  var lineFragmentPadding: CGFloat {
    self.textLayoutManager?.textContainer?.lineFragmentPadding ?? 0
  }

  /// How wide the container is.
  var containerWidth: CGFloat {
    self.textLayoutManager?.textContainer?.size.width ?? self.layoutFragmentFrame.width
  }

  /// The paragraph's style, as its first character has it.
  var paragraphStyle: NSParagraphStyle? {
    guard let text = (self.textElement as? NSTextParagraph)?.attributedString, text.length > 0 else {
      return nil
    }
    return text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    super.draw(at: point, in: context)
    self.drawHoveredLink(at: point, in: context)
  }

  private func drawHoveredLink(at point: CGPoint, in context: CGContext) {
    guard let link = self.provider?.hoveredLink,
          let contentManager = self.textLayoutManager?.textContentManager,
          let paragraph = self.textElement as? NSTextParagraph else {
      return
    }
    // The link's characters, counted from the start of this paragraph.
    let start = contentManager.offset(from: contentManager.documentRange.location, to: self.rangeInElement.location)
    let local = NSIntersectionRange(NSRange(location: link.location - start, length: link.length), NSRange(location: 0, length: paragraph.attributedString.length))
    guard local.length > 0 else {
      return
    }

    let pixel = abs(context.convertToUserSpace(CGSize(width: 1, height: 1)).height)
    context.saveGState()
    for line in self.textLineFragments {
      var range = NSIntersectionRange(line.characterRange, local)
      // Not under a file's icon.
      if range.length > 1, (line.attributedString.string as NSString).character(at: range.location) == 0xFFFC {
        range = NSRange(location: range.location + 1, length: range.length - 1)
      }
      guard range.length > 0 else {
        continue
      }
      let attributes = line.attributedString.attributes(at: range.location, effectiveRange: nil)
      let font = attributes[.font] as? NSFont ?? Markdown.font
      let color = attributes[.foregroundColor] as? NSColor ?? .textColor
      let left = line.locationForCharacter(at: range.location).x
      let right = line.locationForCharacter(at: NSMaxRange(range)).x
      // Below the baseline by the font's underline position, on whole pixels so it's crisp, with
      // the part of a pixel dropped the way the text drops it.
      let baseline = point.y + line.typographicBounds.minY + line.glyphOrigin.y
      let y = ((baseline - font.underlinePosition) / pixel).rounded(.down) * pixel
      let thickness = max(pixel, (font.underlineThickness / pixel).rounded() * pixel)
      context.setFillColor(color.cgColor)
      context.fill(CGRect(x: point.x + line.typographicBounds.minX + left, y: y, width: right - left, height: thickness))
    }
    context.restoreGState()
  }
}

/// A line of a code block, with its part of the block's background behind it, rounded at the top
/// of the block's first line and the bottom of its last, and square where its lines meet, so they
/// make one block. As it's shown, the language the block names is above its first line, small and
/// faint. In the editor, a block opening at the end of a line of words has its background behind
/// the ``` there too, joined to the block under it, with a rounded corner where they meet.
final class MarkdownCodeLineFragment: MarkdownLineFragment {
  /// Where the line is in its block.
  let line: Markdown.CodeLine
  /// The language the block names, shown above its code, on its first line.
  private let language: String?

  private static let cornerRadius: CGFloat = 6
  /// How far before a ``` at the end of a line of words its background starts.
  private static let fenceInset: CGFloat = 4

  private static var languageFont: NSFont {
    .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
  }

  init(textElement: NSTextElement, range: NSTextRange?, line: Markdown.CodeLine, language: String?) {
    self.line = line
    self.language = language
    super.init(textElement: textElement, range: range)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  /// Whether the line has the top of its block.
  var isTop: Bool {
    self.line == .first || self.line == .only || self.line == .opening
  }

  var isBottom: Bool {
    self.line.isBottom
  }

  /// Whether it's the first line of a block that opens at the end of the line above it, which its
  /// background goes on from.
  private var joinsAbove: Bool {
    self.line == .firstAfterOpening || self.line == .onlyAfterOpening
  }

  private var padding: NSSize {
    self.provider?.codePadding ?? NSSize(width: Markdown.codePadding, height: Markdown.codePadding)
  }

  /// Where the block's background stops on the right, across from where text starts.
  private var right: CGFloat {
    self.containerWidth - self.lineFragmentPadding - self.layoutFragmentFrame.minX
  }

  /// From where the code's lines start, less how far the background reaches past them, across to
  /// the other side, and from the top of the line to the top of the next, but for the block's first
  /// line, from the top of its text, and its language, as the room above the block isn't the
  /// block's, and for its last, to the bottom of its text, as the room below isn't either, and nor
  /// is a new line after it at the end, which its fragment has too. For words a block opens at the
  /// end of, from just before the ``` there, down to the block.
  var backgroundBounds: CGRect {
    let padding = self.padding
    if self.line == .opening {
      guard let fence = self.fence else {
        return .null
      }
      return CGRect(x: fence.x, y: fence.y, width: self.right - fence.x, height: self.layoutFragmentFrame.height - fence.y)
    }
    let indent = (self.paragraphStyle?.headIndent ?? padding.width) - padding.width
    let left = self.lineFragmentPadding + indent - self.layoutFragmentFrame.minX
    var top: CGFloat = 0
    var bottom = self.layoutFragmentFrame.height
    if self.isTop, let first = self.textLineFragments.first {
      top = first.typographicBounds.minY - padding.height - (self.language == nil ? 0 : Markdown.codeLanguageHeight)
    }
    if self.isBottom, let last = self.textLineFragments.last(where: { $0.characterRange.length > 0 }) {
      bottom = last.typographicBounds.maxY + padding.height
    }
    return CGRect(x: left, y: top, width: self.right - left, height: bottom - top)
  }

  /// Where the ``` a block opens with at the end of this line of words starts, a little before it,
  /// and the top of its line, less the room the block has above its text.
  private var fence: CGPoint? {
    guard let text = (self.textElement as? NSTextParagraph)?.attributedString else {
      return nil
    }
    var start: Int?
    text.enumerateAttribute(Markdown.codeFenceKey, in: NSRange(location: 0, length: text.length)) { value, range, stop in
      if value != nil {
        start = range.location
        stop.pointee = true
      }
    }
    guard let start, let line = self.textLineFragments.last(where: { $0.characterRange.location <= start }) else {
      return nil
    }
    return CGPoint(x: line.typographicBounds.minX + line.locationForCharacter(at: start).x - Self.fenceInset, y: line.typographicBounds.minY - self.padding.height)
  }

  /// The block's left edge, under words a block opens at the end of, where the lines under them
  /// start, as they're written in the editor.
  private var blockLeft: CGFloat {
    self.lineFragmentPadding - self.layoutFragmentFrame.minX
  }

  override var renderingSurfaceBounds: CGRect {
    var bounds = self.backgroundBounds
    // And the corner where the ``` meet the block, before them.
    if self.line == .opening, !bounds.isNull {
      bounds = bounds.union(CGRect(x: bounds.minX - Self.cornerRadius, y: bounds.maxY - Self.cornerRadius, width: Self.cornerRadius, height: Self.cornerRadius))
    }
    return bounds.isNull ? super.renderingSurfaceBounds : super.renderingSurfaceBounds.union(bounds)
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    let bounds = self.backgroundBounds
    guard !bounds.isNull else {
      super.draw(at: point, in: context)
      return
    }
    let rect = bounds.offsetBy(dx: point.x, dy: point.y)
    let radius = Self.cornerRadius
    let topLeft = self.isTop || self.joinsAbove ? radius : 0
    let topRight = self.isTop ? radius : 0
    let bottom = self.isBottom ? radius : 0
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + topLeft, y: rect.minY), radius: topLeft)
    path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + topRight), radius: topRight)
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom)
    path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom)
    path.closeSubpath()
    // Where the ``` meet the block under them, a corner curving into it, when there's room before
    // them for one.
    if self.line == .opening, bounds.minX - radius >= self.blockLeft {
      let corner = CGPoint(x: rect.minX, y: rect.maxY)
      path.move(to: CGPoint(x: corner.x, y: corner.y - radius))
      path.addLine(to: corner)
      path.addLine(to: CGPoint(x: corner.x - radius, y: corner.y))
      path.addQuadCurve(to: CGPoint(x: corner.x, y: corner.y - radius), control: corner)
      path.closeSubpath()
    }

    context.saveGState()
    context.addPath(path)
    context.setFillColor((self.provider?.codeBackground ?? Markdown.Colors.codeBlock).cgColor)
    context.fillPath()
    context.restoreGState()
    if self.line == .first || self.line == .only, let language = self.language {
      // In line with the code, in the room above it.
      let label = NSAttributedString(string: language, attributes: [
        .font: Self.languageFont,
        .foregroundColor: self.provider?.tertiaryColor ?? .tertiaryLabelColor,
      ])
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
      label.draw(at: CGPoint(x: rect.minX + self.padding.width, y: rect.minY + self.padding.height - 1))
      NSGraphicsContext.restoreGraphicsState()
    }
    super.draw(at: point, in: context)
  }
}

/// A line of a quote, with the bar along a quote's lines beside it, where its lines start, from the
/// top of the line to the top of the next, so a quote's lines make one bar.
final class MarkdownQuoteLineFragment: MarkdownLineFragment {
  private static let barWidth: CGFloat = 3

  /// Not beside a new line after the quote at the end, which the quote's last line's fragment has
  /// too, but which isn't the quote's.
  private var barBounds: CGRect {
    var height = self.layoutFragmentFrame.height
    if self.textLineFragments.count > 1, let last = self.textLineFragments.last, last.characterRange.length == 0 {
      height = last.typographicBounds.minY
    }
    let start = (self.paragraphStyle?.firstLineHeadIndent ?? Markdown.quoteIndent) - Markdown.quoteIndent
    return CGRect(x: self.lineFragmentPadding + start + 1 - self.layoutFragmentFrame.minX, y: 0, width: Self.barWidth, height: height)
  }

  override var renderingSurfaceBounds: CGRect {
    super.renderingSurfaceBounds.union(self.barBounds)
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    context.saveGState()
    context.setFillColor((self.provider?.tertiaryColor ?? .tertiaryLabelColor).cgColor)
    context.fill(self.barBounds.offsetBy(dx: point.x, dy: point.y))
    context.restoreGState()
    super.draw(at: point, in: context)
  }
}

/// A line across, through the middle of its line, from where lines start across to the other side,
/// one pixel tall.
final class MarkdownRuleFragment: MarkdownLineFragment {
  private var ruleBounds: CGRect {
    let line = self.textLineFragments.first?.typographicBounds ?? CGRect(x: 0, y: 0, width: 0, height: self.layoutFragmentFrame.height)
    let left = self.lineFragmentPadding + (self.paragraphStyle?.firstLineHeadIndent ?? 0) - self.layoutFragmentFrame.minX
    let right = self.containerWidth - self.lineFragmentPadding - self.layoutFragmentFrame.minX
    return CGRect(x: left, y: line.midY, width: max(0, right - left), height: 1)
  }

  override var renderingSurfaceBounds: CGRect {
    super.renderingSurfaceBounds.union(self.ruleBounds)
  }

  override func draw(at point: CGPoint, in context: CGContext) {
    let rect = self.ruleBounds.offsetBy(dx: point.x, dy: point.y)
    let pixel = abs(context.convertToUserSpace(CGSize(width: 1, height: 1)).height)
    context.saveGState()
    context.setFillColor((self.provider?.tertiaryColor ?? .tertiaryLabelColor).cgColor)
    context.fill(CGRect(x: rect.minX, y: (rect.minY / pixel).rounded(.down) * pixel, width: rect.width, height: pixel))
    context.restoreGState()
    super.draw(at: point, in: context)
  }
}
