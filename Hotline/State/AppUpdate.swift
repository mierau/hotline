import AppKit
import Observation
import Sparkle

/// What's new in one of Hotline's builds, as its release on GitHub has it.
struct ReleaseNotes: Identifiable, Equatable, Sendable {
  /// Its tag, like 1.0beta31.
  let tag: String
  /// As it's shown, like 1.0b31.
  let version: String
  let build: Int
  let date: Date?
  /// In Markdown.
  let notes: String
  /// Its page on GitHub.
  let page: URL

  var id: String {
    self.tag
  }
}

/// Hotline's releases on GitHub, which have every build's notes.
enum GitHubReleases {
  private static let url = URL(string: "https://api.github.com/repos/mierau/hotline/releases?per_page=100")!

  /// Every build's notes, the newest first.
  static func fetch() async throws -> [ReleaseNotes] {
    let (data, response) = try await URLSession.shared.data(from: self.url)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          let releases = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw URLError(.badServerResponse)
    }
    return releases.compactMap(self.notes(from:)).sorted { $0.build > $1.build }
  }

  /// A release's notes, for a tag like 1.0beta31, which says the version and build it's for.
  static func notes(from release: [String: Any]) -> ReleaseNotes? {
    guard let tag = release["tag_name"] as? String,
          let match = tag.prefixMatch(of: #/([0-9.]+)beta([0-9]+)/#),
          let build = Int(match.2),
          let page = (release["html_url"] as? String).flatMap(URL.init(string:)) else {
      return nil
    }
    let date = (release["published_at"] as? String).flatMap { try? Date($0, strategy: .iso8601) }
    return ReleaseNotes(tag: tag, version: "\(match.1)b\(build)", build: build, date: date, notes: (release["body"] as? String) ?? "", page: page)
  }

  /// What's new since a build: the notes of each build after it, the newest first, under its version
  /// but for the newest, whose version the window has already.
  static func combined(_ releases: [ReleaseNotes], since build: Int) -> String? {
    let newer = releases.filter { $0.build > build }
    guard let newest = newer.first else {
      return nil
    }
    let sections = [Self.body(of: newest)] + newer.dropFirst().map { "## Hotline \($0.version)\n\n\(Self.body(of: $0))" }
    return sections.joined(separator: "\n\n---\n\n")
  }

  private static func body(of release: ReleaseNotes) -> String {
    let notes = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    return notes.isEmpty ? "_No release notes provided._" : notes
  }
}

struct AppUpdateMessage: Equatable {
  enum Kind {
    case info
    case success
    case error
  }

  let title: String
  let detail: String
  let kind: Kind
  /// Where to download Hotline instead, for an update it can't install itself.
  var page: URL? = nil
}

/// Updates to Hotline, found and installed by Sparkle and shown in Hotline's own window: what's new
/// since this build, then the update coming in, then installing it, which quits and relaunches
/// Hotline. Sparkle reads the feed on Hotline's latest GitHub release, which has to be signed with
/// Hotline's key, downloads its zip, checks that's signed too, and installs it from outside the
/// sandbox. When the feed can't be verified, as when it's signed with a new key, GitHub's releases
/// page is offered instead, to download from there.
@MainActor
@Observable
final class AppUpdate: NSObject {
  static let shared = AppUpdate()

  /// Where an update's at, as the window shows it.
  enum Stage: Equatable {
    /// A newer build, to install or not.
    case found
    /// Coming in, with how much has, of how much, once that's known.
    case downloading(received: UInt64, expected: UInt64)
    /// Here, being unpacked and checked, then installed, which quits and relaunches Hotline.
    case installing
    /// Ready, once Hotline quits, which something stopped, like a transfer it asked about.
    case waitingToQuit
    /// Something that went wrong, to read and close.
    case failed(AppUpdateMessage)
  }

  /// Whether the update window's open.
  var showWindow = false
  private(set) var stage = Stage.found
  /// The newer build, as it's shown, like 1.0b31.
  private(set) var version = ""
  /// What's new since this build, the newest first, in Markdown.
  private(set) var notes = ""
  /// Whether a check can start now, which Check for Updates is for.
  private(set) var canCheck = false

  @ObservationIgnored private var updater: SPUUpdater?
  @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?
  /// What Sparkle's waiting to hear about the update that was found.
  @ObservationIgnored private var choose: ((SPUUserUpdateChoice) -> Void)?
  @ObservationIgnored private var cancelDownload: (() -> Void)?
  @ObservationIgnored private var retryTermination: (() -> Void)?
  /// What Sparkle's waiting for, once a failure's been read.
  @ObservationIgnored private var acknowledge: (() -> Void)?

  /// A build that was put off, which a check of its own accord doesn't bring up again for a while.
  private static let putOffVersionKey = "update.last.prompt.version"
  private static let remindDateKey = "update.remind.date"
  private static let putOffInterval: TimeInterval = 60 * 60 * 24 * 14
  /// When a check of Sparkle's own that couldn't verify the feed can bring up GitHub's releases again.
  private static let unverifiedRemindDateKey = "update.unverified.remind.date"

