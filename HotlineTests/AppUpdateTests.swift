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
    let releases = [32, 31].compactMap { GitHubReleases.notes(from: self.release($0, notes: "In b\($0).")) }
    ReleaseNotesCache.save(releases, to: fileURL)
    #expect(ReleaseNotesCache.load(from: fileURL) == releases)
  }
}
