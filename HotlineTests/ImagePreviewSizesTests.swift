// ImagePreviewSizesTests

import Testing
import AppKit
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
    #expect(ImagePreview.previewSize(forImageSize: CGSize(width: 4000, height: 3000)) == CGSize(width: 240, height: 180))
    #expect(ImagePreview.previewSize(forImageSize: CGSize(width: 3000, height: 500)) == CGSize(width: 240, height: 40))
    // A phone's screenshot, as tall as there's room for.
    #expect(ImagePreview.previewSize(forImageSize: CGSize(width: 1170, height: 2532)) == CGSize(width: 92, height: 200))
  }

  @Test func unknownImagesGetThePlaceholder() {
    #expect(ImagePreview.previewSize(forImageSize: nil) == ImagePreview.placeholderSize)
  }

  // MARK: - Where Pictures Load From by Themselves

  @Test func picturesLoadByThemselvesOnlyFromWhereItsSafe() throws {
    let sources = ImagePreview.Sources(server: "hotline.example.com")
    func loads(_ link: String, isImage: Bool = false, in sources: ImagePreview.Sources = sources) -> Bool {
      sources.loadsByItself(URL(string: link)!, isImage: isImage)
    }
    // Image hosts, and the server's own address.
    #expect(loads("https://i.imgur.com/cat.png"))
    #expect(loads("https://hotline.example.com/banner.jpg"))
    #expect(loads("https://HOTLINE.example.com/banner.jpg"))
    // Not another under the same name, or a site of whoever posted it.
    #expect(!loads("https://evil.imgur.com/cat.png"))
    #expect(!loads("https://files.example.com/banner.jpg"))
    #expect(!loads("https://tracker.example/pixel.png"))
    // Nor without https, or for a link to something that isn't a picture, but for image search's
    // copies, which have no extension.
    #expect(!loads("http://i.imgur.com/cat.png"))
    #expect(!loads("https://raw.githubusercontent.com/someone/repo/main/README.md"))
    #expect(loads("https://encrypted-tbn0.gstatic.com/images?q=tbn:abc"))
    #expect(loads("https://external-content.duckduckgo.com/iu/?u=https://tracker.example/pixel.png"))
    // A picture written in Markdown, by where it is, whatever its extension.
    #expect(loads("https://i.imgur.com/cat", isImage: true))
    #expect(!loads("https://tracker.example/pixel", isImage: true))
    // Not the server's own in another server's window.
    #expect(!loads("https://hotline.example.com/banner.jpg", in: ImagePreview.Sources(server: "other.example.com")))
    // From any site, as Settings can have it.
    #expect(loads("https://tracker.example/pixel.png", in: ImagePreview.Sources(anySite: true)))
  }

  @Test func picturesFromSitesWhoseEveryHostIsTheirOwnLoadByThemselves() {
    let sources = ImagePreview.Sources()
    func loads(_ link: String) -> Bool {
      sources.loadsByItself(URL(string: link)!, isImage: false)
    }
    // The Internet Archive's downloads, and the server it sends them from, the Wayback Machine's
    // copies, and Flickr's older links.
    #expect(loads("https://archive.org/download/hypercard_what_is_hypercard_2/00_screenshot.png"))
    #expect(loads("https://dn721509.ca.archive.org/0/items/hypercard_what_is_hypercard_2/00_screenshot.png"))
    #expect(loads("https://web.archive.org/web/2001/http://www.apple.com/home/images/indexhero.jpg"))
    #expect(loads("https://farm1.staticflickr.com/2/1418878_1e92283336_m.jpg"))
    // Instagram's, Threads' and Facebook's pictures, from wherever Meta has them.
    #expect(loads("https://scontent-lax3-1.cdninstagram.com/v/t51.29350-15/123_n.jpg?stp=dst-jpg_e35&oh=00_AYB&oe=6745D2F1"))
    #expect(loads("https://instagram.fsjc1-3.fna.fbcdn.net/v/t51.2885-15/123_n.webp?oe=6745D2F1"))
    #expect(loads("https://scontent.xx.fbcdn.net/v/t39.30808-6/123_n.jpg?oe=6745D2F1"))
    // Not sites whose names only end the same way.
    #expect(!loads("https://notarchive.org/pic.png"))
    #expect(!loads("https://archive.org.example.com/pic.png"))
    #expect(!loads("https://notfbcdn.net/pic.jpg"))
    // Brave's image search copies, which have no extension.
    #expect(loads("https://imgs.search.brave.com/abc/rs:fit:500:0:0/g:ce/aHR0cHM6Ly9leGFtcGxlLmNvbQ"))
  }

  @Test func redditsViewerLinksShowThePictureInThem() {
    let sources = ImagePreview.Sources()
    let picture = URL(string: "https://i.redd.it/z6bs0bgwzst91.jpg")!
    let viewer = "https://www.reddit.com/media?url=https%3A%2F%2Fi.redd.it%2Fz6bs0bgwzst91.jpg"
    #expect(sources.picture(for: URL(string: viewer)!, isImage: false) == picture)
    #expect(sources.picture(for: picture, isImage: false) == picture)
    // Only a picture from where it could load by itself anyway, and only in Reddit's.
    #expect(sources.picture(for: URL(string: "https://www.reddit.com/media?url=https%3A%2F%2Ftracker.example%2Fpixel.png")!, isImage: false) == nil)
    #expect(sources.picture(for: URL(string: "https://reddit.com.example/media?url=https%3A%2F%2Fi.redd.it%2Fz6bs0bgwzst91.jpg")!, isImage: false) == nil)
    // Shown under the line its link is on, as any picture's is.
    let shown = Markdown.shownText("look \(viewer)", layout: .board)
    var previews: [URL] = []
    shown.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
      if let attachment = value as? ImageAttachment {
        previews.append(attachment.url)
      }
    }
    #expect(previews == [picture])
  }

  @Test func redirectsOnlyToWhereTheyCouldLoadFrom() {
    let sources = ImagePreview.Sources(server: "hotline.example.com")
    #expect(sources.trusts(URL(string: "https://i.imgur.com/removed.png")!))
    #expect(sources.trusts(URL(string: "https://hotline.example.com/moved.png")!))
    #expect(!sources.trusts(URL(string: "https://tracker.example/pixel")!))
  }

  @Test func markdownPicturesFromElsewhereStayLinks() {
    func previews(_ text: String) -> Int {
      let shown = Markdown.shownText(text, layout: .board)
      var count = 0
      shown.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
        count += value is ImageAttachment ? 1 : 0
      }
      return count
    }
    #expect(previews("![cat](https://i.imgur.com/cat.png)") == 1)
    #expect(previews("![cat](https://tracker.example/cat.png)") == 0)
    #expect(Markdown.shownText("![cat](https://tracker.example/cat.png)", layout: .board).string.contains("cat"))
  }

  // MARK: - The Setting

  @Test func previewsTurnedOffBeforeThereWereChoicesStayOff() throws {
    // A scratch set of settings, never the app's own.
    let suite = "ImagePreviewSizesTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    // Never set, from well-known sites.
    #expect(ImagePreviews.saved(in: defaults) == .wellKnownSites)
    // Set before, off stays off, and on is from well-known sites.
    defaults.set(false, forKey: PrefsKeys.previewChatImages.rawValue)
    #expect(ImagePreviews.saved(in: defaults) == .never)
    defaults.set(true, forKey: PrefsKeys.previewChatImages.rawValue)
    #expect(ImagePreviews.saved(in: defaults) == .wellKnownSites)
    // As it's set now, whatever previews were before.
    defaults.set(false, forKey: PrefsKeys.previewChatImages.rawValue)
    defaults.set(ImagePreviews.anySite.rawValue, forKey: PrefsKeys.imagePreviews.rawValue)
    #expect(ImagePreviews.saved(in: defaults) == .anySite)
  }
}
