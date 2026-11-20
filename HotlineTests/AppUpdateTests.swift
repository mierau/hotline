// AppUpdateTests

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import Hotline

struct AppUpdateTests {
  private func release(_ build: Int, notes: String = "Notes") -> [String: Any] {
    [
      "tag_name": "1.0beta\(build)",
      "html_url": "https://github.com/mierau/hotline/releases/tag/1.0beta\(build)",
      "published_at": "2026-11-13T18:30:00Z",
      "body": notes,
    ]
  }

  @Test func aReleasesTagSaysItsVersionAndBuild() throws {
    let notes = try #require(GitHubReleases.notes(from: self.release(31, notes: "Hello again!")))
    #expect(notes.version == "1.0b31")
    #expect(notes.build == 31)
    #expect(notes.notes == "Hello again!")
    #expect(notes.page.absoluteString == "https://github.com/mierau/hotline/releases/tag/1.0beta31")
    #expect(notes.date == Date(timeIntervalSince1970: 1_794_594_600))
  }

  @Test func releasesThatArentBuildsAreLeftOut() {
    var release = self.release(31)
    release["tag_name"] = "v2"
    #expect(GitHubReleases.notes(from: release) == nil)
  }

  @Test func whatsNewIsEveryNewerBuildsNotesNewestFirst() throws {
    let releases = [33, 32, 31, 30].compactMap { GitHubReleases.notes(from: self.release($0, notes: "In b\($0).")) }
    let combined = try #require(GitHubReleases.combined(releases, since: 31))
    // The newest's under the window's own title, and each older one under its version.
    #expect(combined == "In b33.\n\n---\n\n## Hotline 1.0b32\n\nIn b32.")
    #expect(GitHubReleases.combined(releases, since: 33) == nil)
  }

  @Test func aBuildWithoutNotesSaysSo() throws {
    let releases = [GitHubReleases.notes(from: self.release(32, notes: "  \n"))].compactMap { $0 }
    #expect(GitHubReleases.combined(releases, since: 31) == "_No release notes provided._")
  }

  @Test func whatsNewIsOnlyShownWithTheFoundBuildsOwnNotes() throws {
    let releases = [35, 34, 33].compactMap { GitHubReleases.notes(from: self.release($0)) }
    // Up to the build that was found, without any after it.
    #expect(GitHubReleases.notes(releases, through: 34)?.map(\.build) == [34, 33])
    // Notes kept from before it came out have an older build's, which wouldn't do for its.
    #expect(GitHubReleases.notes(Array(releases.dropFirst(2)), through: 34) == nil)
  }

  // MARK: - Notes as GitHub Shows Them

  /// A release as GitHub gives it, with its notes in HTML too.
  private func release(_ build: Int, notes: String = "Notes", html: String) -> [String: Any] {
    var release = self.release(build, notes: notes)
    release["body_html"] = html
    return release
  }

  /// A link to a picture in GitHub's HTML, which only works for five minutes, and the one it was
  /// put up with, which lasts.
  private let signedLink = "https://private-user-images.githubusercontent.com/55453/294246818-aee8de6a-bec5-4cf3-8364-69a98c87d372.gif?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIn0.vTdA2kGESTZCj8ZPtDoWy2yunMJ_WVeHpj17_F0ZDx8"
  private let lastingLink = "https://github.com/user-attachments/assets/aee8de6a-bec5-4cf3-8364-69a98c87d372"

  @Test func aReleasesHTMLIsKeptWithLinksThatLast() throws {
    let html = #"<p><a target="_blank" href="\#(self.signedLink)"><img src="\#(self.signedLink)" alt="CleanShot"></a></p>"#
    let notes = try #require(GitHubReleases.notes(from: self.release(6, html: html)))
    #expect(notes.html == #"<p><a target="_blank" href="\#(self.lastingLink)"><img src="\#(self.lastingLink)" alt="CleanShot"></a></p>"#)
    #expect(notes.notes == "Notes")
  }

