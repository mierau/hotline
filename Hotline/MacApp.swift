import SwiftUI
import SwiftData
import CloudKit
import UniformTypeIdentifiers
import UserNotifications
import Darwin

@Observable
final class AppLaunchState {
  static let shared = AppLaunchState()
  
  enum LaunchState {
    case loading
    case launched
    case terminated
  }
  
  var launchState = LaunchState.loading
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
  private var cloudKitObserverToken: Any? = nil

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppLaunchState.shared.launchState = .launched

    SoundEffects.prepare()

    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        print("Notification authorization error: \(error.localizedDescription)")
      }
    }
    
    if FileManager.default.ubiquityIdentityToken != nil {
      CKContainer.default().accountStatus { [weak self] status, error in
        if let error = error {
          print("iCloud account status error: \(error.localizedDescription)")
          AppState.shared.cloudKitReady = true
          return
        }

        switch status {
        case .noAccount:
          print("iCloud Unavailable")
          AppState.shared.cloudKitReady = true
        default:
          print("iCloud Available")

          self?.cloudKitObserverToken = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: OperationQueue.main) { note in
            print("iCloud Changed!")
            AppState.shared.cloudKitReady = true

            guard let token = self?.cloudKitObserverToken else { return }
            NotificationCenter.default.removeObserver(token)
          }
        }
      }
    } else {
      print("iCloud not signed in, skipping CloudKit")
      AppState.shared.cloudKitReady = true
    }

    Task {
      await AppUpdate.shared.checkForUpdatesOnLaunch()
    }
  }
  
  /// Asks first when quitting would stop transfers or lose posts being written.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard let losses = AppState.shared.quitLosses else {
      return .terminateNow
    }

    // Quitting from the Dock leaves another app in front, where the alert would be missed.
    NSApplication.shared.activate()

    let alert = NSAlert()
    alert.messageText = "Quit Hotline?"
    alert.informativeText = losses
    alert.addButton(withTitle: "Quit")
    alert.addButton(withTitle: "Cancel")
    return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
  }

  func applicationWillTerminate(_ notification: Notification) {
    AppLaunchState.shared.launchState = .terminated
  }

  // MARK: - URL Handling

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard Server.isLink(url) else { continue }
      if let server = Server(url: url) {
        AppState.shared.pendingServerOpen = server
      }
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo

    if let type = userInfo["type"] as? String, type == "watchWord" || type == "mention" {
      Task { @MainActor in
        AppState.shared.activeServerState?.selection = .chat
        NSApplication.shared.activate()
      }
    } else if let type = userInfo["type"] as? String, type == "transfer" {
      Task { @MainActor in
        AppState.openTransfersWindow?()
        NSApplication.shared.activate()
      }
    } else if let type = userInfo["type"] as? String, type == "privateChat", let chatID = userInfo["chatID"] as? UInt32 {
      Task { @MainActor in
        AppState.shared.activeServerState?.selection = .privateChat(chatID: chatID)
        NSApplication.shared.activate()
      }
    } else if let userID = userInfo["userID"] as? UInt16 {
      Task { @MainActor in
        AppState.shared.activeServerState?.selection = .user(userID: userID)
        NSApplication.shared.activate()
      }
    }
    completionHandler()
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    completionHandler([])
  }
}


@main
struct Application: App {
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow

  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @Bindable private var update = AppUpdate.shared

  private var modelContainer: ModelContainer = {
    let schema = Schema([
      Bookmark.self,
    ])

    let hasICloud = FileManager.default.ubiquityIdentityToken != nil

    if hasICloud {
      print("iCloud signed in, using CloudKit-backed storage")
      let cloudKitConfiguration = ModelConfiguration(
        schema: schema,
        isStoredInMemoryOnly: false,
        cloudKitDatabase: .private("iCloud.co.goodmake.hotline")
      )
      return try! ModelContainer(for: schema, configurations: [cloudKitConfiguration])
    }

    print("iCloud unavailable, using local-only storage")
    let localConfiguration = ModelConfiguration(
      schema: schema,
      isStoredInMemoryOnly: false
    )
    return try! ModelContainer(for: schema, configurations: [localConfiguration])
  }()
    
