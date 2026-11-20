import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers
import WebKit

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

  /// What's new, in a box: as GitHub shows it, once that's loaded, which it usually is before the
  /// window opens, or until then, as the feed has it.
  private var releaseNotes: some View {
    Group {
      if let page = self.update.notesPage {
        ReleaseNotesWebView(page: page)
          .clipShape(.rect(cornerRadius: 12))
      }
      else {
        let notes = self.update.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        ScrollView(.vertical) {
          MarkdownText(text: notes.isEmpty ? "_No release notes provided._" : notes, layout: Markdown.Layout(font: .systemFont(ofSize: 12), lineSpacing: 3), inset: NSSize(width: 12, height: 12))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
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
/// and the notes of the one chosen, which starts as the build that's running. The notes GitHub last
/// gave show straight away, and stay, if it doesn't give them this time. Without any, it says why:
/// no connection, or GitHub's limit for the network, and until when.
struct ReleaseNotesView: View {
  @State private var releases: [ReleaseNotes] = []
  @State private var selection: ReleaseNotes.ID?
  /// The build chosen for you, before you choose one, which the window goes on choosing as newer
  /// notes come in: the build that's running, once there are notes for it.
  @State private var picked: ReleaseNotes.ID?
  /// Why GitHub didn't give the notes, the last time it was asked.
  @State private var failure: GitHubReleases.Failure?
  /// The build whose app is being downloaded, while it is.
  @State private var downloading: ReleaseNotes.ID?
  /// Why the last download didn't work, to say so.
  @State private var downloadFailure: DownloadFailure?
  @Environment(\.openURL) private var openURL

  private let currentBuild = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "") ?? 0

  /// A build's app that couldn't be downloaded, and why.
  struct DownloadFailure {
    let version: String
    let reason: String
  }

  /// The build chosen.
  private var chosen: ReleaseNotes? {
    self.releases.first { $0.id == self.selection }
  }

  var body: some View {
    NavigationSplitView {
      // How long ago each came out, kept up to the minute.
      TimelineView(.everyMinute) { context in
        List(self.releases, selection: self.$selection) { release in
          ReleaseNotesRow(release: release, currentBuild: self.currentBuild, now: context.date)
        }
      }
      .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
    } detail: {
      // As GitHub shows them, unless they were kept from before Hotline asked for that, or pictures
      // shouldn't load, as the settings can say.
      if let release = self.chosen, release.html != nil, Prefs.shared.imagePreviews != .never {
        ReleaseNotesWebDetail(release: release, isInstalled: release.build == self.currentBuild)
      }
      else if let release = self.chosen {
        ScrollView(.vertical) {
          ReleaseNotesDetail(release: release, isInstalled: release.build == self.currentBuild)
        }
        // From the top for each build.
        .id(release.id)
      }
      else if let failure = self.failure {
        ContentUnavailableView {
          Label("Couldn't Load Release Notes", systemImage: "exclamationmark.triangle")
        } description: {
          Text(Self.explanation(of: failure))
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
    .toolbar {
      self.toolbar
    }
    .alert(
      Text("Couldn't Download Hotline \(self.downloadFailure?.version ?? "")"),
      isPresented: Binding(get: { self.downloadFailure != nil }, set: { if !$0 { self.downloadFailure = nil } }),
      presenting: self.downloadFailure
    ) { _ in
      Button("OK") {}
    } message: { failure in
      Text(failure.reason)
    }
    .task {
      await self.load()
    }
  }

  /// The chosen build's app, to download, and its code and its release, on GitHub.
  @ToolbarContentBuilder
  private var toolbar: some ToolbarContent {
    ToolbarItem {
      Button {
        if let release = self.chosen {
          self.download(release)
        }
      } label: {
        // A spinner while it's coming.
        if self.downloading != nil, self.downloading == self.selection {
          ProgressView()
            .controlSize(.small)
        }
        else {
          Label("Download", systemImage: "arrow.down.circle")
        }
      }
      .disabled(self.chosen?.download == nil || self.downloading != nil)
      .help(self.chosen.map { Text("Download Hotline \($0.version) to your Downloads folder") } ?? Text("Download"))
    }

    ToolbarSpacer(.fixed)

    ToolbarItemGroup {
      Button {
        if let release = self.chosen {
          self.openURL(release.source)
        }
      } label: {
        Label("View Code", systemImage: "chevron.left.forwardslash.chevron.right")
      }
      .disabled(self.chosen == nil)
      .help(self.chosen.map { Text("View the code for Hotline \($0.version) on GitHub") } ?? Text("View Code"))

      Button {
        if let release = self.chosen {
          self.openURL(release.page)
        }
      } label: {
        Label("Open on GitHub", systemImage: "arrow.up.forward")
      }
      .disabled(self.chosen == nil)
      .help(self.chosen.map { Text("Open Hotline \($0.version)'s release on GitHub") } ?? Text("Open on GitHub"))
    }
  }

  /// Downloads a build's app to the Downloads folder, and shows it there in the Finder, or says why
  /// it couldn't.
  private func download(_ release: ReleaseNotes) {
    self.downloading = release.id
    Task {
      do {
        let file = try await ReleaseDownload.download(release)
        NSWorkspace.shared.activateFileViewerSelecting([file])
      }
      catch {
        self.downloadFailure = DownloadFailure(version: release.version, reason: error.localizedDescription)
      }
      self.downloading = nil
    }
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

  /// Shows the notes GitHub last gave, straight away, then asks it for them again, as one may have
  /// come out since.
  private func load() async {
    self.failure = nil
    if self.releases.isEmpty {
      self.show(ReleaseNotesCache.load())
    }
    do {
      self.show(try await GitHubReleases.fetch())
    }
    catch {
      self.failure = error as? GitHubReleases.Failure ?? .unexpected
    }
  }

  /// Shows builds' notes, with the build that's running chosen, or the newest without notes for it,
  /// unless you've chosen another.
  private func show(_ releases: [ReleaseNotes]) {
    guard !releases.isEmpty else {
      return
    }
    self.releases = releases
    if self.selection == nil || self.selection == self.picked {
      let pick = (releases.first { $0.build == self.currentBuild } ?? releases.first)?.id
      self.picked = pick
      self.selection = pick
    }
  }

  /// Why there aren't any notes, and what to do: wait for GitHub's limit to pass, as long as it
  /// says, or check the connection, or try again.
  static func explanation(of failure: GitHubReleases.Failure, now: Date = .now) -> String {
    switch failure {
    case .limited(let until):
      guard let until, until > now else {
        return String(localized: "GitHub is limiting requests from your network for now. Try again in a little while.")
      }
      let time = until.formatted(date: Calendar.current.isDate(until, inSameDayAs: now) ? .omitted : .abbreviated, time: .shortened)
      return String(localized: "GitHub is limiting requests from your network for now. Try again after \(time).")
    case .offline:
      return String(localized: "Check your connection to the internet, then try again.")
    case .unexpected:
      return String(localized: "GitHub didn't send them this time. Try again in a moment.")
    }
  }
}

/// A build in the list of them: its version, in semibold while it's newer than the one running, and
/// how long ago it came out, with a check in a circle on the one running, and a fainter check on those
/// before it, whose changes it has too.
struct ReleaseNotesRow: View {
  let release: ReleaseNotes
  /// The build that's running.
  let currentBuild: Int
  let now: Date

  var body: some View {
    HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        Text("Hotline \(self.release.version)")
          .fontWeight(self.release.build > self.currentBuild ? .semibold : .regular)
        Text(self.subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 0)

      if self.release.build == self.currentBuild {
        // In the words' color, which is white on the row's color when it's chosen, with the check
        // cut out of the circle, showing what's under it.
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.primary)
          .help("The version you're using")
          .accessibilityLabel("Installed")
      }
      else if self.release.build < self.currentBuild {
        // The installed one's check, as big and where it is, without its circle, and bold.
        Image(systemName: "checkmark.circle.fill")
          .symbolRenderingMode(.palette)
          .foregroundStyle(.tertiary, .clear)
          .fontWeight(.bold)
          .help("In the version you're using")
          .accessibilityLabel("In the version you're using")
      }
    }
    .padding(.vertical, 2)
  }

  /// How long ago it came out, and whether it's the build that's running.
  private var subtitle: String {
    let date = self.release.date.map { ReleaseNotesView.howLongAgo($0, now: self.now) }
    let installed = self.release.build == self.currentBuild ? String(localized: "Installed") : nil
    return [date, installed].compactMap { $0 }.joined(separator: " · ")
  }
}

/// One build's notes, in Hotline's own text, which shows their pictures, but not their videos or
/// GIFs, and not all of GitHub's Markdown: its header, then under a line, the notes themselves.
struct ReleaseNotesDetail: View {
  let release: ReleaseNotes
  let isInstalled: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      ReleaseNotesHeader(release: self.release, isInstalled: self.isInstalled)

      Divider()

      let notes = self.release.notes.trimmingCharacters(in: .whitespacesAndNewlines)
      MarkdownText(text: notes.isEmpty ? "_No release notes provided._" : notes, layout: Markdown.Layout(font: .systemFont(ofSize: 13), lineSpacing: 3))
    }
    .padding(24)
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// One build's notes as GitHub shows them, in a web view, which plays their videos and GIFs: its
/// header, then under a line, which stays put as they scroll, the notes, out to the window's sides,
/// for its scroller. The same page shows each build that's chosen, which takes a few hundredths of
/// a second. It's empty for the first one, for about a quarter of a second, and in Hotline's own
/// text, if it doesn't load.
struct ReleaseNotesWebDetail: View {
  let release: ReleaseNotes
  let isInstalled: Bool

  @State private var page: WebPage?
  @State private var failed = false

  private var html: String {
    GitHubReleases.htmlBody(of: self.release)
  }

  var body: some View {
    ZStack {
      if self.failed {
        ScrollView(.vertical) {
          ReleaseNotesDetail(release: self.release, isInstalled: self.isInstalled)
        }
        .id(self.release.id)
      }
      else {
        VStack(alignment: .leading, spacing: 0) {
          VStack(alignment: .leading, spacing: 16) {
            ReleaseNotesHeader(release: self.release, isInstalled: self.isInstalled)
            Divider()
          }
          .padding([.horizontal, .top], 24)

          // In the window as it loads, which has it at the window's size sooner.
          if let page = self.page {
            ReleaseNotesWebView(page: page)
          }
          else {
            Spacer(minLength: 0)
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      }
    }
    .task(id: self.html) {
      let page = self.page ?? ReleaseNotesWeb.page()
      self.page = page
      let shown = await ReleaseNotesWeb.show(self.html, style: .window, in: page)
      // Unless another build's been chosen since.
      guard !Task.isCancelled else {
        return
      }
      self.failed = !shown
    }
  }
}

/// A build's header: Hotline's icon, beside its version and when it came out, and at the other side,
/// whether it's the one running.
struct ReleaseNotesHeader: View {
  let release: ReleaseNotes
  let isInstalled: Bool

  var body: some View {
    HStack(spacing: 12) {
      Image(nsImage: NSApp.applicationIconImage)
        .resizable()
        .frame(width: 52, height: 52)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 4) {
        Text("Hotline \(self.release.version)")
          .font(.title2)
          .fontWeight(.semibold)
        if let date = self.release.date {
          Text(date.formatted(date: .long, time: .omitted))
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      Spacer(minLength: 0)

      if self.isInstalled {
        self.installed
      }
    }
  }

  /// That it's the build that's running: Installed, with a check, in white on a green capsule.
  private var installed: some View {
    HStack(spacing: 3) {
      Image(systemName: "checkmark")
        .fontWeight(.bold)
        .accessibilityHidden(true)
      Text("Installed")
    }
    .font(.subheadline.weight(.semibold))
    .foregroundStyle(.white)
    .padding(.horizontal, 7)
    .padding(.vertical, 2)
    .background(.green, in: .capsule)
  }
}

// MARK: - Release Notes as GitHub Shows Them

/// Notes in a web view, on what's behind it, without the gestures for going back, zooming or
/// previewing links, as it only shows them.
struct ReleaseNotesWebView: View {
  let page: WebPage

  var body: some View {
    WebView(self.page)
      .webViewContentBackground(.hidden)
      .webViewLinkPreviews(.disabled)
      .webViewMagnificationGestures(.disabled)
      .webViewBackForwardNavigationGestures(.disabled)
  }
}

/// Release notes as GitHub shows them, in HTML, in a web view, which plays their GIFs, shows their
/// videos, and has all of GitHub's Markdown, where Hotline's own text shows links and stills. It
/// runs none of their scripts, keeps nothing, loads only their pictures and videos, and opens their
/// links in the browser. Their pictures and videos open in a preview window, as a picture in chat
/// does. GIFs play by the system's Animated Images setting, which Hotline's own can't change.
@MainActor
enum ReleaseNotesWeb {
  /// Where the notes are, for their links, and the only page that loads in the web view.
  static let base = URL(string: "https://github.com/mierau/hotline/releases/")!

  enum Style {
    /// The Release Notes window's: 13 points, 24 points in from its sides.
    case window
    /// The update window's: 12 points, inside its box, with pictures and videos no taller than a
    /// preview.
    case update

    fileprivate var css: String {
      switch self {
      case .window:
        """
        body { padding: 16px 24px 24px; }
        """
      case .update:
        // GitHub's videos say how tall they can be themselves, which only !important overrides.
        """
        body { font-size: 12px; padding: 12px; }
        img, video { max-height: 200px !important; width: auto; }
        details.details-reset { display: inline-block; max-width: 100%; vertical-align: top; }
        details.details-reset video { width: auto; max-width: 100%; }
        .hotline-video { display: inline-block; vertical-align: top; }
        """
      }
    }
  }

  /// A page for notes, empty until they're shown in it, which opens their links in the browser, and
  /// their pictures and videos in a preview window, or as a test would rather.
  static func page(opening open: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }, previewing preview: @escaping @MainActor (PreviewFileInfo) -> Void = { AppState.openPreviewWindow?($0) }) -> WebPage {
    var configuration = WebPage.Configuration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultNavigationPreferences.allowsContentJavaScript = false
    configuration.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
    configuration.userContentController.add(MediaClicks(preview: preview), contentWorld: .defaultClient, name: "preview")
    return WebPage(configuration: configuration, navigationDecider: LinksInBrowser(open: open))
  }

  /// Hotline's own script in the page, in a world of its own, as the notes' don't run. A picture
  /// or video that's clicked goes to the preview window, rather than the browser, unless it's a
  /// link to something else, as a badge can be, with its name: a video's file's, which GitHub shows
  /// over it, or a picture's description, and its type, which GitHub gives a picture. A video shows
  /// its first frame, under a play button, rather than playing where it is.
  private static let script = """
  for (const video of document.querySelectorAll('video')) {
    video.removeAttribute('controls');
    const frame = document.createElement('span');
    frame.className = 'hotline-video';
    video.replaceWith(frame);
    frame.append(video);
  }
  document.addEventListener('click', (event) => {
    const media = event.target instanceof Element ? event.target.closest('img, video') : null;
    if (!media || !media.src) {
      return;
    }
    const link = media.closest('a[href]');
    if (link && link.href !== media.src) {
      return;
    }
    event.preventDefault();
    event.stopPropagation();
    const isVideo = media.tagName === 'VIDEO';
    const summary = isVideo ? media.closest('details')?.querySelector('summary') : null;
    window.webkit.messageHandlers.preview.postMessage({
      url: media.src,
      name: (isVideo ? summary?.textContent : media.getAttribute('alt')) ?? '',
      type: media.getAttribute('content-type-secured-asset') ?? '',
      video: isVideo,
    });
  }, true);
  """

  /// What a picture or a video from the notes is called in its preview window, and as a file: its
  /// name, as the page has it, or for one without, or with GitHub's own, Picture or Video, with the
  /// extension of its type, when it doesn't have one already.
  static func mediaName(_ name: String, type: String, isVideo: Bool) -> String {
    var name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    if name.isEmpty || name.lowercased() == "image" {
      name = isVideo ? "Video" : "Picture"
    }
    let named = UTType(filenameExtension: (name as NSString).pathExtension)
    if named?.conforms(to: .image) != true, named?.conforms(to: .audiovisualContent) != true,
       let pathExtension = UTType(mimeType: type)?.preferredFilenameExtension {
      name += ".\(pathExtension)"
    }
    return name
  }

  /// Hears from Hotline's script in the page about a picture or video that's clicked.
  private final class MediaClicks: NSObject, WKScriptMessageHandler {
    let preview: @MainActor (PreviewFileInfo) -> Void

    init(preview: @escaping @MainActor (PreviewFileInfo) -> Void) {
      self.preview = preview
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
      guard let clicked = message.body as? [String: Any], let link = clicked["url"] as? String,
            let url = URL(string: link), url.scheme?.lowercased() == "https" else {
        return
      }
      let name = ReleaseNotesWeb.mediaName(clicked["name"] as? String ?? "", type: clicked["type"] as? String ?? "", isVideo: clicked["video"] as? Bool ?? false)
      self.preview(PreviewFileInfo(webImage: url, name: name))
    }
  }

  /// Shows notes in a page, in a style, and waits until their words are in, which takes up to a
  /// quarter of a second in the first page Hotline makes, and under a tenth after. Their pictures
  /// and videos come in after. False if they didn't load.
  @discardableResult
  static func show(_ html: String, style: Style, in page: WebPage) async -> Bool {
    // Until it's showing them, as loaded waits for a video's first frame, which can take seconds.
    do {
      for try await event in page.load(html: Self.document(html, style: style), baseURL: Self.base) {
        if event == .committed || event == .finished {
          break
        }
      }
    }
    catch {
      return false
    }
    // Then until they've all been read in, which is soon after.
    for _ in 0..<40 {
      let state = try? await page.callJavaScript("return document.readyState", contentWorld: .defaultClient)
      if let state = state as? String, state != "loading" {
        break
      }
      try? await Task.sleep(for: .milliseconds(5))
    }
    return true
  }

  /// Notes, in a page of their own, in a style, which loads only their pictures and videos.
  static func document(_ html: String, style: Style) -> String {
    let policy = "default-src 'none'; img-src https: data:; media-src https:; style-src 'unsafe-inline'"
    return "<!doctype html><html><head><meta charset=\"utf-8\"><meta http-equiv=\"Content-Security-Policy\" content=\"\(policy)\"><style>\(Self.css)\(style.css)</style></head><body>\(html)</body></html>"
  }

  /// GitHub's HTML as Hotline's own text has it: the system's font and colors, its bullets and
  /// headings, and pictures and videos no wider than the notes.
  private static let css = """
  :root { color-scheme: light dark; }
  html, body { margin: 0; padding: 0; background: transparent; }
  body { font: 13px/1.45 -apple-system, system-ui, sans-serif; color: CanvasText; color: -apple-system-label; overflow-wrap: anywhere; }
  p { margin: 0 0 6px; }
  h1, h2, h3, h4, h5, h6 { margin: 14px 0 6px; line-height: 1.25; font-size: 1em; font-weight: bold; }
  h1 { font-size: 1.5em; } h2 { font-size: 1.3em; } h3 { font-size: 1.15em; }
  body > :first-child, body > .markdown-heading:first-child > * { margin-top: 0; }
  .markdown-heading .anchor { display: none; }
  ul, ol { margin: 0 0 8px; padding-left: 10px; }
  ol { padding-left: 22px; }
  li > ul, li > ol { margin: 2px 0 0; }
  ul { list-style: none; }
  ul > li { position: relative; }
  ul > li::before { content: "\\2022"; position: absolute; left: -10px; color: rgba(128,128,128,.6); color: -apple-system-tertiary-label; }
  .contains-task-list { padding-left: 0; }
  li.task-list-item::before { content: none; }
  .task-list-item-checkbox { margin: 0 6px 0 0; vertical-align: -1px; }
  a { color: LinkText; text-decoration: none; }
  img, video { max-width: 100%; height: auto; border-radius: 6px; cursor: pointer; }
  .hotline-video { position: relative; display: block; }
  .hotline-video::after { content: ""; position: absolute; top: 50%; left: 50%; width: 52px; height: 52px; margin: -26px 0 0 -26px; border-radius: 50%; pointer-events: none; -webkit-backdrop-filter: blur(8px); background: rgba(0,0,0,.45) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 24 24'%3E%3Cpath fill='white' d='M9 6.5v11l9-5.5z'/%3E%3C/svg%3E") no-repeat center / 26px; }
  code, kbd { font: 12px ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(0,0,0,.05); padding: 1px 4px; border-radius: 4px; }
  kbd { border: 1px solid rgba(128,128,128,.3); }
  pre { background: rgba(0,0,0,.04); padding: 10px; border-radius: 6px; overflow-x: auto; }
  pre code { background: none; padding: 0; }
  blockquote, .markdown-alert { margin: 0 0 8px; padding-left: 10px; border-left: 3px solid rgba(128,128,128,.35); color: rgba(128,128,128,1); color: -apple-system-secondary-label; }
  .markdown-alert-title { display: flex; align-items: center; gap: 4px; font-weight: 600; }
  hr { border: 0; border-top: 1px solid rgba(128,128,128,.3); margin: 12px 0; }
  table { border-collapse: collapse; margin: 0 0 8px; }
  th, td { border: 1px solid rgba(128,128,128,.3); padding: 4px 8px; }
  details.details-reset { border: 1px solid rgba(128,128,128,.3); border-radius: 8px; overflow: hidden; margin: 8px 0; }
  details.details-reset > summary { list-style: none; display: flex; align-items: center; gap: 6px; padding: 6px 10px; font-size: 12px; color: rgba(128,128,128,1); color: -apple-system-secondary-label; }
  details.details-reset > summary::-webkit-details-marker { display: none; }
  details.details-reset video { display: block; width: 100%; border-radius: 0; }
  .dropdown-caret { display: none; }
  svg.octicon { fill: currentColor; }
  @media (prefers-color-scheme: dark) {
    code, kbd { background: rgba(255,255,255,.08); }
    pre { background: rgba(255,255,255,.06); }
  }
  """

  /// Lets only the notes load in the page, and jumps within them, and opens other links in the
  /// browser, whether they're clicked, opened from a link's menu, or for a new window.
  private struct LinksInBrowser: WebPage.NavigationDeciding {
    let open: @MainActor (URL) -> Void

    @MainActor
    func decidePolicy(for action: WebPage.NavigationAction, preferences: inout WebPage.NavigationPreferences) async -> WKNavigationActionPolicy {
      guard let url = action.request.url else {
        return .cancel
      }
      var page = URLComponents(url: url, resolvingAgainstBaseURL: false)
      page?.fragment = nil
      if page?.url == ReleaseNotesWeb.base {
        return .allow
      }
      // Not what a frame in them would load, which isn't a link.
      if action.target?.isMainFrame ?? true, let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
        self.open(url)
      }
      return .cancel
    }
  }
}
