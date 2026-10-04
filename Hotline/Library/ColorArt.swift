
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

fileprivate let kColorThresholdMinimumPercentage: CGFloat = 0.001

// ColorArt.analyze(image: img) -> ColorArt?

struct ColorArt: Equatable {
  let backgroundColor: NSColor
  let primaryColor: NSColor
  let secondaryColor: NSColor
  let detailColor: NSColor
//  let scaledImage: NSImage

  static func == (lhs: ColorArt, rhs: ColorArt) -> Bool {
    return lhs.backgroundColor == rhs.backgroundColor &&
           lhs.primaryColor == rhs.primaryColor &&
           lhs.secondaryColor == rhs.secondaryColor &&
           lhs.detailColor == rhs.detailColor
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
                    detailColor: colors.detail)
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
  
  private static func analyzeImage(_ image: NSImage) -> (background: NSColor, primary: NSColor, secondary: NSColor, detail: NSColor)? {
    var imageColors: NSCountedSet?
    guard let backgroundColor = self.findEdgeColor(image, imageColors: &imageColors),
          let colors = imageColors
    else {
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

    // Convert all colors to calibrated RGB color space for consistency
    // This ensures all colors are in the same color space and prevents
    // any color space conversion issues when used in SwiftUI
    let rgbColorSpace = NSColorSpace.genericRGB
    let finalBackground = backgroundColor.usingColorSpace(rgbColorSpace) ?? backgroundColor
    let finalPrimary = primaryColor!.usingColorSpace(rgbColorSpace) ?? primaryColor!
    let finalSecondary = secondaryColor!.usingColorSpace(rgbColorSpace) ?? secondaryColor!
    let finalDetail = detailColor!.usingColorSpace(rgbColorSpace) ?? detailColor!

    return (finalBackground, finalPrimary, finalSecondary, finalDetail)
  }
  
  // MARK: - Edge Color Detection
  
  private static func findEdgeColor(_ image: NSImage, imageColors: inout NSCountedSet?) -> NSColor? {
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
    
    let pixelsWide = bitmapRep.pixelsWide
    let pixelsHigh = bitmapRep.pixelsHigh
    
    let colors = NSCountedSet(capacity: pixelsWide * pixelsHigh)
    let leftEdgeColors = NSCountedSet(capacity: pixelsHigh)
    var searchColumnX = 0
    
    for x in 0..<pixelsWide {
      for y in 0..<pixelsHigh {
        guard let color = bitmapRep.colorAt(x: x, y: y) else { continue }
        
        if x == searchColumnX {
          // Make sure it's a meaningful color
          if color.alphaComponent > 0.5 {
            leftEdgeColors.add(color)
          }
        }
        
        if color.alphaComponent > CGFloat.ulpOfOne {
          colors.add(color)
        }
      }
      
      // Background is clear, keep looking in next column for background color
      if leftEdgeColors.count == 0 {
        searchColumnX += 1
      }
    }
    
    imageColors = colors
    
    var sortedColors: [CountedColor] = []
    
    for color in leftEdgeColors {
      guard let nsColor = color as? NSColor else { continue }
      let colorCount = leftEdgeColors.count(for: nsColor)
      
      let randomColorsThreshold = Int(CGFloat(pixelsHigh) * kColorThresholdMinimumPercentage)
      
      if colorCount <= randomColorsThreshold {
        continue
      }
      
      sortedColors.append(CountedColor(color: nsColor, count: colorCount))
    }
    
    sortedColors.sort { $0.count > $1.count }
    
    guard var proposedEdgeColor = sortedColors.first else {
      return nil
    }
    
    // Want to choose color over black/white so we keep looking
    if proposedEdgeColor.color.isBlackOrWhite {
      for i in 1..<sortedColors.count {
        let nextProposedColor = sortedColors[i]
        
        // Make sure the second choice color is 30% as common as the first choice
        if Double(nextProposedColor.count) / Double(proposedEdgeColor.count) > 0.3 {
          if !nextProposedColor.color.isBlackOrWhite {
            proposedEdgeColor = nextProposedColor
            break
          }
        } else {
          // Reached color threshold less than 30% of the original proposed edge color
          break
        }
      }
    }
    
    return proposedEdgeColor.color
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
  /// The most colorful of the banner's colors for text, which are picked to stand out against its
  /// background, or nil if they're all close to gray, as the white and black they fall back to are.
  var accentColor: NSColor? {
    let saturation = { (color: NSColor) in color.usingColorSpace(.genericRGB)?.saturationComponent ?? 0 }
    return [self.primaryColor, self.secondaryColor, self.detailColor]
      .filter { saturation($0) >= 0.2 }
      .max { saturation($0) < saturation($1) }
  }

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
  
  var isBlackOrWhite: Bool {
    guard let tempColor = usingColorSpace(.genericRGB) else {
      return false
    }
    
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    tempColor.getRed(&r, green: &g, blue: &b, alpha: &a)
    
    // White
    if r > 0.91 && g > 0.91 && b > 0.91 {
      return true
    }
    
    // Black
    if r < 0.09 && g < 0.09 && b < 0.09 {
      return true
    }
    
    return false
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