  @Test func onlyGitHubsShortLivedLinksAreChanged() {
    // A video's, without an extension.
    let video = "https://private-user-images.githubusercontent.com/55453/294646889-16b1c6f0-ec64-4d64-82d9-6a67ad9acd5d?jwt=abc.def-ghi_jkl"
    #expect(GitHubReleases.lasting(#"<video src="\#(video)" controls>"#) == #"<video src="https://github.com/user-attachments/assets/16b1c6f0-ec64-4d64-82d9-6a67ad9acd5d" controls>"#)
    // Links that last already, and to anything else, stay as they are.
    let others = #"<a href="https://github.com/jhalter">@jhalter</a> <img src="https://camo.githubusercontent.com/abc/def"> <img src="\#(self.lastingLink)">"#
    #expect(GitHubReleases.lasting(others) == others)
  }

  @Test func notesWithoutHTMLAreShownFromTheirMarkdown() throws {
    // GitHub didn't give HTML for notes it has, as it didn't before Hotline asked for it.
    #expect(try #require(GitHubReleases.notes(from: self.release(31, notes: "Hello"))).html == nil)
    // Without notes, there's no HTML to give.
    #expect(try #require(GitHubReleases.notes(from: self.release(31, notes: " \n"))).html == "")
  }

  @Test func whatsNewInHTMLIsEveryNewerBuildsNotesNewestFirst() throws {
    let releases = [33, 32, 31, 30].compactMap { GitHubReleases.notes(from: self.release($0, html: "<p>In b\($0).</p>\n")) }
    let combined = try #require(GitHubReleases.combinedHTML(releases, since: 31))
    // The newest's under the window's own title, and each older one under its version.
    #expect(combined == "<p>In b33.</p>\n<hr>\n<h2>Hotline 1.0b32</h2>\n<p>In b32.</p>")
    #expect(GitHubReleases.combinedHTML(releases, since: 33) == nil)
  }

  @Test func whatsNewInHTMLNeedsEveryBuildsHTML() throws {
    let releases = [GitHubReleases.notes(from: self.release(33, html: "<p>In b33.</p>")), GitHubReleases.notes(from: self.release(32))].compactMap { $0 }
    #expect(GitHubReleases.combinedHTML(releases, since: 31) == nil)
    #expect(GitHubReleases.combinedHTML(releases, since: 32) == "<p>In b33.</p>")
  }

  @Test func aBuildWithoutNotesSaysSoInHTML() throws {
    let releases = [GitHubReleases.notes(from: self.release(32, notes: ""))].compactMap { $0 }
    #expect(GitHubReleases.combinedHTML(releases, since: 31) == "<p><em>No release notes provided.</em></p>")
  }

  @Test @MainActor func picturesAndVideosInNotesAreNamedForTheirPreview() {
    // A picture's description, with its type's extension, and a video's file's name, as it is.
    #expect(ReleaseNotesWeb.mediaName("CleanShot 2024-01-04 at 08 53 35", type: "image/gif", isVideo: false) == "CleanShot 2024-01-04 at 08 53 35.gif")
    #expect(ReleaseNotesWeb.mediaName(" File.Previews.mp4\n", type: "", isVideo: true) == "File.Previews.mp4")
    #expect(ReleaseNotesWeb.mediaName("Shot 1.5", type: "image/png", isVideo: false) == "Shot 1.5.png")
    // GitHub's own description, or none.
    #expect(ReleaseNotesWeb.mediaName("image", type: "image/png", isVideo: false) == "Picture.png")
    #expect(ReleaseNotesWeb.mediaName("", type: "", isVideo: true) == "Video")
  }

