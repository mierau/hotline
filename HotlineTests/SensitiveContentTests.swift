// SensitiveContentTests

import Testing
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import Hotline

struct SensitiveContentTests {
  /// Sharp black and white stripes, which blurring should leave nothing of.
  private func stripes(width: Int = 400, height: Int = 300) throws -> CGImage {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.setFillColor(gray: 0, alpha: 1)
    for x in stride(from: 0, to: width, by: 8) {
      context.fill(CGRect(x: x, y: 0, width: 4, height: height))
    }
    return try #require(context.makeImage())
  }

  /// A picture's pixels, as gray.
  private func grays(of image: CGImage) throws -> [UInt8] {
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height)
    try pixels.withUnsafeMutableBytes { buffer in
      let context = try #require(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return pixels
  }

  @Test func blurredPicturesCantBeMadeOut() throws {
    let blurred = try #require(SensitiveContent.blurred(try self.stripes()))
    // Small, as there's nothing sharp left in it to need more.
    #expect(max(blurred.width, blurred.height) <= 256)
    // Black and white stripes come out an even gray, but for a little at its edges.
    let grays = try self.grays(of: blurred)
    let spread = Int(grays.max() ?? 0) - Int(grays.min() ?? 0)
    #expect(spread < 32, "From \(grays.min() ?? 0) to \(grays.max() ?? 0)")
  }

  @Test func animationsAreCheckedAlongTheirLength() throws {
    // Ten frames, each a shade lighter than the one before.
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, 10, nil))
    for index in 0..<10 {
      let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
      context.setFillColor(gray: CGFloat(index) / 10, alpha: 1)
      context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
      CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    }
    #expect(CGImageDestinationFinalize(destination))

    // Four of them, from along it, rather than only the first, which can be harmless.
    let shades = try SensitiveContent.frames(of: data as Data).map { frame in
      Int((Double(try self.grays(of: frame)[0]) / 255 * 10).rounded())
    }
    #expect(shades == [0, 2, 5, 7])
  }

  @Test func aBannerIsCheckedAgainOnceItChanges() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "Banner \(UUID().uuidString).png", directoryHint: .notDirectory)
    defer {
      try? FileManager.default.removeItem(at: url)
    }
    try Data(repeating: 1, count: 10).write(to: url)
    let key = SensitiveContent.key(forFileAt: url)
    #expect(SensitiveContent.key(forFileAt: url) == key)

    try Data(repeating: 1, count: 20).write(to: url)
    #expect(SensitiveContent.key(forFileAt: url) != key)
  }
}
