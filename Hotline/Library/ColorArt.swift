
//  Swift translation and modernization
//  by Dustin Mierau
//
//  of:
//
//  ColorArt.swift
//  SLColorArt by Panic Inc.
//
//  Copyright (C) 2012 Panic Inc. Code by Wade Cosgrove. All rights reserved.
//
//  Redistribution and use, with or without modification, are permitted
//  provided that the following conditions are met:
//
//  - Redistributions must reproduce the above copyright notice, this list of
//    conditions and the following disclaimer in the documentation and/or other
//    materials provided with the distribution.
//
//  - Neither the name of Panic Inc nor the names of its contributors may be used
//    to endorse or promote works derived from this software without specific prior
//    written permission from Panic Inc.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
//  AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
//  ARE DISCLAIMED. IN NO EVENT SHALL PANIC INC BE LIABLE FOR ANY DIRECT, INDIRECT,
//  INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
//  PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
//  WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
//  POSSIBILITY OF SUCH DAMAGE.

import AppKit
import SwiftUI

// ColorArt.analyze(image: img) -> ColorArt?

struct ColorArt: Equatable {
  let backgroundColor: NSColor
  let primaryColor: NSColor
  let secondaryColor: NSColor
  let detailColor: NSColor
  /// The banner's color for theming things alongside its background, like a selection: the biggest
  /// part of it that's colorful and of another hue, or on a gray or black background, the biggest
  /// colorful part, like a logo. It's made to stand out against the background. Nil when the
  /// banner has nothing of another color.
  let accentColor: NSColor?
//  let scaledImage: NSImage

  static func == (lhs: ColorArt, rhs: ColorArt) -> Bool {
    return lhs.backgroundColor == rhs.backgroundColor &&
           lhs.primaryColor == rhs.primaryColor &&
           lhs.secondaryColor == rhs.secondaryColor &&
           lhs.detailColor == rhs.detailColor &&
           lhs.accentColor == rhs.accentColor
  }
  
  static func analyze(image: NSImage) -> ColorArt? {
    print("ColorArt.analyze: Starting, image size: \(image.size)")
    // Scale image to a reasonable size for analysis
    // This is important because:
    // 1. Makes analysis faster (fewer pixels)
    // 2. Normalizes weird image dimensions
    // 3. Ensures CGImage conversion succeeds
    print("ColorArt.analyze: Calling scaleImage...")
    let finalImage = Self.scaleImage(image, size: NSSize(width: 100, height: 100))
    print("ColorArt.analyze: scaleImage returned, scaled size: \(finalImage.size)")

    guard let colors = Self.analyzeImage(finalImage) else {
      print("ColorArt.analyze: failed with no colors")
      return nil
    }
    
    print("ColorArt.analyze: returning colors", colors)

    return ColorArt(backgroundColor: colors.background,
                    primaryColor: colors.primary,
                    secondaryColor: colors.secondary,
                    detailColor: colors.detail,
                    accentColor: colors.accent)
  }
  
  // MARK: - Image Scaling
  
  private static func scaleImage(_ image: NSImage, size scaledSize: NSSize) -> NSImage {
    print("ColorArt.scaleImage: Entered, input: \(image.size), target: \(scaledSize)")
    // Get CGImage directly without using lockFocus
    print("ColorArt.scaleImage: Getting CGImage...")
    guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      print("ColorArt.scaleImage: Failed to get CGImage, returning original")
      return image
    }
    print("ColorArt.scaleImage: Got CGImage")

    let imageSize = image.size
    let squareSize = min(imageSize.width, imageSize.height)

    // Use native square size if passed zero size
    let finalScaledSize = scaledSize == .zero ? NSSize(width: squareSize, height: squareSize) : scaledSize

    // Create bitmap context for drawing
    let width = Int(finalScaledSize.width)
    let height = Int(finalScaledSize.height)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

