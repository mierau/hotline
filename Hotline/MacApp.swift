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

    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        print("Notification authorization error: \(error.localizedDescription)")
      }
    }
    
    if FileManager.default.ubiquityIdentityToken != nil {
      CKContainer.default().accountStatus { status, error in
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

          self.cloudKitObserverToken = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: OperationQueue.main) { [weak self] note in
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
  
  func applicationWillTerminate(_ notification: Notification) {
    AppLaunchState.shared.launchState = .terminated
  }

  // MARK: - URL Handling

  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard url.scheme?.lowercased() == "hotline" else { continue }
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
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openWindow) private var openWindow
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openURL) private var openURL
  
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  
  @State private var hotlinePanel: HotlinePanel? = nil
  @State private var selection: TrackerSelection? = nil
  @Bindable private var update = AppUpdate.shared

  @FocusedValue(\.activeHotlineModel) private var activeHotline: HotlineState?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?
  
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
      TrackerView(selection: $selection)
        .frame(minWidth: 250, minHeight: 250)
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
          self.showBannerWindow()
        }
      }
    }
    .onChange(of: Prefs.shared.hasCompletedOnboarding) {
      if Prefs.shared.hasCompletedOnboarding && Prefs.shared.showBannerToolbar {
        self.showBannerWindow()
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
      CommandGroup(replacing: CommandGroupPlacement.appInfo) {
        Button("About Hotline", systemImage: "info.circle") {
          openWindow(id: "about")
        }
                
        Button("Check for Updates...", systemImage: "questionmark.diamond") {
          Task {
            await AppUpdate.shared.checkForUpdatesManually()
          }
        }
      }
      CommandGroup(replacing: .appSettings) {
        Button("Settings...", systemImage: "gearshape") {
          openWindow(id: "settings")
        }
        .keyboardShortcut(",", modifiers: .command)
      }
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
    .onChange(of: activeServerState) {
      AppState.shared.activeServerState = self.activeServerState
    }
    .onChange(of: activeHotline) {
      AppState.shared.activeHotline = self.activeHotline
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("Connect to Server...", systemImage: "globe.americas.fill") {
          self.openWindow(id: "server")
        }
        .keyboardShortcut(.init("K"), modifiers: .command)
      }
      CommandGroup(replacing: .sidebar) {
        Button("Show Sidebar") {
          withAnimation {
            activeServerState?.columnVisibility = .all
          }
        }
        .keyboardShortcut("S", modifiers: [.command, .option])
      }
      CommandGroup(before: .singleWindowList) {
        Button("Toolbar") {
          self.toggleBannerWindow()
        }
        .keyboardShortcut(.init("\\"), modifiers: [.shift, .command])
      }
      CommandGroup(after: .help) {
        Divider()
        Button("Request Feature...", systemImage: "sparkles.2") {
          if let url = URL(string: "https://github.com/mierau/hotline/issues/new?labels=enhancement") {
            self.openURL(url)
          }
        }
        Button("Report Bug...", systemImage: "ladybug") {
          if let url = URL(string: "https://github.com/mierau/hotline/issues/new?labels=bug") {
            self.openURL(url)
          }
        }
        Divider()
        Button("View Latest Release...", systemImage: "app.gift") {
          if let url = URL(string: "https://github.com/mierau/hotline/releases/latest") {
            self.openURL(url)
          }
        }
      }
      CommandMenu("Server") {
        Button("Connect", systemImage: "globe.americas.fill") {
          guard let selection else {
            return
          }
          self.connect(to: selection)
        }
        .disabled(selection == nil || selection?.server == nil)
        .keyboardShortcut(.downArrow, modifiers: .command)
        
        Button("Disconnect", systemImage: "xmark") {
          if let hotline = activeHotline {
            Task {
              await hotline.disconnect()
            }
          }
        }
        .disabled(activeHotline?.status == .disconnected)
        
        Divider()
        
        Button("Broadcast Message...", systemImage: "megaphone") {
          activeServerState?.broadcastShown = true
        }
        .disabled(activeHotline?.access?.contains(.canBroadcast) != true)
        .keyboardShortcut(.init("B"), modifiers: .command)
        
        Divider()
        
        Button("Chat", systemImage: "bubble.left") {
          activeServerState?.selection = .chat
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("1"), modifiers: .command)
        
        Button("Board", systemImage: "pin") {
          activeServerState?.selection = .board
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("2"), modifiers: .command)
        
        Button("News", systemImage: "newspaper") {
          activeServerState?.selection = .news
        }
        .disabled(activeHotline?.status != .loggedIn || (activeHotline?.serverVersion ?? 0) < 151)
        .keyboardShortcut(.init("3"), modifiers: .command)
        
        Button("Files", systemImage: "folder") {
          activeServerState?.selection = .files
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("4"), modifiers: .command)
        
        Divider()
        
        Button("Manage Accounts...", systemImage: "person.2") {
          activeServerState?.accountsShown = true
        }
        .disabled(activeHotline?.status != .loggedIn || activeHotline?.access?.contains(.canOpenUsers) != true)
      }
    }
    
    // MARK: Settings Window
    Window("Settings", id: "settings") {
      SettingsView()
        .frame(width: 570, height: 500)
    }
    .windowResizability(.contentSize)
    .commandsRemoved()

    // MARK: Transfers Window
    Window("Transfers", id: "transfers") {
      TransfersView()
        .frame(minWidth: 500, minHeight: 200)
    }
    .defaultSize(width: 500, height: 400)
    .defaultPosition(.topTrailing)
    .keyboardShortcut(.init("T"), modifiers: [.shift, .command])
        
    // MARK: Image Preview Window
    WindowGroup(id: "preview-image", for: PreviewFileInfo.self) { $info in
      FilePreviewImageView(info: $info)
    }
    .windowResizability(.contentSize)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: true))
    .defaultSize(width: 350, height: 150)
    .defaultPosition(.center)
    .restorationBehavior(.disabled)
    
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

    // MARK: QuickLook Preview Window
    WindowGroup(id: "preview-quicklook", for: PreviewFileInfo.self) { $info in
      FilePreviewQuickLookView(info: $info)
    }
    .windowManagerRole(.associated)
    .windowResizability(.automatic)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: true))
    .defaultSize(width: 450, height: 550)
    .defaultPosition(.center)
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

  func connect(to item: TrackerSelection) {
    if let server = item.server {
      self.openWindow(id: "server", value: server)
    }
  }

  func showBannerWindow() {
    if hotlinePanel == nil {
      hotlinePanel = HotlinePanel(HotlinePanelView())
    }
    
    if hotlinePanel?.isVisible == false {
      hotlinePanel?.orderFront(nil)
      Prefs.shared.showBannerToolbar = true
    }
  }
  
  func toggleBannerWindow() {
    if hotlinePanel == nil {
      hotlinePanel = HotlinePanel(HotlinePanelView())
    }
    
    if hotlinePanel?.isVisible == true {
      hotlinePanel?.orderOut(nil)
      Prefs.shared.showBannerToolbar = false
    }
    else {
      hotlinePanel?.orderFront(nil)
      Prefs.shared.showBannerToolbar = true
    }
  }
}