  var body: some Scene {
    // MARK: Tracker Window
    Window("Servers", id: "servers") {
      TrackerView()
        .frame(minWidth: 250, minHeight: 250)
        .focusedSceneValue(\.focusedAppWindow, .servers)
    }
    .modelContainer(self.modelContainer)
    .defaultSize(width: 700, height: 550)
    .defaultPosition(.center)
    .keyboardShortcut(.init("R"), modifiers: .command)
    .onChange(of: AppLaunchState.shared.launchState) {
      if AppLaunchState.shared.launchState == .launched {
        AppState.openTransfersWindow = {
          self.openWindow(id: "transfers")
        }
        if !Prefs.shared.hasCompletedOnboarding {
          self.dismissWindow(id: "servers")
          self.openWindow(id: "onboarding")
        } else if Prefs.shared.showBannerToolbar {
          AppState.shared.showBannerToolbar()
        }
      }
    }
    .onChange(of: Prefs.shared.hasCompletedOnboarding) {
      if Prefs.shared.hasCompletedOnboarding && Prefs.shared.showBannerToolbar {
        AppState.shared.showBannerToolbar()
      }
    }
    .onChange(of: self.update.showWindow) {
      if self.update.showWindow {
        self.openWindow(id: "update")
      }
    }
    .onChange(of: AppState.shared.pendingServerOpen) {
      guard var server = AppState.shared.pendingServerOpen else { return }
      AppState.shared.pendingServerOpen = nil

      // Use saved bookmark credentials if the URL didn't include any.
      self.mergeBookmarkCredentials(into: &server)

      // Signal for already-connected servers to navigate to the linked section.
      if server.initialSection != nil {
        AppState.shared.pendingLink = server
      }

      self.openWindow(id: "server", value: server)
    }
    
    // MARK: Onboarding Window
    Window("Welcome", id: "onboarding") {
      OnboardingView()
        .background(Color.hotlineRed, ignoresSafeAreaEdges: .all)
        .windowFullScreenBehavior(.disabled)
        .toolbar(removing: .title)
        .gesture(WindowDragGesture())
        .background(
          WindowConfigurator { window in
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true

            if let btn = window.standardWindowButton(.closeButton) {
              btn.isHidden = true
            }
            if let btn = window.standardWindowButton(.zoomButton) {
              btn.isHidden = true
            }
            if let btn = window.standardWindowButton(.miniaturizeButton) {
              btn.isHidden = true
            }
          }
        )
    }
    .windowResizability(.contentSize)
    .windowStyle(.hiddenTitleBar)
    .restorationBehavior(.disabled)
    .defaultPosition(.center)
    .commandsRemoved()

    // MARK: About Box
    Window("About", id: "about") {
      AboutView()
        .background(Color.hotlineRed, ignoresSafeAreaEdges: .all)
        .windowFullScreenBehavior(.disabled)
        .toolbar(removing: .title)
        .gesture(WindowDragGesture())
        .background(
          WindowConfigurator { window in
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.isMovableByWindowBackground = true
            
            if let closeButton = window.standardWindowButton(.closeButton) {
              closeButton.isHidden = false   // make sure it’s visible
              closeButton.isEnabled = true
            }
            
            if let btn = window.standardWindowButton(.zoomButton) {
              btn.isHidden = true
            }
            
            if let btn = window.standardWindowButton(.miniaturizeButton) {
              btn.isHidden = true
            }
          }
        )
    }
    .windowResizability(.contentSize)
    .windowStyle(.hiddenTitleBar)
    .restorationBehavior(.disabled)
    .defaultPosition(.center)
    .commandsRemoved() // Remove About that was automatically added to Window menu.
    .commands {
      AppMenuCommands()
    }
    
    // MARK: Update Window
    Window("New Update", id: "update") {
      AppUpdateView()
        .windowFullScreenBehavior(.disabled)
    }
    .windowResizability(.contentSize)
    .windowStyle(.hiddenTitleBar)
    .restorationBehavior(.disabled)
    .defaultPosition(.center)
    .commandsRemoved()
    
    // MARK: Server Window
    ServerWindows(modelContainer: self.modelContainer)
      .commands {
        FileMenuCommands()
        FormatMenuCommands()
        SidebarCommands()
        WindowMenuCommands()
        HelpMenuCommands()
        ServerMenuCommands()
      }

    // MARK: Settings Window
    Window("Settings", id: "settings") {
      SettingsView()
        .frame(width: 570, height: 500)
        .focusedSceneValue(\.focusedAppWindow, .settings)
    }
    .windowResizability(.contentSize)
    .commandsRemoved()

    // MARK: Transfers Window
    Window("Transfers", id: "transfers") {
      TransfersView()
        .frame(minWidth: 500, minHeight: 200)
        .focusedSceneValue(\.focusedAppWindow, .transfers)
    }
    .defaultSize(width: 500, height: 400)
    .defaultPosition(.topTrailing)
    .keyboardShortcut(.init("T"), modifiers: [.shift, .command])
        
    // MARK: Text Preview Window
    WindowGroup(id: "preview-text", for: PreviewFileInfo.self) { $info in
      FilePreviewTextView(info: $info)
    }
    .windowResizability(.automatic)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: true))
    .defaultSize(width: 450, height: 550)
    .defaultPosition(.center)
    .restorationBehavior(.disabled)

    // MARK: Chat History Window
    WindowGroup("Chat History", id: "chat-log", for: ChatStore.SessionKey.self) { $key in
      ChatLogView(key: key)
    }
    .defaultSize(width: 640, height: 720)
    .restorationBehavior(.disabled)

    // MARK: QuickLook Preview Window
    WindowGroup(id: "preview-quicklook", for: PreviewFileInfo.self) { $info in
      FilePreviewQuickLookView(info: $info)
    }
    .windowManagerRole(.associated)
    .windowResizability(.automatic)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unified(showsTitle: true))
    // As big as what it shows first: just big enough for a picture's, a video's or audio's row as
    // it comes, which the window grows from to fit what it is, and bigger for anything else.
    .defaultWindowPlacement { content, _ in
      let size = content.sizeThatFits(.unspecified)
      guard size.width.isFinite, size.height.isFinite, size.width >= 300, size.height >= 80 else {
        return WindowPlacement(.center, size: CGSize(width: 450, height: 498))
      }
      return WindowPlacement(.center, size: size)
    }
    .restorationBehavior(.disabled)
  }

  /// Look up bookmarks for a matching server and merge saved credentials.
  private func mergeBookmarkCredentials(into server: inout Server) {
    let context = ModelContext(self.modelContainer)
    let descriptor = FetchDescriptor<Bookmark>()
    guard let bookmarks = try? context.fetch(descriptor) else { return }

    if let bookmark = bookmarks.first(where: {
      $0.type == .server && $0.address.lowercased() == server.address && $0.port == server.port
    }) {
      if server.login.isEmpty, let login = bookmark.login, !login.isEmpty {
        server.login = login
      }
      if server.password.isEmpty, let password = bookmark.password, !password.isEmpty {
        server.password = password
      }
    }
  }
}