    guard let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: colorSpace,
      bitmapInfo: bitmapInfo.rawValue
    ) else {
      return image
    }

    // Draw the image scaled
    context.interpolationQuality = .high
    context.draw(cgImage, in: CGRect(x: 0, y: 0, width: finalScaledSize.width, height: finalScaledSize.height))

    // Create NSImage from context
    guard let scaledCGImage = context.makeImage() else {
      return image
    }

    let bitmapRep = NSBitmapImageRep(cgImage: scaledCGImage)
    let finalImage = NSImage(size: finalScaledSize)
    finalImage.addRepresentation(bitmapRep)

    return finalImage
  }
  
  // MARK: - Image Analysis
  
  private static func analyzeImage(_ image: NSImage) -> (background: NSColor, primary: NSColor, secondary: NSColor, detail: NSColor, accent: NSColor?)? {
    guard let colors = self.imageColors(image) else {
      return nil
    }
    // The background is the color covering the most of the banner, all of it, not just an edge,
    // which a logo or border can fill.
    let groups = self.colorGroups(colors)
    guard let backgroundColor = groups.first?.color else {
      return nil
    }
    
    let darkBackground = backgroundColor.isDarkColor
    var primaryColor: NSColor?
    var secondaryColor: NSColor?
    var detailColor: NSColor?
    
    self.findTextColors(colors, primaryColor: &primaryColor, secondaryColor: &secondaryColor, detailColor: &detailColor, backgroundColor: backgroundColor)
    
    // Fallback to black or white if colors not found
    if primaryColor == nil {
      primaryColor = darkBackground ? .white : .black
    }

    if secondaryColor == nil {
      secondaryColor = darkBackground ? .white : .black
    }

    if detailColor == nil {
      detailColor = darkBackground ? .white : .black
    }

    let accentColor = self.accentColor(in: groups, background: backgroundColor)

    // Convert all colors to calibrated RGB color space for consistency
    // This ensures all colors are in the same color space and prevents
    // any color space conversion issues when used in SwiftUI
    let rgbColorSpace = NSColorSpace.genericRGB
    let finalBackground = backgroundColor.usingColorSpace(rgbColorSpace) ?? backgroundColor
    let finalPrimary = primaryColor!.usingColorSpace(rgbColorSpace) ?? primaryColor!
    let finalSecondary = secondaryColor!.usingColorSpace(rgbColorSpace) ?? secondaryColor!
    let finalDetail = detailColor!.usingColorSpace(rgbColorSpace) ?? detailColor!
    let finalAccent = accentColor.map { $0.usingColorSpace(rgbColorSpace) ?? $0 }

    return (finalBackground, finalPrimary, finalSecondary, finalDetail, finalAccent)
  }
  
  // MARK: - Colors
  
  /// Every color in the image that isn't see-through, with how many of its pixels are that color.
  private static func imageColors(_ image: NSImage) -> NSCountedSet? {
    var bitmapRep: NSBitmapImageRep?

    // Try to get existing bitmap representation
    if let existingRep = image.representations.last as? NSBitmapImageRep {
      bitmapRep = existingRep
    } else {
      // Create bitmap rep from CGImage instead of using lockFocus
      guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        return nil
      }
      bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    }

    // Convert to RGB color space
    guard let bitmapRep = bitmapRep?.converting(to: .genericRGB, renderingIntent: .default) else {
      return nil
    }
    
    let colors = NSCountedSet(capacity: bitmapRep.pixelsWide * bitmapRep.pixelsHigh)
    for x in 0..<bitmapRep.pixelsWide {
      for y in 0..<bitmapRep.pixelsHigh {
        if let color = bitmapRep.colorAt(x: x, y: y), color.alphaComponent > CGFloat.ulpOfOne {
          colors.add(color)
        }
      }
    }
    return colors.count > 0 ? colors : nil
  }
  
  /// Colors close enough to look the same, together, with how many pixels they cover.
  private struct ColorGroup {
    var count = 0
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0

    /// Their average.
    var color: NSColor {
      NSColor(colorSpace: .genericRGB, components: [self.red / CGFloat(self.count), self.green / CGFloat(self.count), self.blue / CGFloat(self.count), 1], count: 4)
    }

    mutating func add(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, count: Int) {
      self.count += count
      self.red += red * CGFloat(count)
      self.green += green * CGFloat(count)
      self.blue += blue * CGFloat(count)
    }

    mutating func add(_ other: ColorGroup) {
      self.count += other.count
      self.red += other.red
      self.green += other.green
      self.blue += other.blue
    }

    func isClose(to other: ColorGroup) -> Bool {
      let count = CGFloat(self.count), otherCount = CGFloat(other.count)
      return abs(self.red / count - other.red / otherCount) + abs(self.green / count - other.green / otherCount) + abs(self.blue / count - other.blue / otherCount) < 0.12
    }
  }

  /// The image's colors in groups of about the same color, the biggest first, so a color that noise
  /// or dithering has split into many close shades counts as the one it looks like. Colors are put
  /// in eight steps of red, green and blue, then steps whose colors are close, joined.
  private static func colorGroups(_ colors: NSCountedSet) -> [ColorGroup] {
    var steps: [Int: ColorGroup] = [:]
    for case let color as NSColor in colors {
      guard color.alphaComponent > 0.5, let rgb = color.usingColorSpace(.genericRGB) else {
        continue
      }
      let step = Int(rgb.redComponent * 7.999) << 6 | Int(rgb.greenComponent * 7.999) << 3 | Int(rgb.blueComponent * 7.999)
      steps[step, default: ColorGroup()].add(rgb.redComponent, rgb.greenComponent, rgb.blueComponent, count: colors.count(for: color))
    }
    var groups: [ColorGroup] = []
    for step in steps.values.sorted(by: { $0.count > $1.count }) {
      if let index = groups.firstIndex(where: { $0.isClose(to: step) }) {
        groups[index].add(step)
      }
      else {
        groups.append(step)
      }
    }
    return groups.sorted { $0.count > $1.count }
  }

  /// The biggest group that's colorful, at least half a percent of the image, so not a speck, and
  /// of another hue than the background, or on a gray or nearly black background, any colorful
  /// one. Made to stand out against the background: if it's too near its brightness, it's made
  /// deeper on a bright background and brighter on a dark one, and a little more colorful.
  private static func accentColor(in groups: [ColorGroup], background: NSColor) -> NSColor? {
    guard let background = background.usingColorSpace(.genericRGB) else {
      return nil
    }
    let total = groups.reduce(0) { $0 + $1.count }
    // Nearly black has no hue to speak of, whatever its saturation works out to.
    let grayBackground = background.saturationComponent < 0.15 || background.brightnessComponent < 0.2
    for group in groups.dropFirst() where CGFloat(group.count) >= CGFloat(total) * 0.005 {
      guard let color = group.color.usingColorSpace(.genericRGB), color.saturationComponent >= 0.2 else {
        continue
      }
      let hueDistance = abs(color.hueComponent - background.hueComponent)
      guard grayBackground || min(hueDistance, 1 - hueDistance) >= 25 / 360 else {
        continue
      }
      let brightness = background.brightnessComponent
      guard abs(color.brightnessComponent - brightness) < 0.3 else {
        return color
      }
      return NSColor(colorSpace: .genericRGB, hue: color.hueComponent, saturation: min(color.saturationComponent + 0.15, 1), brightness: brightness >= 0.55 ? brightness - 0.3 : min(brightness + 0.3, 1), alpha: 1)
    }
    return nil
  }
  
  // MARK: - Text Color Detection
  
  private static func findTextColors(_ colors: NSCountedSet, primaryColor: inout NSColor?, secondaryColor: inout NSColor?, detailColor: inout NSColor?, backgroundColor: NSColor) {
    var sortedColors: [CountedColor] = []
    let findDarkTextColor = !backgroundColor.isDarkColor
    
    for color in colors {
      guard let nsColor = color as? NSColor else { continue }
      let adjustedColor = nsColor.withMinimumSaturation(0.15)
      
      if adjustedColor.isDarkColor == findDarkTextColor {
        let colorCount = colors.count(for: nsColor)
        sortedColors.append(CountedColor(color: adjustedColor, count: colorCount))
      }
    }
    
    sortedColors.sort { $0.count > $1.count }
    
    for container in sortedColors {
      let curColor = container.color
      
      if primaryColor == nil {
        if curColor.isContrasting(to: backgroundColor) {
          primaryColor = curColor
        }
      } else if secondaryColor == nil {
        if let primary = primaryColor,
           primary.isDistinct(from: curColor) && curColor.isContrasting(to: backgroundColor) {
          secondaryColor = curColor
        }
      } else if detailColor == nil {
        if let primary = primaryColor,
           let secondary = secondaryColor,
           secondary.isDistinct(from: curColor) &&
            primary.isDistinct(from: curColor) &&
            curColor.isContrasting(to: backgroundColor) {
          detailColor = curColor
          break
        }
      }
    }
  }
}