  @Test func aVideoFromTheWebPlaysAsItComes() {
    let url = URL(string: "https://github.com/user-attachments/assets/16b1c6f0-ec64-4d64-82d9-6a67ad9acd5d")!
    #expect(PreviewFileInfo(webImage: url, name: "File.Previews.mp4").webPlayableType == .mpeg4Movie)
    // A picture, which comes whole, and one from a Hotline server, which plays as it comes otherwise.
    #expect(PreviewFileInfo(webImage: url, name: "CleanShot.gif").webPlayableType == nil)
    var serverFile = PreviewFileInfo(webImage: url, name: "File.Previews.mp4")
    serverFile.webURL = nil
    #expect(serverFile.webPlayableType == nil)
    // Without a name, it's the end of its address, as a picture linked in chat is.
    #expect(PreviewFileInfo(webImage: url).name == "16b1c6f0-ec64-4d64-82d9-6a67ad9acd5d")
  }

  /// One of Sparkle's errors, as it reports them, with the reason under it.
  private func sparkleError(_ code: Int, reason: Int? = nil) -> NSError {
    var userInfo: [String: Any] = [:]
    if let reason {
      userInfo[NSUnderlyingErrorKey] = NSError(domain: "SUSparkleErrorDomain", code: reason)
    }
    return NSError(domain: "SUSparkleErrorDomain", code: code, userInfo: userInfo)
  }

  @Test func aFeedThatCouldntBeVerifiedIsToldApart() {
    // The feed failed (1000) because its signature didn't (3002), as when it's signed with a new key.
    #expect(AppUpdate.isUnverifiedFeed(self.sparkleError(1000, reason: 3002)))
    // A feed that couldn't be read, no update, or no connection, isn't one.
    #expect(!AppUpdate.isUnverifiedFeed(self.sparkleError(1000)))
    #expect(!AppUpdate.isUnverifiedFeed(self.sparkleError(1001)))
    #expect(!AppUpdate.isUnverifiedFeed(URLError(.notConnectedToInternet)))
  }

  /// An answer from GitHub's API, with its headers.
  private func answer(_ status: Int, _ headers: [String: String] = [:]) throws -> HTTPURLResponse {
    try #require(HTTPURLResponse(url: URL(string: "https://api.github.com/repos/mierau/hotline/releases")!, statusCode: status, httpVersion: "HTTP/2", headerFields: headers))
  }

