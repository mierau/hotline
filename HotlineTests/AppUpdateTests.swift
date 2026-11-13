// AppUpdateTests

import Testing
import Foundation
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
}