extension ColorArt {
  /// Whether the banner's background is white, or nearly, or a light gray: no color to speak of.
  var hasPlainLightBackground: Bool {
    guard let color = self.backgroundColor.usingColorSpace(.genericRGB) else {
      return false
    }
    return color.saturationComponent < 0.12 && color.brightnessComponent > 0.7
  }
}

// MARK: - Helper Classes

fileprivate struct CountedColor {
  let color: NSColor
  let count: Int
}

// MARK: - NSColor Extensions

extension NSColor {
  var isDarkColor: Bool {
    guard let convertedColor = usingColorSpace(.genericRGB) else {
      return false
    }
    
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    
    let lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    
    return lum < 0.5
  }
  
  func isDistinct(from compareColor: NSColor) -> Bool {
    guard let convertedColor = usingColorSpace(.genericRGB),
          let convertedCompareColor = compareColor.usingColorSpace(.genericRGB)
    else {
      return false
    }
    
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
    
    convertedColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    convertedCompareColor.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
    
    let threshold: CGFloat = 0.25
    
    if abs(r - r1) > threshold || abs(g - g1) > threshold || abs(b - b1) > threshold || abs(a - a1) > threshold {
      // Check for grays, prevent multiple gray colors
      if abs(r - g) < 0.03 && abs(r - b) < 0.03 {
        if abs(r1 - g1) < 0.03 && abs(r1 - b1) < 0.03 {
          return false
        }
      }
      
      return true
    }
    
    return false
  }
  
