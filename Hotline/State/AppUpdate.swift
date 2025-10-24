import Foundation
import Observation
import AppKit

struct UpdateReleaseInfo: Equatable {
  let tagName: String
  let displayVersion: String
  let versionNumber: Double
  let buildNumber: Int
  let notes: String
  let downloadURL: URL
  let assetName: String
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
}

@Observable
final class AppUpdate {
  static let shared = AppUpdate()
  
  private init() {}
  
  private enum CheckTrigger {
    case automatic
    case manual
  }
  
  // MARK: - Public State
  
  var isChecking = false
  var isDownloading = false
  var showWindow = false
  var release: UpdateReleaseInfo?
  var releases: [UpdateReleaseInfo] = []
  var message: AppUpdateMessage?
  var userInitiated = false
  var releaseNotesCombined: String?
  
  // MARK: - Configuration
  
  private let releasesURL = URL(string: "https://api.github.com/repos/mierau/hotline/releases?per_page=100")!
  private let remindInterval: TimeInterval = 60 * 60 * 24 * 14
  
  private let defaults = UserDefaults.standard
  private let remindDateKey = "update.remind.date"
  private let lastPromptedVersionKey = "update.last.prompt.version"
  
  // MARK: - Public API
  
  func checkForUpdatesOnLaunch() async {
    await checkForUpdates(trigger: .automatic)
  }
  
  func checkForUpdatesManually() async {
    await checkForUpdates(trigger: .manual)
  }
  
  @MainActor
  func startDownload() {
    guard let release, isDownloading == false else { return }
    
    isDownloading = true
    message = nil
    
    Task(priority: .userInitiated) {
      await self.downloadRelease(release)
    }
  }
  
  @MainActor
  func remindLater() {
    guard let release else {
      resetAndCloseWindow()
      return
    }
    
    recordPrompt(for: release, remindLater: true)
    resetAndCloseWindow()
  }
  
  @MainActor
  func acknowledgeMessage() {
    resetAndCloseWindow()
  }
  
  @MainActor
  func handleWindowDismissed() {
    guard showWindow else { return }
    
    resetAndCloseWindow()
  }
  
  // MARK: - Internal Logic
  
  private func checkForUpdates(trigger: CheckTrigger) async {
    await MainActor.run {
      self.isChecking = true
      self.userInitiated = (trigger == .manual)
      self.message = nil
      self.releases = []
      self.release = nil
      self.releaseNotesCombined = nil
      self.isDownloading = false
      if trigger == .manual {
        self.showWindow = false
      }
    }
    
    do {
      let newerReleases = try await fetchNewerReleases()
      let latestRelease = newerReleases.first
      let shouldShow: Bool
      switch trigger {
      case .manual:
        shouldShow = latestRelease != nil
      case .automatic:
        if let latestRelease {
          shouldShow = shouldPrompt(for: latestRelease)
        } else {
          shouldShow = false
        }
      }
      
      await MainActor.run {
        self.isChecking = false
        if shouldShow, let latestRelease {
          self.release = latestRelease
          self.releases = newerReleases
          self.releaseNotesCombined = combinedReleaseNotes(from: newerReleases)
          self.isDownloading = false
          self.message = nil
          self.showWindow = true
        } else {
          self.release = nil
          self.releases = []
          self.releaseNotesCombined = nil
          self.isDownloading = false
          if trigger == .manual {
            self.message = AppUpdateMessage(
              title: "Hotline is up to date",
              detail: "You're running the latest and greatest.",
              kind: .success
            )
            self.showWindow = true
          } else {
            self.message = nil
            self.showWindow = false
          }
        }
      }
    } catch {
      await MainActor.run {
        self.isChecking = false
        self.release = nil
        self.releases = []
        self.releaseNotesCombined = nil
        self.isDownloading = false
        if trigger == .manual {
          self.message = AppUpdateMessage(
            title: "Unable to Check for Updates",
            detail: error.localizedDescription,
            kind: .error
          )
          self.showWindow = true
        }
      }
    }
  }
  
  private func fetchNewerReleases() async throws -> [UpdateReleaseInfo] {
    let (data, _) = try await URLSession.shared.data(from: releasesURL)
    guard let jsonArray = try JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
      throw NSError(domain: "AppUpdate", code: -10, userInfo: [NSLocalizedDescriptionKey: "Malformed GitHub releases response."])
    }
    