  @Test func gitHubsLimitIsToldApartFromOtherFailures() throws {
    let now = Date(timeIntervalSince1970: 1_794_600_000)
    #expect(GitHubReleases.failure(for: try self.answer(200)) == nil)
    // Its 60 an hour used up, until the time it says.
    let limited = try self.answer(403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1794603600"])
    #expect(GitHubReleases.failure(for: limited, now: now) == .limited(until: Date(timeIntervalSince1970: 1_794_603_600)))
    // Too many too close together, for as many seconds as it says.
    #expect(GitHubReleases.failure(for: try self.answer(429, ["Retry-After": "60"]), now: now) == .limited(until: now.addingTimeInterval(60)))
    #expect(GitHubReleases.failure(for: try self.answer(403, ["X-RateLimit-Remaining": "0"]), now: now) == .limited(until: nil))
    // Turned away for something else, or broken.
    #expect(GitHubReleases.failure(for: try self.answer(403, ["X-RateLimit-Remaining": "12"]), now: now) == .unexpected)
    #expect(GitHubReleases.failure(for: try self.answer(500), now: now) == .unexpected)
  }

  @Test func noConnectionIsToldApartFromOtherErrors() {
    #expect(GitHubReleases.failure(for: URLError(.notConnectedToInternet)) == .offline)
    #expect(GitHubReleases.failure(for: URLError(.timedOut)) == .offline)
    #expect(GitHubReleases.failure(for: URLError(.badURL)) == .unexpected)
    #expect(GitHubReleases.failure(for: CancellationError()) == .unexpected)
  }

  @Test @MainActor func theLimitSaysWhenToTryAgain() {
    let now = Date(timeIntervalSince1970: 1_794_600_000)
    let later = now.addingTimeInterval(1800)
    let time = later.formatted(date: .omitted, time: .shortened)
    #expect(ReleaseNotesView.explanation(of: .limited(until: later), now: now).hasSuffix("Try again after \(time)."))
    // Without a time, or one that's passed.
    #expect(ReleaseNotesView.explanation(of: .limited(until: nil), now: now).hasSuffix("Try again in a little while."))
    #expect(ReleaseNotesView.explanation(of: .limited(until: now.addingTimeInterval(-5)), now: now).hasSuffix("Try again in a little while."))
    #expect(ReleaseNotesView.explanation(of: .offline, now: now) == "Check your connection to the internet, then try again.")
  }

  @Test func notesAreKeptAsTheyWere() throws {
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "Release Notes \(UUID()).json")
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }
    #expect(ReleaseNotesCache.load(from: fileURL).isEmpty)
    let releases = [32, 31].compactMap { GitHubReleases.notes(from: self.release($0, notes: "In b\($0).", html: "<p>In b\($0).</p>")) }
    ReleaseNotesCache.save(releases, to: fileURL)
    #expect(ReleaseNotesCache.load(from: fileURL) == releases)
    #expect(ReleaseNotesCache.load(from: fileURL).first?.html == "<p>In b32.</p>")
  }

  // MARK: - Downloading a Build, and Its Code

  @Test func aReleasesAppIsItsFirstZip() throws {
    var release = self.release(31)
    release["assets"] = [
      ["name": "updates.xml", "browser_download_url": "https://github.com/mierau/hotline/releases/download/1.0beta31/updates.xml"],
      ["name": "Hotline.b31.zip", "browser_download_url": "https://github.com/mierau/hotline/releases/download/1.0beta31/Hotline.b31.zip"],
    ]
    let notes = try #require(GitHubReleases.notes(from: release))
    #expect(notes.download?.absoluteString == "https://github.com/mierau/hotline/releases/download/1.0beta31/Hotline.b31.zip")
    // Without one, there's nothing to download.
    #expect(try #require(GitHubReleases.notes(from: self.release(30))).download == nil)
  }

  @Test func aReleasesCodeIsAtItsTag() throws {
    let notes = try #require(GitHubReleases.notes(from: self.release(31)))
    #expect(notes.source.absoluteString == "https://github.com/mierau/hotline/tree/1.0beta31")
  }

  @Test func notesKeptBeforeDownloadsStillLoad() throws {
    let fileURL = FileManager.default.temporaryDirectory.appending(path: "Release Notes \(UUID()).json")
    defer {
      try? FileManager.default.removeItem(at: fileURL)
    }
    // As a build before downloads kept them.
    let kept = #"[{"tag":"1.0beta31","version":"1.0b31","build":31,"notes":"Hello","page":"https:\/\/github.com\/mierau\/hotline\/releases\/tag\/1.0beta31"}]"#
    try Data(kept.utf8).write(to: fileURL)
    let loaded = ReleaseNotesCache.load(from: fileURL)
    #expect(loaded.map(\.build) == [31])
    #expect(loaded.first?.download == nil)
    // And before HTML, which is shown from its Markdown.
    #expect(loaded.first?.html == nil)
  }

  @Test func downloadsAreNumberedAsTheFindersCopiesAre() {
    let downloads = URL(filePath: "/Users/someone/Downloads", directoryHint: .isDirectory)
    var there: Set<String> = []
    func destination() -> String {
      ReleaseDownload.destination(for: "Hotline.b31.zip", in: downloads) { there.contains($0.lastPathComponent) }.lastPathComponent
    }
    #expect(destination() == "Hotline.b31.zip")
    there = ["Hotline.b31.zip"]
    #expect(destination() == "Hotline.b31 2.zip")
    there = ["Hotline.b31.zip", "Hotline.b31 2.zip"]
    #expect(destination() == "Hotline.b31 3.zip")
  }
}