  func withMinimumSaturation(_ minSaturation: CGFloat) -> NSColor {
    guard let tempColor = usingColorSpace(.genericRGB) else {
      return self
    }
    
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    tempColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    
    if saturation < minSaturation {
      return NSColor(calibratedHue: hue, saturation: minSaturation, brightness: brightness, alpha: alpha)
    }
    
    return self
  }
  
  func isContrasting(to color: NSColor) -> Bool {
    guard let backgroundColor = usingColorSpace(.genericRGB),
          let foregroundColor = color.usingColorSpace(.genericRGB)
    else {
      return true
    }
    
    var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
    var fr: CGFloat = 0, fg: CGFloat = 0, fb: CGFloat = 0, fa: CGFloat = 0
    
    backgroundColor.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
    foregroundColor.getRed(&fr, green: &fg, blue: &fb, alpha: &fa)
    
    let bLum = 0.2126 * br + 0.7152 * bg + 0.0722 * bb
    let fLum = 0.2126 * fr + 0.7152 * fg + 0.0722 * fb
    
    let contrast: CGFloat
    if bLum > fLum {
      contrast = (bLum + 0.05) / (fLum + 0.05)
    } else {
      contrast = (fLum + 0.05) / (bLum + 0.05)
    }
    
    return contrast > 1.6
  }
}