    let parsed = jsonArray.compactMap(parseRelease)
    let newer = parsed.filter(isReleaseNewer)
    return newer
  }
  
  private func parseRelease(_ json: [String: Any]) -> UpdateReleaseInfo? {
    guard let tagName = json["tag_name"] as? String else {
      return nil
    }
    
    let notes = (json["body"] as? String) ?? ""
    guard
      let assets = json["assets"] as? [[String: Any]],
      let asset = assets.first,
      let downloadString = asset["browser_download_url"] as? String,
      let downloadURL = URL(string: downloadString)
    else {
      return nil
    }
    
    let assetName = (asset["name"] as? String) ?? downloadURL.lastPathComponent
    
    let versionPattern = #"^([0-9\.]+)beta([0-9]+)"#
    guard let regex = try? NSRegularExpression(pattern: versionPattern, options: []) else {
      return nil
    }
    
    let range = NSRange(location: 0, length: tagName.utf16.count)
    guard let match = regex.firstMatch(in: tagName, options: [], range: range),
          match.numberOfRanges >= 3,
          let versionRange = Range(match.range(at: 1), in: tagName),
          let buildRange = Range(match.range(at: 2), in: tagName),
          let versionNumber = Double(String(tagName[versionRange])),
          let buildNumber = Int(String(tagName[buildRange]))
    else {
      return nil
    }
    
    let versionComponent = String(tagName[versionRange])
    let buildComponent = String(tagName[buildRange])
    let displayVersion = "\(versionComponent)b\(buildComponent)"
    
    return UpdateReleaseInfo(
      tagName: tagName,
      displayVersion: displayVersion,
      versionNumber: versionNumber,
      buildNumber: buildNumber,
      notes: notes,
      downloadURL: downloadURL,
      assetName: assetName
    )
  }
  
  private func combinedReleaseNotes(from releases: [UpdateReleaseInfo]) -> String? {
    guard let firstRelease = releases.first else { return nil }
    
    let firstNotes = firstRelease.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    let firstBody = firstNotes.isEmpty ? "_No release notes provided._" : firstNotes
    
    guard releases.count > 1 else {
      return firstBody
    }
    
    let olderSections = releases.dropFirst().map { release -> String in
      let trimmed = release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
      let body = trimmed.isEmpty ? "_No release notes provided._" : trimmed
      return "## Hotline \(release.displayVersion)\n\n\(body)"
    }
    
    let olderCombined = olderSections.joined(separator: "\n\n---\n\n")
    return "\(firstBody)\n\n---\n\n\(olderCombined)"
  }
  
  private func downloadRelease(_ release: UpdateReleaseInfo) async {
    do {
      let (temporaryURL, _) = try await URLSession.shared.download(from: release.downloadURL)
      let downloadsDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
      let destinationURL = downloadsDirectory.appendingPathComponent(release.assetName)
      
      if FileManager.default.fileExists(atPath: destinationURL.path) {
        try? FileManager.default.removeItem(at: destinationURL)
      }
      
      try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
      
      await MainActor.run {
        self.isDownloading = false
        NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
        self.resetAndCloseWindow()
      }
    } catch {
      await MainActor.run {
        self.isDownloading = false
        self.message = AppUpdateMessage(
          title: "Download Failed",
          detail: error.localizedDescription,
          kind: .error
        )
        self.showWindow = true
      }
    }
  }
  
  private func currentApplicationVersion() -> (version: Double, build: Int) {
    let info = Bundle.main.infoDictionary ?? [:]
    let versionString = info["CFBundleShortVersionString"] as? String ?? "0"
    let buildString = info["CFBundleVersion"] as? String ?? "0"
    let version = Double(versionString) ?? 0
    let build = Int(buildString) ?? 0
    return (version, build)
  }
  
  private func isReleaseNewer(_ release: UpdateReleaseInfo) -> Bool {
    let current = currentApplicationVersion()
    if release.versionNumber > current.version {
      return true
    }
    if release.versionNumber == current.version {
      return release.buildNumber > current.build
    }
    return false
  }
  
  private func shouldPrompt(for release: UpdateReleaseInfo) -> Bool {
    if defaults.string(forKey: lastPromptedVersionKey) != release.tagName {
      return true
    }
    guard let remindDate = defaults.object(forKey: remindDateKey) as? Date else {
      return true
    }
    return remindDate <= Date()
  }
  
  @MainActor
  private func recordPrompt(for release: UpdateReleaseInfo, remindLater: Bool) {
    defaults.set(release.tagName, forKey: lastPromptedVersionKey)
    if remindLater {
      let nextReminder = Date().addingTimeInterval(remindInterval)
      defaults.set(nextReminder, forKey: remindDateKey)
    } else {
      defaults.removeObject(forKey: remindDateKey)
    }
  }
  
  @MainActor
  private func resetAndCloseWindow() {
    isChecking = false
    isDownloading = false
    release = nil
    releases = []
    releaseNotesCombined = nil
    message = nil
    userInitiated = false
    showWindow = false
  }
}
