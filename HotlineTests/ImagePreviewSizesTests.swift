// ImagePreviewSizesTests

import Testing
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
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

  @Test func unreachableLinksAreTriedAgainOnceTheNetworksBack() {
    let failures = ImagePreviewFailures(fileURL: self.makeFile())
    let unreachable = URL(string: "https://example.com/down.png")!
    let refused = URL(string: "https://example.com/gone.png")!
    failures.insert(unreachable, refused: false)
    failures.insert(refused, refused: true)
    #expect(failures.contains(unreachable) && failures.contains(refused))
    // Back on a network, those that couldn't be reached are tried again, but not those refused.
    failures.forgetUnreachable()
    #expect(!failures.contains(unreachable))
    #expect(failures.contains(refused))
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

  /// A picture of a size, as a kind of file, turned as it says.
  private func encoded(_ type: UTType, width: Int, height: Int, orientation: Int = 1) -> Data {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(srgbRed: 0.3, green: 0.5, blue: 0.8, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, [kCGImagePropertyOrientation: orientation] as CFDictionary)
    CGImageDestinationFinalize(destination)
    return data as Data
  }

  @Test func picturesSayTheirSizeInTheirFirstBytes() {
    // A GIF and a PNG, by their headers' first few dozen bytes, and not before.
    let gif = self.encoded(.gif, width: 480, height: 270)
    #expect(ImagePreview.pixelSize(ofStart: gif.prefix(10)) == CGSize(width: 480, height: 270))
    #expect(ImagePreview.pixelSize(ofStart: gif.prefix(9)) == nil)
    let png = self.encoded(.png, width: 300, height: 200)
    #expect(ImagePreview.pixelSize(ofStart: png.prefix(24)) == CGSize(width: 300, height: 200))
    #expect(ImagePreview.pixelSize(ofStart: png.prefix(23)) == nil)
    // A JPEG, as ImageIO reads it, turned the way it says it is.
    #expect(ImagePreview.pixelSize(ofStart: self.encoded(.jpeg, width: 1200, height: 700).prefix(4096)) == CGSize(width: 1200, height: 700))
    #expect(ImagePreview.pixelSize(ofStart: self.encoded(.jpeg, width: 1200, height: 700, orientation: 6).prefix(4096)) == CGSize(width: 700, height: 1200))
    // A WebP of each kind: extended, as an animation is, lossy, and lossless.
    func webP(_ chunk: String, _ start: [UInt8]) -> Data {
      Data("RIFF".utf8) + Data([0, 0, 0, 0]) + Data("WEBP".utf8) + Data(chunk.utf8) + Data([0, 0, 0, 0]) + Data(start)
    }
    // 640 x 360, each less one, in three bytes, after its flags.
    #expect(ImagePreview.pixelSize(ofStart: webP("VP8X", [0x10, 0, 0, 0, 0x7F, 0x02, 0x00, 0x67, 0x01, 0x00])) == CGSize(width: 640, height: 360))
    // 320 x 240, after its frame tag and start code.
    #expect(ImagePreview.pixelSize(ofStart: webP("VP8 ", [0x10, 0x02, 0x00, 0x9D, 0x01, 0x2A, 0x40, 0x01, 0xF0, 0x00])) == CGSize(width: 320, height: 240))
    // 100 x 50, each less one, in 14 bits, after its signature.
    #expect(ImagePreview.pixelSize(ofStart: webP("VP8L", [0x2F, 0x63, 0x40, 0x0C, 0x00, 0, 0, 0, 0, 0])) == CGSize(width: 100, height: 50))
    // HEIC, which ImageIO only reads whole, and nothing.
    #expect(ImagePreview.pixelSize(ofStart: self.encoded(.heic, width: 300, height: 200).prefix(4096)) == nil)
    #expect(ImagePreview.pixelSize(ofStart: Data()) == nil)
  }

  @Test func picturesInNewerFormatsArePreviewed() {
    // AVIF and JPEG XL, which macOS reads, by their extensions, as other pictures are.
    #expect(ImagePreview.canPreview(URL(string: "https://example.com/photo.avif")!))
    #expect(ImagePreview.canPreview(URL(string: "https://example.com/photo.JXL")!))
    #expect(self.shown("look https://i.imgur.com/cat.avif").words == "look\n[preview]")
  }

  @Test func githubsPicturesLoadByThemselves() {
    let sources = ImagePreview.Sources()
    func loads(_ link: String) -> Bool {
      sources.loadsByItself(URL(string: link)!, isImage: false)
    }
    // A picture put up on GitHub, by the link it's given there, which has no extension, and from
    // before those, a repository's.
    let attachment = URL(string: "https://github.com/user-attachments/assets/30534bb1-4274-45c6-86cd-ed2bb1dd1d98")!
    #expect(sources.loadsByItself(attachment, isImage: false))
    #expect(ImagePreview.canPreview(attachment))
    #expect(loads("https://github.com/mierau/hotline/assets/55453/30534bb1-4274-45c6-86cd-ed2bb1dd1d98"))
    // Where those send you on to, for five minutes: signed in, and not.
    #expect(loads("https://private-user-images.githubusercontent.com/868228/329385740-80071c04-a800-42ce-bc4d-8cce52c4f2e3.png?jwt=abc"))
    #expect(sources.trusts(URL(string: "https://github-production-user-asset-6210df.s3.amazonaws.com/55453/552852784-30534bb1-4274-45c6-86cd-ed2bb1dd1d98.png?X-Amz-Signature=abc")!))
    // GitHub's copies of pictures from elsewhere, and a picture in a repository, by its extension.
    #expect(loads("https://camo.githubusercontent.com/4a1b2c/68747470733a2f2f6578616d706c652e636f6d2f6361742e706e67"))
    #expect(loads("https://github.com/mierau/hotline/raw/main/screenshot.png"))
    // Not GitHub's pages, or the other files put up there, or another bucket at Amazon, which
    // could be anyone's.
    #expect(!loads("https://github.com/mierau/hotline"))
    #expect(!loads("https://github.com/user-attachments/files/123/notes.zip"))
    #expect(!loads("https://github.com/mierau/hotline/assets/latest/thing"))
    #expect(!ImagePreview.canPreview(URL(string: "https://github.com/mierau/hotline")!))
    #expect(!sources.trusts(URL(string: "https://someone-else.s3.amazonaws.com/pixel.png")!))
    // Shown under the line its link is on, as any picture's is.
    let shown = Markdown.shownText("the board: \(attachment.absoluteString)", layout: .board)
    var previews: [URL] = []
    shown.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
      if let preview = value as? ImageAttachment {
        previews.append(preview.url)
      }
    }
    #expect(previews == [attachment])
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

  /// The picture shown for a link, by itself, as its address.
  private func picture(_ link: String, in sources: ImagePreview.Sources = ImagePreview.Sources()) -> String? {
    sources.picture(for: URL(string: link)!, isImage: false)?.absoluteString
  }

  @Test func giphysPagesAndCopiesShowItsWebP() {
    // A GIF's page, by its name and ID, or its ID alone, a sticker's, and an embed, as its WebP,
    // which is smaller.
    #expect(self.picture("https://giphy.com/gifs/dancing-dance-party-clubbing-blSTtZehjAZ8I") == "https://i.giphy.com/blSTtZehjAZ8I.webp")
    #expect(self.picture("https://giphy.com/gifs/WtDLxQWQWLtw3oIXTy/") == "https://i.giphy.com/WtDLxQWQWLtw3oIXTy.webp")
    #expect(self.picture("https://www.giphy.com/stickers/happy-cat-AbC123xyz?utm_source=share") == "https://i.giphy.com/AbC123xyz.webp")
    #expect(self.picture("https://giphy.com/embed/blSTtZehjAZ8I") == "https://i.giphy.com/blSTtZehjAZ8I.webp")
    // Its GIFs at their own size, and MP4 copies, the same, and a WebP as it is.
    #expect(self.picture("https://i.giphy.com/blSTtZehjAZ8I.gif") == "https://i.giphy.com/blSTtZehjAZ8I.webp")
    #expect(self.picture("https://media.giphy.com/media/blSTtZehjAZ8I/giphy.gif") == "https://i.giphy.com/blSTtZehjAZ8I.webp")
    #expect(self.picture("https://media4.giphy.com/media/v1.Y2lkPTc5MGI3NjEx/blSTtZehjAZ8I/giphy.mp4?cid=790b7611") == "https://i.giphy.com/blSTtZehjAZ8I.webp")
    #expect(self.picture("https://i.giphy.com/blSTtZehjAZ8I.webp") == "https://i.giphy.com/blSTtZehjAZ8I.webp")
    // Its GIFs at other sizes as they are, as some have no WebP, and not its other pages, or a site
    // only named the same.
    #expect(self.picture("https://media.giphy.com/media/blSTtZehjAZ8I/giphy-downsized.gif") == "https://media.giphy.com/media/blSTtZehjAZ8I/giphy-downsized.gif")
    #expect(self.picture("https://giphy.com/explore/cats") == nil)
    #expect(self.picture("https://giphy.com.example/gifs/cat-blSTtZehjAZ8I") == nil)
  }

  @Test func giphysGIFsPreviewedBeforeStayGIFs() {
    // As they're kept, and their sizes are known, rather than their WebP downloading.
    let gif = URL(string: "https://i.giphy.com/Zq9Xw8Vv7Uu6.gif")!
    ImagePreview.sizes.remember(CGSize(width: 480, height: 270), for: gif)
    defer {
      ImagePreview.sizes.forget(gif)
    }
    #expect(self.picture("https://giphy.com/gifs/Zq9Xw8Vv7Uu6") == gif.absoluteString)
    // Opened, or dragged out, as the GIF, whatever it's previewed as.
    #expect(ImagePreview.giphyGIF(for: URL(string: "https://i.giphy.com/blSTtZehjAZ8I.webp")!) == URL(string: "https://i.giphy.com/blSTtZehjAZ8I.gif"))
    #expect(ImagePreview.giphyGIF(for: URL(string: "https://media.giphy.com/media/blSTtZehjAZ8I/200.gif")!) == nil)
  }

  @Test func tenorsPagesShowTheGIFTheySendOnTo() {
    #expect(self.picture("https://tenor.com/view/40dollars-baby-boy-gif-10186449") == "https://tenor.com/view/40dollars-baby-boy-gif-10186449.gif")
    #expect(self.picture("https://tenor.com/en-GB/view/40dollars-baby-boy-gif-10186449/") == "https://tenor.com/en-GB/view/40dollars-baby-boy-gif-10186449.gif")
    #expect(self.picture("https://www.tenor.com/view/40dollars-baby-boy-gif-10186449") == "https://tenor.com/view/40dollars-baby-boy-gif-10186449.gif")
    // With .gif after it already, and Tenor's own GIFs, as they are.
    #expect(self.picture("https://tenor.com/view/40dollars-baby-boy-gif-10186449.gif") == "https://tenor.com/view/40dollars-baby-boy-gif-10186449.gif")
    #expect(self.picture("https://media1.tenor.com/m/tYiKvSqO2xAAAAAC/40dollars-baby-boy.gif") == "https://media1.tenor.com/m/tYiKvSqO2xAAAAAC/40dollars-baby-boy.gif")
    // Not its other pages.
    #expect(self.picture("https://tenor.com/search/cats-gifs") == nil)
    #expect(self.picture("https://tenor.com/view/cats") == nil)
  }

  @Test func imgursPagesAndVideosOfGIFsShowThePicture() {
    #expect(self.picture("https://imgur.com/mYNXTPw") == "https://i.imgur.com/mYNXTPw.gif")
    #expect(self.picture("https://i.imgur.com/mYNXTPw.gifv") == "https://i.imgur.com/mYNXTPw.gif")
    #expect(self.picture("https://i.imgur.com/mYNXTPw.mp4") == "https://i.imgur.com/mYNXTPw.gif")
    #expect(self.picture("https://i.imgur.com/mYNXTPw.jpg") == "https://i.imgur.com/mYNXTPw.jpg")
    // Not an album or a gallery, or Imgur's own pages.
    #expect(self.picture("https://imgur.com/a/mYNXTPw") == nil)
    #expect(self.picture("https://imgur.com/gallery/mYNXTPw") == nil)
    #expect(self.picture("https://imgur.com/upload") == nil)
    // Imgur's picture for one that's gone isn't one.
    #expect(ImagePreview.isGone(URL(string: "https://i.imgur.com/removed.png")))
    #expect(!ImagePreview.isGone(URL(string: "https://i.imgur.com/mYNXTPw.gif")))
  }

  @Test func gifSitesPagesShowUnderTheLineTheyreOn() {
    let shown = Markdown.shownText("lol https://giphy.com/gifs/dancing-dance-party-clubbing-blSTtZehjAZ8I", layout: .board)
    var previews: [URL] = []
    shown.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
      if let attachment = value as? ImageAttachment {
        previews.append(attachment.url)
      }
    }
    #expect(previews == [URL(string: "https://i.giphy.com/blSTtZehjAZ8I.webp")!])
  }

  @Test func giphysShortLinksLoadTheirAnimationByWhereTheySendYou() {
    // As they are, with no extension, as an animation, and found by where they send you on to.
    #expect(self.picture("https://gph.is/g/4LxX5Yp") == "https://gph.is/g/4LxX5Yp")
    #expect(self.picture("https://gph.is/145Id8I") == "https://gph.is/145Id8I")
    #expect(ImagePreview.mayBeAnimated(URL(string: "https://gph.is/g/4LxX5Yp")!))
    #expect(ImagePreview.picture(in: URL(string: "https://giphy.com/gifs/126bpm-dancingatclub-1NVtSIcr1PQnf7X2kG")!) == URL(string: "https://i.giphy.com/1NVtSIcr1PQnf7X2kG.webp"))
    // Not without https, or Giphy's own page.
    #expect(self.picture("http://gph.is/145Id8I") == nil)
    #expect(self.picture("https://gph.is/") == nil)
  }

  /// A GIF of so many frames, each a gray, shown for a twentieth of a second.
  private func gif(frames: Int, width: Int, height: Int) throws -> Data {
    let data = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames, nil))
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary
    for index in 0..<frames {
      context.setFillColor(CGColor(gray: CGFloat(index % 10) / 10, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: width, height: height))
      CGImageDestinationAddImage(destination, try #require(context.makeImage()), properties)
    }
    #expect(CGImageDestinationFinalize(destination))
    return data as Data
  }

  @Test func animationsAreDecodedWholeWhereTheyFit() throws {
    let bounds = CGSize(width: 120, height: 100)
    // Few frames, whole, at two pixels a point.
    let short = try #require(AnimationFrames(data: self.gif(frames: 100, width: 240, height: 200), fitting: bounds))
    #expect(short.isWhole && short.frames(0..<1, in: nil).first?.width == 240)
    #expect(short.durations.first == 0.05)
    // More, whole, at a pixel a point, which they fit at.
    let longer = try #require(AnimationFrames(data: self.gif(frames: 300, width: 240, height: 200), fitting: bounds))
    #expect(longer.isWhole && longer.frames(0..<1, in: nil).first?.width == 120)
    // Too many for either, in parts, at two.
    let long = try #require(AnimationFrames(data: self.gif(frames: 800, width: 240, height: 200), fitting: bounds))
    #expect(!long.isWhole && long.frames(0..<1, in: nil).first?.width == 240)
    // A picture of one frame isn't an animation.
    let still = try self.gif(frames: 1, width: 240, height: 200)
    #expect(AnimationFrames(data: still, fitting: bounds) == nil)
  }

  @Test func whatMightBeAnAnimationIsKeptWhole() {
    #expect(ImagePreview.mayBeAnimated(URL(string: "https://i.giphy.com/blSTtZehjAZ8I.gif")!))
    #expect(ImagePreview.mayBeAnimated(URL(string: "https://media.discordapp.net/attachments/1/2/dance.webp?animated=true")!))
    #expect(!ImagePreview.mayBeAnimated(URL(string: "https://i.imgur.com/cat.png")!))
  }

  // MARK: - Previews in Their Links' Places

  /// What's shown of some text, as its words, with a preview as a mark, and its previews.
  private func shown(_ text: String, layout: Markdown.Layout = .board) -> (words: String, previews: [ImageAttachment]) {
    let shown = Markdown.shownText(text, layout: layout)
    var previews: [ImageAttachment] = []
    shown.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
      if let attachment = value as? ImageAttachment {
        previews.append(attachment)
      }
    }
    let words = shown.string.replacingOccurrences(of: "\u{FFFC}", with: "[preview]").replacingOccurrences(of: "\u{2028}", with: "\n")
    return (words, previews)
  }

  @Test func anAddressWithAPreviewIsShownAsThePreview() throws {
    let page = "https://giphy.com/gifs/dancing-dance-party-clubbing-blSTtZehjAZ8I"
    // Alone, as the preview alone, and with words, under them, without the space before it.
    #expect(self.shown(page).words == "[preview]")
    #expect(self.shown("lol \(page)").words == "lol\n[preview]")
    #expect(self.shown("look \(page) here").words == "look here\n[preview]")
    // Standing for the link, as it was written, which it shows should its image not be had.
    let preview = try #require(self.shown("lol \(page)").previews.first)
    #expect(preview.standsForLink && preview.link == URL(string: page) && preview.url == URL(string: "https://i.giphy.com/blSTtZehjAZ8I.webp"))
    #expect(preview.linkText?.string == page)
    // Copied as the link.
    #expect(Markdown.plainText(Markdown.shownText("lol \(page)", layout: .board)) == "lol\n\(page)")
  }

  @Test func anAddressWithoutAPreviewStaysAsItIs() {
    // From where pictures don't load by themselves, or with previews off.
    #expect(self.shown("look https://tracker.example/pixel.png").words == "look https://tracker.example/pixel.png")
    var off = Markdown.Layout.board
    off.imagePreviews = 0
    #expect(self.shown("look https://i.imgur.com/cat.png", layout: off).words == "look https://i.imgur.com/cat.png")
    // The same picture again, which has only the one preview, and past as many as there's room for.
    #expect(self.shown("https://i.imgur.com/cat.png or https://i.imgur.com/cat.png").words == "or https://i.imgur.com/cat.png\n[preview]")
    var one = Markdown.Layout.board
    one.imagePreviews = 1
    #expect(self.shown("https://i.imgur.com/cat.png https://i.imgur.com/dog.png", layout: one).words == "https://i.imgur.com/dog.png\n[preview]")
  }

  // MARK: - Pictures Among the Server's Files

  @Test func picturesAmongTheServersFilesLoadThroughItInItsOwnWindow() {
    let sources = ImagePreview.Sources(server: "hotline.example.com", serverPort: 5500, connection: UUID())
    func picture(_ link: String, in sources: ImagePreview.Sources = sources) -> URL? {
      sources.picture(for: URL(string: link)!, isImage: false)
    }
    // A picture among its files, by where it is there.
    #expect(sources.serverFile(at: URL(string: "hotline://hotline.example.com/files/Pictures/My%20Cat.png")!) == ["Pictures", "My Cat.png"])
    #expect(picture("hotline://hotline.example.com/files/Pictures/cat.png") != nil)
    #expect(picture("hotline://HOTLINE.example.com:5500/files/cat.jpg") != nil)
    // Not a file that isn't a picture, or a folder, or another server's, or one on another port.
    #expect(picture("hotline://hotline.example.com/files/Pictures/notes.txt") == nil)
    #expect(picture("hotline://hotline.example.com/files/Pictures/") == nil)
    #expect(picture("hotline://other.example.com/files/cat.png") == nil)
    #expect(picture("hotline://hotline.example.com:5600/files/cat.png") == nil)
    // Nor where it isn't connected, as in a window of saved chat.
    #expect(picture("hotline://hotline.example.com/files/cat.png", in: ImagePreview.Sources(server: "hotline.example.com", serverPort: 5500)) == nil)
    // Without the login and password its link has, which aren't kept with it.
    #expect(picture("hotline://guest:secret@hotline.example.com/files/cat.png") == URL(string: "hotline://hotline.example.com/files/cat.png"))
  }

  @Test func linksToPicturesAmongTheServersFilesShowThem() {
    var layout = Markdown.Layout.board
    layout.imageSources = ImagePreview.Sources(server: "hotline.example.com", serverPort: 5500, connection: UUID())
    let shown = Markdown.shownText("look hotline://hotline.example.com/files/Pictures/cat.png", layout: layout)
    var previews: [URL] = []
    shown.enumerateAttribute(.attachment, in: NSRange(location: 0, length: shown.length)) { value, _, _ in
      if let attachment = value as? ImageAttachment {
        previews.append(attachment.url)
      }
    }
    #expect(previews == [URL(string: "hotline://hotline.example.com/files/Pictures/cat.png")!])
  }

  @Test func redirectsOnlyToWhereTheyCouldLoadFrom() {
    let sources = ImagePreview.Sources(server: "hotline.example.com")
    #expect(sources.trusts(URL(string: "https://i.imgur.com/removed.png")!))
    #expect(sources.trusts(URL(string: "https://hotline.example.com/moved.png")!))
    #expect(!sources.trusts(URL(string: "https://tracker.example/pixel")!))
    // Nor on to an address, as a router's.
    #expect(!ImagePreview.Sources(server: "hotline.example.com", anySite: true).trusts(URL(string: "https://192.168.1.1/moved.png")!))
  }

  @Test func addressesAndLocalNamesNeverLoadByThemselves() {
    // Not even from any site, as Settings can have it: an IP address reaches whatever's at it, as a
    // router or a printer, on any network, and so does a name only a network of its own knows.
    let anywhere = ImagePreview.Sources(server: "hotline.example.com", anySite: true)
    let links = [
      "https://192.168.1.1/cat.png", "https://10.0.0.5/cat.png", "https://203.0.113.9/cat.png", "https://2130706433/cat.png",
      "https://[::1]/cat.png", "https://[fe80::1]/cat.png", "https://[2001:db8::1]/cat.png",
      "https://localhost/cat.png", "https://localhost./cat.png", "https://app.localhost/cat.png", "https://printer.local/cat.png",
      "https://nas/cat.png", "https://router.lan/cat.png", "https://files.home.arpa/cat.png", "https://wiki.internal/cat.png",
    ]
    for link in links {
      #expect(!anywhere.trusts(URL(string: link)!), "\(link)")
    }
    // Sites by their names.
    #expect(anywhere.trusts(URL(string: "https://example.com/cat.png")!))
    #expect(anywhere.trusts(URL(string: "https://photos.example.co.uk/cat.png")!))
    #expect(anywhere.trusts(URL(string: "https://example.com./cat.png")!))
    // But the server you're on, by whatever address it has, as it has yours already, as a server
    // in a dorm could, and its files, which come through the connection to it.
    let dorm = ImagePreview.Sources(server: "10.0.5.23", serverPort: 5500, connection: UUID())
    #expect(dorm.trusts(URL(string: "https://10.0.5.23/cat.png")!))
    #expect(!dorm.trusts(URL(string: "https://10.0.5.24/cat.png")!))
    #expect(dorm.trusts(URL(string: "hotline://10.0.5.23/files/Pictures/cat.png")!))
    #expect(ImagePreview.Sources(server: "fe80::1").trusts(URL(string: "https://[fe80::1]/cat.png")!))
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
    // Never set, from trusted sites.
    #expect(ImagePreviews.saved(in: defaults) == .trustedSites)
    // Set before, off stays off, and on is from trusted sites.
    defaults.set(false, forKey: PrefsKeys.previewChatImages.rawValue)
    #expect(ImagePreviews.saved(in: defaults) == .never)
    defaults.set(true, forKey: PrefsKeys.previewChatImages.rawValue)
    #expect(ImagePreviews.saved(in: defaults) == .trustedSites)
    // As it's set now, whatever previews were before.
    defaults.set(false, forKey: PrefsKeys.previewChatImages.rawValue)
    defaults.set(ImagePreviews.anySite.rawValue, forKey: PrefsKeys.imagePreviews.rawValue)
    #expect(ImagePreviews.saved(in: defaults) == .anySite)
  }
}
