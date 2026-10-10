import AppKit
import UniformTypeIdentifiers

/// A picture as a drawing, for a post, made of the characters the board finds drawings by, each one
/// the character that looks most like that part of the picture, as the board draws it. Where the
/// picture has an edge, that's the character whose shape is closest, as Alex Harri's "ASCII
/// characters are not pixels" has it, so edges stay sharp, and where it's flat, the one whose shade
/// is closest, from characters that look even when they repeat, so flat parts aren't striped. It's
/// no bigger than fits in a post without wrapping, and it's drawn for the background it's read on,
/// light, with what's dark in ink, or dark, with what's light in ink.
enum PostPicture {
  /// The most characters across and lines down a drawing of a picture is, which fit in a post.
  static let maximumColumns = 56
  static let maximumRows = 24

  /// What drawings are made of, but `, as three of them at the start of a line would start code.
  private static let characters: [Character] = Array(" |/\\_-=+*#@[]()<>{}^~.:;%&$")
  /// Those that look even when they repeat, for the picture's flat parts.
  private static let shades: Set<Character> = Set(" .:-=+*&$@#%")

  /// Each character's cell, in samples across and down.
  private static let across = 6, down = 12
  /// How dark the darkest of a picture is drawn, short of the darkest character, so a dark picture
  /// isn't all one dense block.
  private static let range: Float = 0.85
  /// How much more a cell's ink varies than this, of the darkest character's ink, makes it an edge,
  /// drawn by shape.
  private static let edge: Float = 0.12
  /// How much an edge's shade counts, beside its shape.
  private static let shadeWeight: Float = 2

  // MARK: Pictures

  /// The picture in a file, or on a pasteboard, as copied or dragged from an app, but not as part
  /// of rich text, which pastes as Markdown, and goes in as text.
  static func picture(on pasteboard: NSPasteboard) -> CGImage? {
    if let url = self.pictureFile(on: pasteboard) {
      return self.picture(at: url)
    }
    guard self.hasPictureData(pasteboard), let image = NSImage(pasteboard: pasteboard) else {
      return nil
    }
    return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
  }

  /// Whether there's a picture on a pasteboard, without reading it, as a drag goes over the editor.
  static func hasPicture(_ pasteboard: NSPasteboard) -> Bool {
    self.pictureFile(on: pasteboard) != nil || self.hasPictureData(pasteboard)
  }