// MARK: - Server Windows

/// Windows for connecting to and using servers. This scene, rather than Application, follows
/// which window is in front, so a window coming forward only updates this scene.
struct ServerWindows: Scene {
  let modelContainer: ModelContainer

  @FocusedValue(\.activeHotlineModel) private var activeHotline: HotlineState?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?
  @FocusedValue(\.focusedAppWindow) private var focusedAppWindow: FocusedAppWindow?

  var body: some Scene {
    WindowGroup(id: "server", for: Server.self) { server in
      ServerView(server: server)
        .frame(minWidth: 430, minHeight: 300)
    } defaultValue: {
      Server(name: nil, description: nil, address: "")
    }
//    .windowStyle(.hiddenTitleBar)
    .defaultSize(width: 780, height: 640)
    .defaultPosition(.center)
    .modelContainer(self.modelContainer)
    .onChange(of: self.activeServerState) {
      // Only track server windows coming forward. Focusing another kind of window keeps the
      // last server as the one the banner toolbar controls; ServerView reports when it closes.
      if let hotline = self.activeHotline, let state = self.activeServerState {
        AppState.shared.serverWindowFocused(hotline: hotline, state: state)
      }
    }
    .onChange(of: self.focusedAppWindow) {
      AppState.shared.focusedWindow = self.focusedAppWindow
    }
  }
}