  /// Hotline's latest release on GitHub, to download there when Hotline can't install it itself.
  static let releasesPage = URL(string: "https://github.com/mierau/hotline/releases/latest")!

  private override init() {
    super.init()
  }

  /// Starts checking, which Sparkle does once a day, the first time when it's due.
  func start() {
    guard self.updater == nil else {
      return
    }
    let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
    do {
      try updater.start()
    }
    catch {
      print("AppUpdate: Sparkle couldn't start: \(error)")
      return
    }
    self.updater = updater
    self.canCheckObservation = updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
      let canCheck = updater.canCheckForUpdates
      Task { @MainActor in
        self?.canCheck = canCheck
      }
    }
    #if DEBUG
    // Pointed at a test feed, checked straight away, rather than when it's due.
    if Self.testFeed != nil {
      updater.checkForUpdatesInBackground()
    }
    #endif
  }

  #if DEBUG
  /// A feed to try an update from, given at launch, as in `-UpdateTestFeedURL
  /// http://127.0.0.1:8765/appcast.xml`, as Sparkle only takes http and https, with
  /// `-UpdateTestInstall YES` to install what it finds as Install Update would: quitting, installing
  /// and relaunching.
  nonisolated static var testFeed: String? {
    UserDefaults.standard.string(forKey: "UpdateTestFeedURL")
  }
  #endif

  /// Checks now, as Check for Updates does, which says when there's nothing new.
  func checkForUpdates() {
    self.updater?.checkForUpdates()
  }

  // MARK: Choices

  func install() {
    self.reply(.install)
  }

  /// Puts the update off until a check finds it again, which one of Sparkle's own isn't for a while.
  func notNow() {
    UserDefaults.standard.set(self.version, forKey: Self.putOffVersionKey)
    UserDefaults.standard.set(Date().addingTimeInterval(Self.putOffInterval), forKey: Self.remindDateKey)
    self.reply(.dismiss)
  }

  /// Stops the download, and puts the update off.
  func cancel() {
    self.cancelDownload?()
    self.cancelDownload = nil
    self.close()
  }

  /// Asks Hotline to quit again, after something stopped it, to install.
  func retryQuitting() {
    self.retryTermination?()
  }

  /// Closes a failure that's been read.
  func acknowledgeFailure() {
    self.acknowledge?()
    self.acknowledge = nil
    self.close()
  }

  /// Opens a page to download Hotline from, for an update it can't install itself, and closes what
  /// was said.
  func download(from page: URL) {
    NSWorkspace.shared.open(page)
    self.acknowledgeFailure()
  }

  /// As the window closes, which, for an update that was found, is Not Now, and for one coming in,
  /// stops it, so Hotline doesn't quit to install it out of nowhere.
  func windowClosed() {
    guard self.showWindow else {
      return
    }
    if self.choose != nil {
      self.notNow()
    }
    else if case .downloading = self.stage {
      self.cancel()
    }
    else if self.acknowledge != nil {
      self.acknowledgeFailure()
    }
    else {
      self.showWindow = false
    }
  }

  private func reply(_ choice: SPUUserUpdateChoice) {
    let choose = self.choose
    self.choose = nil
    if choice != .install {
      self.close()
    }
    choose?(choice)
  }

  private func close() {
    self.showWindow = false
    self.stage = .found
  }

  /// Whether a build was put off, and not long enough ago to bring it up again.
  private func isPutOff(_ version: String) -> Bool {
    guard UserDefaults.standard.string(forKey: Self.putOffVersionKey) == version,
          let remindDate = UserDefaults.standard.object(forKey: Self.remindDateKey) as? Date else {
      return false
    }
    return remindDate > Date()
  }

  /// Whether a check failed because the feed isn't signed with the key this build has, as when it's
  /// signed with a new key, or it was changed. Sparkle won't install anything it lists then.
  nonisolated static func isUnverifiedFeed(_ error: any Error) -> Bool {
    let error = error as NSError
    guard error.domain == SUSparkleErrorDomain,
          error.code == Int(SUError.appcastParseError.rawValue),
          let reason = error.userInfo[NSUnderlyingErrorKey] as? NSError else {
      return false
    }
    return reason.domain == SUSparkleErrorDomain && reason.code == Int(SUError.validationError.rawValue)
  }

  /// What's said when the feed can't be verified, with Hotline's releases on GitHub to download from.
  private static var unverifiedFeedMessage: AppUpdateMessage {
    AppUpdateMessage(title: "Couldn't Update Hotline", detail: "Hotline couldn't verify its updates, so it can't install them itself. Download the latest version from GitHub instead.", kind: .error, page: Self.releasesPage)
  }

  /// GitHub's releases, for when a check of Sparkle's own couldn't verify the feed, which Sparkle keeps
  /// to itself. Brought up once, then not again for a while, like an update that was put off.
  private func offerReleasesPage() {
    let defaults = UserDefaults.standard
    if let remindDate = defaults.object(forKey: Self.unverifiedRemindDateKey) as? Date, remindDate > Date() {
      return
    }
    guard !self.showWindow else {
      return
    }
    defaults.set(Date().addingTimeInterval(Self.putOffInterval), forKey: Self.unverifiedRemindDateKey)
    self.choose = nil
    self.acknowledge = nil
    self.stage = .failed(Self.unverifiedFeedMessage)
    self.showWindow = true
  }

  /// This build's number.
  private static var currentBuild: Int {
    Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0
  }

  /// What's new since this build, from GitHub, in place of the feed's notes, which are only the
  /// newest build's.
  private func loadNotes(for version: String) async {
    guard let releases = try? await GitHubReleases.fetch(),
          let combined = GitHubReleases.combined(releases, since: Self.currentBuild),
          self.version == version else {
      return
    }
    self.notes = combined
  }
}