  private static func pictureFile(on pasteboard: NSPasteboard) -> URL? {
    let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true, .urlReadingContentsConformToTypes: [UTType.image.identifier]]
    return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
  }

  private static func hasPictureData(_ pasteboard: NSPasteboard) -> Bool {
    let types = pasteboard.types ?? []
    let rich: [NSPasteboard.PasteboardType] = [.rtf, .rtfd, .html]
    return !types.contains(where: rich.contains) && NSImage.canInit(with: pasteboard)
  }

  /// A picture file, read only as big as it's to be drawn, turned the way it's meant to be seen.
  private static func picture(at url: URL) -> CGImage? {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceThumbnailMaxPixelSize: 1024,
    ]
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
      return image
    }
    // Those Image I/O can't read, as SVG.
    return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
  }

  // MARK: Characters

  /// A character's cell, as the board lays out a drawing: as wide as the font's characters, as tall
  /// as a line, and how far down it the baseline is.
  private static let cell: (width: CGFloat, height: CGFloat, baseline: CGFloat) = {
    let font = PostMarkdown.codeFont
    let width = ("M" as NSString).size(withAttributes: [.font: font]).width
    let content = NSTextContentStorage()
    let layoutManager = NSTextLayoutManager()
    content.addTextLayoutManager(layoutManager)
    let container = NSTextContainer(size: NSSize(width: 1000, height: 1000))
    container.lineFragmentPadding = 0
    layoutManager.textContainer = container
    content.attributedString = NSAttributedString(string: "M\nM", attributes: [.font: font])
    var tops: [CGFloat] = []
    var baseline = font.ascender
    layoutManager.enumerateTextLayoutFragments(from: layoutManager.documentRange.location, options: .ensuresLayout) { fragment in
      if tops.isEmpty, let line = fragment.textLineFragments.first {
        baseline = line.typographicBounds.minY + line.glyphOrigin.y
      }
      tops.append(fragment.layoutFragmentFrame.minY)
      return true
    }
    let height = tops.count > 1 ? tops[1] - tops[0] : (font.ascender - font.descender).rounded(.up)
    return (width, height, baseline)
  }()

  private struct Glyph {
    let character: Character
    /// Its ink in each of its cell's samples, a little soft, as it looks from where it's read.
    let samples: [Float]
    let shade: Float
    let isEven: Bool
  }

  /// Each character, drawn as the board draws it, and sampled as a picture's cells are.
  private static let glyphs: [Glyph] = {
    let scale: CGFloat = 8
    let width = Int((cell.width * scale).rounded(.up)), height = Int((cell.height * scale).rounded(.up))
    let font = PostMarkdown.codeFont
    return characters.map { character in
      let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
      context.setFillColor(gray: 1, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      let line = CTLineCreateWithAttributedString(NSAttributedString(string: String(character), attributes: [.font: font, .foregroundColor: NSColor.black]))
      context.scaleBy(x: scale, y: scale)
      context.textPosition = CGPoint(x: 0, y: cell.height - cell.baseline)
      CTLineDraw(line, context)
      // The bitmap's top row comes first.
      let data = context.data!.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
      var samples = [Float](repeating: 0, count: across * down)
      for sampleY in 0..<down {
        for sampleX in 0..<across {
          let x0 = sampleX * width / across, x1 = (sampleX + 1) * width / across
          let y0 = sampleY * height / down, y1 = (sampleY + 1) * height / down
          var ink: Float = 0
          for y in y0..<y1 {
            for x in x0..<x1 {
              ink += 1 - Float(data[y * context.bytesPerRow + x]) / 255
            }
          }
          samples[sampleY * across + sampleX] = ink / Float((x1 - x0) * (y1 - y0))
        }
      }
      samples = PostPicture.softened(samples)
      return Glyph(character: character, samples: samples, shade: samples.reduce(0, +) / Float(samples.count), isEven: shades.contains(character))
    }
  }()

  /// A cell's samples, a little blurred, as characters look from where they're read.
  private static func softened(_ samples: [Float]) -> [Float] {
    let weights: [Float] = [0.46, 1, 0.46]
    func pass(_ values: [Float], across horizontal: Bool) -> [Float] {
      var out = values
      for y in 0..<down {
        for x in 0..<across {
          var sum: Float = 0, total: Float = 0
          for (k, offset) in (-1...1).enumerated() {
            let nx = horizontal ? x + offset : x, ny = horizontal ? y : y + offset
            guard nx >= 0, nx < across, ny >= 0, ny < down else {
              continue
            }
            sum += values[ny * across + nx] * weights[k]
            total += weights[k]
          }
          out[y * across + x] = sum / total
        }
      }
      return out
    }
    return pass(pass(samples, across: true), across: false)
  }

  // MARK: Drawing

  /// A picture as a drawing, as big as fits, on lines of its own, without the spaces after what's
  /// drawn on each or the blank lines above and below it.
  static func drawing(of image: CGImage, onDark: Bool) -> String {
    guard image.width > 0, image.height > 0 else {
      return ""
    }
    let aspect = CGFloat(image.height) / CGFloat(image.width)
    var columns = self.maximumColumns
    var rows = Int((CGFloat(columns) * self.cell.width * aspect / self.cell.height).rounded())
    if rows > self.maximumRows {
      rows = self.maximumRows
      columns = Int((CGFloat(rows) * self.cell.height / (aspect * self.cell.width)).rounded())
    }
    columns = max(columns, 1)
    rows = max(rows, 1)

    let ink = self.ink(of: image, width: columns * self.across, height: rows * self.down, onDark: onDark)
    let darkest = (self.glyphs.map(\.shade).max() ?? 1) * self.range
    var lines: [String] = []
    for row in 0..<rows {
      var line = ""
      for column in 0..<columns {
        var patch = [Float](repeating: 0, count: self.across * self.down)
        for y in 0..<self.down {
          for x in 0..<self.across {
            patch[y * self.across + x] = ink[(row * self.down + y) * columns * self.across + column * self.across + x]
          }
        }
        patch = self.softened(patch).map { $0 * darkest }
        line.append(self.character(for: patch, darkest: darkest))
      }
      while line.last == " " {
        line.removeLast()
      }
      lines.append(line)
    }
    while lines.first?.isEmpty == true {
      lines.removeFirst()
    }
    while lines.last?.isEmpty == true {
      lines.removeLast()
    }
    return lines.joined(separator: "\n")
  }

  /// The character that looks most like a cell: by its shape and shade, where the cell has an
  /// edge, and by its shade alone, from those that look even repeated, where it's flat.
  private static func character(for patch: [Float], darkest: Float) -> Character {
    let shade = patch.reduce(0, +) / Float(patch.count)
    let variance = patch.reduce(0) { $0 + ($1 - shade) * ($1 - shade) } / Float(patch.count)
    let isEdge = variance.squareRoot() / (darkest / self.range) >= self.edge
    var best = self.glyphs[0], bestDistance = Float.infinity
    for glyph in self.glyphs where isEdge || glyph.isEven {
      let toShade = glyph.shade - shade
      var distance = toShade * toShade
      if isEdge {
        distance = 0
        for k in 0..<patch.count {
          let d = glyph.samples[k] - patch[k]
          distance += d * d
        }
        distance += self.shadeWeight * toShade * toShade * Float(patch.count)
      }
      if distance < bestDistance {
        best = glyph
        bestDistance = distance
      }
    }
    return best.character
  }

  /// How much ink each pixel of a picture takes, drawn `width` × `height`, from none to all: how
  /// dark it looks, or for a dark background, how light, with its transparent parts, and a plain
  /// background around it, as none, and stretched from the lightest of the rest to the darkest, but
  /// for the odd pixel.
  private static func ink(of image: CGImage, width: Int, height: Int, onDark: Bool) -> [Float] {
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
      return [Float](repeating: 0, count: width * height)
    }
    context.setFillColor(CGColor(gray: onDark ? 0 : 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    let data = context.data!.bindMemory(to: UInt8.self, capacity: context.bytesPerRow * height)
    func linear(_ value: UInt8) -> Float {
      let v = Float(value) / 255
      return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    var ink = [Float](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        let pixel = y * context.bytesPerRow + x * 4
        let luminance = 0.2126 * linear(data[pixel]) + 0.7152 * linear(data[pixel + 1]) + 0.0722 * linear(data[pixel + 2])
        // Lightness as it looks, as CIE L* has it, from 0 to 1.
        let lightness = luminance > 0.008856 ? (116 * pow(luminance, 1 / 3) - 16) / 100 : 9.033 * luminance
        ink[y * width + x] = onDark ? lightness : 1 - lightness
      }
    }
    self.clearBackground(&ink, width: width, height: height)
    let sorted = ink.sorted()
    let low = sorted[Int(Float(sorted.count - 1) * 0.02)], high = sorted[Int(Float(sorted.count - 1) * 0.995)]
    if high - low > 0.05 {
      ink = ink.map { min(max(($0 - low) / (high - low), 0), 1) }
    }
    return ink
  }

  /// A plain background as no ink, rather than a block of it, as a white one would be on a dark
  /// background, or a black one on a light one: the picture's commonest shade at its edges, when
  /// it's that white or black, and a good part of the edges are it, and what's of that shade that
  /// it reaches. What it's around, touching the edges, isn't as plain as that, or it isn't cleared,
  /// as a picture's subject, like a dark cat that fills it, has a texture to it.
  private static func clearBackground(_ ink: inout [Float], width: Int, height: Int) {
    guard width > 2, height > 2 else {
      return
    }
    var edges: [Int] = []
    for x in 0..<width {
      edges += [x, (height - 1) * width + x]
    }
    for y in 1..<(height - 1) {
      edges += [y * width, y * width + width - 1]
    }
    // The commonest shade at the edges, in twentieths.
    var counts = [Int](repeating: 0, count: 21)
    for pixel in edges {
      counts[Int((ink[pixel] * 20).rounded())] += 1
    }
    let commonest = counts.indices.max { counts[$0] < counts[$1] } ?? 0
    let background = Float(commonest) / 20
    let tolerance: Float = 0.08
    let share = Float(edges.filter { abs(ink[$0] - background) <= tolerance }.count) / Float(edges.count)
    guard background >= 0.85, share >= 0.25 else {
      return
    }
    var reached = [Bool](repeating: false, count: width * height)
    var next = edges.filter { abs(ink[$0] - background) <= tolerance }
    for pixel in next {
      reached[pixel] = true
    }
    while let pixel = next.popLast() {
      ink[pixel] = 0
      let x = pixel % width, y = pixel / width
      for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
        let neighbor = ny * width + nx
        if !reached[neighbor], abs(ink[neighbor] - background) <= tolerance {
          reached[neighbor] = true
          next.append(neighbor)
        }
      }
    }
  }
}
