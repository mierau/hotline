
//  ColorArt.swift
//  SLColorArt by Panic Inc.
//  Swift translation by Dustin Mierau
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

struct ColorArt: Equatable {
  let backgroundColor: NSColor
  let primaryColor: NSColor
  let secondaryColor: NSColor
  let detailColor: NSColor
  let scaledImage: NSImage

  static func == (lhs: ColorArt, rhs: ColorArt) -> Bool {
    return lhs.backgroundColor == rhs.backgroundColor &&
           lhs.primaryColor == rhs.primaryColor &&
           lhs.secondaryColor == rhs.secondaryColor &&
           lhs.detailColor == rhs.detailColor
  }

  init?(image: NSImage, scaledSize: NSSize = .zero) {
    let finalImage = Self.scaleImage(image, size: scaledSize)
    self.scaledImage = finalImage
    
    guard let colors = Self.analyzeImage(finalImage) else {
      return nil
    }
    
    self.backgroundColor = colors.background
    self.primaryColor = colors.primary
    self.secondaryColor = colors.secondary
    self.detailColor = colors.detail
  }
  
  // MARK: - Image Scaling
  
  private static func scaleImage(_ image: NSImage, size scaledSize: NSSize) -> NSImage {
    let imageSize = image.size
    let squareImage = NSImage(size: NSSize(width: imageSize.width, height: imageSize.width))
    var drawRect: NSRect
    
    // Make the image square
    if imageSize.height > imageSize.width {
      drawRect = NSRect(x: 0, y: imageSize.height - imageSize.width, width: imageSize.width, height: imageSize.width)
    } else {
      drawRect = NSRect(x: 0, y: 0, width: imageSize.height, height: imageSize.height)
    }
    
    // Use native square size if passed zero size
    let finalScaledSize = scaledSize == .zero ? drawRect.size : scaledSize
    let scaledImage = NSImage(size: finalScaledSize)
    
    squareImage.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: imageSize.width, height: imageSize.width), from: drawRect, operation: .sourceOver, fraction: 1.0)
    squareImage.unlockFocus()
    
    // Scale the image to the desired size
    scaledImage.lockFocus()
    squareImage.draw(in: NSRect(x: 0, y: 0, width: finalScaledSize.width, height: finalScaledSize.height), from: .zero, operation: .sourceOver, fraction: 1.0)
    scaledImage.unlockFocus()
    
    // Convert back to readable bitmap data
    guard let cgImage = scaledImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
      return scaledImage
    }
    
    let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
    let finalImage = NSImage(size: scaledImage.size)
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
    
    return (backgroundColor, primaryColor!, secondaryColor!, detailColor!)
  }
  
  // MARK: - Edge Color Detection
  
  private static func findEdgeColor(_ image: NSImage, imageColors: inout NSCountedSet?) -> NSColor? {
    guard var imageRep = image.representations.last else {
      return nil
    }
    
    if !(imageRep is NSBitmapImageRep) {
      image.lockFocus()
      imageRep = NSBitmapImageRep(focusedViewRect: NSRect(x: 0, y: 0, width: image.size.width, height: image.size.height))!
      image.unlockFocus()
    }
    
    // Convert to RGB color space
    guard let bitmapRep = (imageRep as? NSBitmapImageRep)?.converting(to: .genericRGB, renderingIntent: .default) else {
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