// MARK: - Showing Sparkle's Progress

extension AppUpdate: SPUUserDriver {
  /// Hotline's always checked by itself, which Info.plist says too, and sends nothing about the Mac.
  func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
    reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
  }

  /// A check's quick, and what it finds is shown.
  func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {}

  func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
    let version = appcastItem.displayVersionString
    // Not from a check of Sparkle's own, once it's been put off, for a while.
    if !state.userInitiated, state.stage == .notDownloaded, self.isPutOff(version) {
      reply(.dismiss)
      return
    }
    // One there's only news of, as for a build that shouldn't be installed, has its page.
    if appcastItem.isInformationOnlyUpdate {
      reply(.dismiss)
      if let page = appcastItem.infoURL {
        NSWorkspace.shared.open(page)
      }
      return
    }
    self.version = version
    self.notes = appcastItem.itemDescription ?? ""
    self.choose = reply
    // Even one already downloaded, or partway installed, waits for Install Update, which finishes it.
    self.stage = .found
    self.showWindow = true
    Task {
      await self.loadNotes(for: version)
    }
    #if DEBUG
    if Self.testFeed != nil, UserDefaults.standard.bool(forKey: "UpdateTestInstall") {
      self.install()
    }
    #endif
  }

  /// Notes come with the feed, or from GitHub, rather than from a link.
  func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

  func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

  func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
    acknowledgement()
    let alert = NSAlert()
    alert.messageText = "No Update Available"
    alert.informativeText = "You are already using the latest version of Hotline!"
    alert.runModal()
  }

  func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
    self.choose = nil
    self.acknowledge = acknowledgement
    if Self.isUnverifiedFeed(error) {
      self.stage = .failed(Self.unverifiedFeedMessage)
    }
    else {
      self.stage = .failed(AppUpdateMessage(title: "Couldn't Update Hotline", detail: error.localizedDescription, kind: .error))
    }
    self.showWindow = true
  }

  func showDownloadInitiated(cancellation: @escaping () -> Void) {
    self.cancelDownload = cancellation
    self.stage = .downloading(received: 0, expected: 0)
  }

  func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
    self.stage = .downloading(received: 0, expected: expectedContentLength)
  }

  func showDownloadDidReceiveData(ofLength length: UInt64) {
    if case .downloading(let received, let expected) = self.stage {
      self.stage = .downloading(received: received + length, expected: expected)
    }
  }

  func showDownloadDidStartExtractingUpdate() {
    self.cancelDownload = nil
    self.stage = .installing
  }

  func showExtractionReceivedProgress(_ progress: Double) {}

  /// Installed straight away, as Install Update asked for.
  func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
    self.stage = .installing
    reply(.install)
  }

  func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
    if applicationTerminated {
      self.retryTermination = nil
      self.stage = .installing
    }
    else {
      self.retryTermination = retryTerminatingApplication
      self.stage = .waitingToQuit
    }
  }

  func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
    acknowledgement()
  }

  func dismissUpdateInstallation() {
    self.choose = nil
    self.cancelDownload = nil
    self.retryTermination = nil
    self.acknowledge = nil
    self.close()
  }

  func showUpdateInFocus() {
    self.showWindow = true
    NSApplication.shared.activate()
  }
}

extension AppUpdate: SPUUpdaterDelegate {
  /// The feed Info.plist names, unless a debug build's been pointed at another, to try an update.
  nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
    #if DEBUG
    return Self.testFeed
    #else
    return nil
    #endif
  }

  /// A check of Sparkle's own keeps its failures to itself, but not a feed that couldn't be verified,
  /// as when it's signed with a new key: Hotline can't install what it lists, but GitHub has it. Check
  /// for Updates says so itself, as its failures are shown.
  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
    guard updateCheck == .updatesInBackground, let error, Self.isUnverifiedFeed(error) else {
      return
    }
    self.offerReleasesPage()
  }
}
