// ImagePreviewSizesTests

import Testing
import CoreGraphics
import Foundation
@testable import Hotline

struct ImagePreviewSizesTests {

  /// A sizes file in a scratch folder of its own.
  private func makeFile() -> URL {
    URL.temporaryDirectory
      .appending(path: "ImagePreviewSizesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
      .appending(path: "Sizes.plist", directoryHint: .notDirectory)
  }

  private let image = URL(string: "https://example.com/cat.png")!

  @Test func rememberedSizeIsFoundAgain() {
    let sizes = ImagePreviewSizes(fileURL: self.makeFile())
    #expect(sizes.size(for: self.image) == nil)
    sizes.remember(CGSize(width: 640, height: 480), for: self.image)
    #expect(sizes.size(for: self.image) == CGSize(width: 640, height: 480))
  }

  @Test func sizesLastBetweenLaunches() {
    let file = self.makeFile()
    defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }

    let sizes = ImagePreviewSizes(fileURL: file)
    sizes.remember(CGSize(width: 640, height: 480), for: self.image)
    sizes.save()
    #expect(ImagePreviewSizes(fileURL: file).size(for: self.image) == CGSize(width: 640, height: 480))
  }

  @Test func oldestSizesGoPastTheLimit() {
    let sizes = ImagePreviewSizes(fileURL: self.makeFile(), limit: 10)
    for i in 0...10 {
      sizes.remember(CGSize(width: 100 + i, height: 100), for: URL(string: "https://example.com/\(i).png")!)
    }
    #expect(sizes.size(for: URL(string: "https://example.com/0.png")!) == nil)
    #expect(sizes.size(for: URL(string: "https://example.com/10.png")!) == CGSize(width: 110, height: 100))
  }

  @Test func smallImagesShowAtTheirOwnSize() {
    #expect(ImagePreview.previewSize(forImageSize: CGSize(width: 64, height: 48)) == CGSize(width: 64, height: 48))
  }

  @Test func bigImagesFitWithinTheMaximum() {
    #expect(ImagePreview.previewSize(forImageSize: CGSize(width: 4000, height: 3000)) == CGSize(width: 160, height: 120))
    #expect(ImagePreview.previewSize(forImageSize: CGSize(width: 3000, height: 500)) == CGSize(width: 240, height: 40))
  }

  @Test func unknownImagesGetThePlaceholder() {
    #expect(ImagePreview.previewSize(forImageSize: nil) == ImagePreview.placeholderSize)
  }
}
