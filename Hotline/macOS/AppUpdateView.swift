import SwiftUI
import AppKit
import Observation

/// A newer build of Hotline, and what's new since this one, to install or not, then its coming in and
/// installing, which quits and relaunches Hotline, all in one window.
struct AppUpdateView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable private var update = AppUpdate.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if case .failed(let message) = self.update.stage {
        self.failure(message)
      }
      else {
        self.header
        self.releaseNotes
        self.actions
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .padding(.top, 8)
    .frame(width: self.isFailure ? 380 : 520)
    .frame(idealHeight: 360)
    .onChange(of: self.update.showWindow) { _, show in
      if !show {
        self.dismiss()
      }
    }
    .onDisappear {
      self.update.windowClosed()
    }
  }

  private var isFailure: Bool {
    if case .failed = self.update.stage {
      return true
    }
    return false
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .shadow(color: Color.black.mix(with: .red, by: 0.4).opacity(0.15), radius: 3, y: 1.5)

      VStack(alignment: .leading, spacing: 2) {
        Text("Hotline \(self.update.version)")
          .font(.title2)
          .fontWeight(.semibold)
        Text("A new version of Hotline is available. 🎉")
          .foregroundStyle(.secondary)
      }
    }
  }

  private var releaseNotes: some View {
    let notes = self.update.notes.trimmingCharacters(in: .whitespacesAndNewlines)
    return ScrollView(.vertical) {
      MarkdownText(text: notes.isEmpty ? "_No release notes provided._" : notes, layout: Markdown.Layout(font: .systemFont(ofSize: 12), lineSpacing: 3), inset: NSSize(width: 12, height: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(minHeight: 220, maxHeight: 260)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }

  /// What can be done, as far as the update's got: installed or not, its download stopped, or
  /// Hotline quit to install it, once something stopped it quitting.
  @ViewBuilder
  private var actions: some View {
    HStack(spacing: 12) {
      switch self.update.stage {
      case .found, .failed:
        Button("Not Now") {
          self.update.notNow()
        }
        .keyboardShortcut(.escape, modifiers: [])
        Spacer()
        Button("Install Update") {
          self.update.install()
        }
        .keyboardShortcut(.defaultAction)
      case .downloading(let received, let expected):
        VStack(alignment: .leading, spacing: 4) {
          if expected > 0 {
            ProgressView(value: Double(min(received, expected)), total: Double(expected))
          }
          else {
            ProgressView()
          }
          Text(Self.progress(received: received, expected: expected))
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .progressViewStyle(.linear)
        Button("Cancel") {
          self.update.cancel()
        }
        .keyboardShortcut(.escape, modifiers: [])
      case .installing:
        VStack(alignment: .leading, spacing: 4) {
          ProgressView()
            .progressViewStyle(.linear)
          Text("Installing… Hotline will open again in a moment.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      case .waitingToQuit:
        Text("The update installs once Hotline quits.")
          .foregroundStyle(.secondary)
        Spacer()
        Button("Quit and Install") {
          self.update.retryQuitting()
        }
        .keyboardShortcut(.defaultAction)
      }
    }
    .buttonBorderShape(.capsule)
    .controlSize(.large)
  }

  private static func progress(received: UInt64, expected: UInt64) -> String {
    let format = ByteCountFormatStyle(style: .file)
    let done = Int64(received).formatted(format)
    guard expected > 0 else {
      return "Downloading… \(done)"
    }
    return "Downloading… \(done) of \(Int64(expected).formatted(format))"
  }

  private func failure(_ message: AppUpdateMessage) -> some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .center, spacing: 12) {
        Image(systemName: "exclamationmark.triangle.fill")
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.multicolor)
          .frame(width: 48, height: 48)
        VStack(alignment: .leading, spacing: 2) {
          Text(message.title)
            .font(.title2)
            .fontWeight(.semibold)
          // As many lines as it takes, as the window's only as tall as what's in it.
          Text(message.detail)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer()
      }
      HStack(spacing: 12) {
        // One Hotline can't install itself is on GitHub, to download there.
        if let page = message.page {
          Button("Not Now") {
            self.update.acknowledgeFailure()
          }
          .keyboardShortcut(.escape, modifiers: [])
          Spacer()
          Button("Download from GitHub") {
            self.update.download(from: page)
          }
          .keyboardShortcut(.defaultAction)
        }
        else {
          Spacer()
          Button("OK") {
            self.update.acknowledgeFailure()
          }
          .keyboardShortcut(.defaultAction)
        }
      }
      .buttonBorderShape(.capsule)
      .controlSize(.large)
    }
  }
}

// MARK: - Release Notes

/// Every build's notes, from Hotline's releases on GitHub: the builds down the side, the newest first,
/// and the notes of the one chosen, which starts as the build that's running.
struct ReleaseNotesView: View {
  @State private var releases: [ReleaseNotes] = []
  @State private var selection: ReleaseNotes.ID?
  @State private var failed = false

  private let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0

  var body: some View {
    NavigationSplitView {
      // How long ago each came out, kept up to the minute.
      TimelineView(.everyMinute) { context in
        List(self.releases, selection: self.$selection) { release in
          VStack(alignment: .leading, spacing: 2) {
            Text("Hotline \(release.version)")
            Text(self.subtitle(of: release, now: context.date))
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .padding(.vertical, 2)
        }
      }
      .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
    } detail: {
      if let release = self.releases.first(where: { $0.id == self.selection }) {
        ScrollView(.vertical) {
          ReleaseNotesDetail(release: release, isInstalled: release.build == self.currentBuild)
        }
        // From the top for each build.
        .id(release.id)
      }
      else if self.failed {
        ContentUnavailableView {
          Label("Couldn't Load Release Notes", systemImage: "exclamationmark.triangle")
        } description: {
          Text("Check your connection to the internet, then try again.")
        } actions: {
          Button("Try Again") {
            Task {
              await self.load()
            }
          }
        }
      }
      else {
        ProgressView()
      }
    }
    .navigationTitle("Release Notes")
    .task {
      await self.load()
    }
  }

  /// How long ago it came out, and whether it's the build that's running.
  private func subtitle(of release: ReleaseNotes, now: Date) -> String {
    let date = release.date.map { Self.howLongAgo($0, now: now) }
    let installed = release.build == self.currentBuild ? "Installed" : nil
    return [date, installed].compactMap { $0 }.joined(separator: " · ")
  }

  /// How long ago something was, to the nearest of the biggest unit it's been at least one of, as
  /// GitHub says it: just now, for under a minute, then minutes, hours, days, weeks, months and
  /// years, so 20 days and 23 hours is 3 weeks, and 35 months is 3 years. One day, week, month or
  /// year is yesterday, last week, last month or last year.
  static func howLongAgo(_ date: Date, now: Date) -> String {
    let seconds = now.timeIntervalSince(date)
    guard seconds >= 60 else {
      return String(localized: "Just now")
    }
    let minutes = Int((seconds / 60).rounded())
    let hours = Int((seconds / 3600).rounded())
    let days = seconds / 86400
    let months = Int((days / 30.44).rounded())
    var ago = DateComponents()
    if minutes < 60 {
      ago.minute = -minutes
    }
    else if hours < 24 {
      ago.hour = -hours
    }
    else if days.rounded() < 7 {
      ago.day = -Int(days.rounded())
    }
    else if days < 30 {
      ago.weekOfMonth = -max(1, Int((days / 7).rounded()))
    }
    else if months < 12 {
      ago.month = -max(1, months)
    }
    else {
      ago.year = -max(1, Int((days / 365.25).rounded()))
    }
    return Self.relativeFormatter.localizedString(from: ago)
  }

  private static let relativeFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.dateTimeStyle = .named
    // Capitalized, as it starts the line: Yesterday, Last week.
    formatter.formattingContext = .beginningOfSentence
    return formatter
  }()

  private func load() async {
    self.failed = false
    do {
      let releases = try await GitHubReleases.fetch()
      self.releases = releases
      if self.selection == nil {
        self.selection = (releases.first { $0.build == self.currentBuild } ?? releases.first)?.id
      }
    }
    catch {
      self.failed = true
    }
  }
}

/// One build's notes: its version, when it came out, whether it's the one running, and a link to its
/// release on GitHub, then the notes themselves.
struct ReleaseNotesDetail: View {
  let release: ReleaseNotes
  let isInstalled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Hotline \(self.release.version)")
          .font(.title2)
          .fontWeight(.semibold)
        HStack(spacing: 0) {
          if let details = self.details {
            Text("\(details) · ")
              .foregroundStyle(.secondary)
          }
          Link("View on GitHub", destination: self.release.page)
        }
        .font(.callout)
      }
      let notes = self.release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
      MarkdownText(text: notes.isEmpty ? "_No release notes provided._" : notes, layout: Markdown.Layout(font: .systemFont(ofSize: 13), lineSpacing: 3))
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  /// When it came out, and whether it's the build that's running.
  private var details: String? {
    let parts = [self.release.date?.formatted(date: .long, time: .omitted), self.isInstalled ? "Installed" : nil].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}
