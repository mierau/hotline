import SwiftUI
import SwiftData
import CloudKit
import UniformTypeIdentifiers

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

class AppDelegate: NSObject, NSApplicationDelegate {
  private var cloudKitObserverToken: Any? = nil
  
  func applicationDidFinishLaunching(_ notification: Notification) {
    AppLaunchState.shared.launchState = .launched
    
    CKContainer.default().accountStatus { status, error in
      switch status {
      case .noAccount:
        print("iCloud Unavailable")
        
        // We mark CloudKit has available now since we're not waiting on
        // a server sync or anything.
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
    
//    if FileManager.default.ubiquityIdentityToken == nil {
//      print("iCloud Unavailable")
//      
//      // We mark CloudKit has available now since we're not waiting on
//      // a server sync or anything.
//      AppState.shared.cloudKitReady = true
//    }
//    else {
//      print("iCloud Available")
//      
//      self.cloudKitObserverToken = NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: OperationQueue.main) { [weak self] note in
//        print("iCloud Changed!")
//        AppState.shared.cloudKitReady = true
//
//        guard let token = self?.cloudKitObserverToken else { return }
//        NotificationCenter.default.removeObserver(token)
//      }
//    }

    Task {
      await AppUpdate.shared.checkForUpdatesOnLaunch()
    }
  }
  
  func applicationWillTerminate(_ notification: Notification) {
    AppLaunchState.shared.launchState = .terminated
  }
}

@main
struct Application: App {
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openURL) private var openURL
  
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  
  @State private var hotlinePanel: HotlinePanel? = nil
  @State private var selection: TrackerSelection? = nil
  @Bindable private var update = AppUpdate.shared

  @FocusedValue(\.activeHotlineModel) private var activeHotline: Hotline?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?
  
  private var modelContainer: ModelContainer = {
    let schema = Schema([
      Bookmark.self
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .private("iCloud.co.goodmake.hotline"))
    let modelContainer = try! ModelContainer(for: schema, configurations: [config])
    
    // Print local SwiftData sqlite file.
//    print(modelContainer.configurations.first?.url.path(percentEncoded: false))
    
    return modelContainer
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
        if Prefs.shared.showBannerToolbar {
          showBannerWindow()
        }
      }
    }
    .onChange(of: self.update.showWindow) {
      if self.update.showWindow {
        self.openWindow(id: "update")
      }
    }
    
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
        Button("About Hotline") {
          openWindow(id: "about")
        }
                
        Button("Check for Updates...") {
          Task {
            await AppUpdate.shared.checkForUpdatesManually()
          }
        }
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
    .modelContainer(self.modelContainer)
    .defaultSize(width: 750, height: 700)
    .defaultPosition(.center)
    .onChange(of: activeServerState) {
      AppState.shared.activeServerState = activeServerState
    }
    .onChange(of: activeHotline) {
      AppState.shared.activeHotline = activeHotline
    }
    .onChange(of: activeHotline?.serverTitle) {
      if let hotline = activeHotline {
        AppState.shared.activeServerName = hotline.serverTitle
      }
    }
    .onChange(of: activeHotline?.bannerImage) {
      withAnimation {
        AppState.shared.activeServerBanner = activeHotline?.bannerImage
      }
    }
    .onChange(of: activeHotline) {
      AppState.shared.activeHotline = activeHotline
      if let hotline = activeHotline {
        AppState.shared.activeServerName = hotline.serverTitle
      }
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("Connect to Server...") {
          openWindow(id: "server")
        }
        .keyboardShortcut(.init("K"), modifiers: .command)
      }
      CommandGroup(after: .singleWindowList) {
        Button("Toolbar") {
          toggleBannerWindow()
        }
        .keyboardShortcut(.init("\\"), modifiers: [.shift, .command])
      }
      CommandGroup(after: .help) {
        Divider()
        Button("Request Feature...") {
          if let url = URL(string: "https://github.com/mierau/hotline/issues/new?labels=enhancement") {
            openURL(url)
          }
        }
        Button("Report Bug...") {
          if let url = URL(string: "https://github.com/mierau/hotline/issues/new?labels=bug") {
            openURL(url)
          }
        }
        Divider()
        Button("Open Latest Release Page...") {
          if let url = URL(string: "https://github.com/mierau/hotline/releases/latest") {
            openURL(url)
          }
        }
      }
      CommandMenu("Server") {
        Button("Connect") {
          guard let selection else {
            return
          }
          connect(to: selection)
        }
        .disabled(selection == nil || selection?.server == nil)
        .keyboardShortcut(.downArrow, modifiers: .command)
        Button("Disconnect") {
          activeHotline?.disconnect()
        }
        .disabled(activeHotline?.status == .disconnected)
        Divider()
        Button("Broadcast Message...") {
          // TODO: Implement broadcast message when user is allowed.
        }
        .disabled(true)
        .keyboardShortcut(.init("B"), modifiers: .command)
        Divider()
        Button("Show Chat") {
          activeServerState?.selection = .chat
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("1"), modifiers: .command)
        Button("Show Message Board") {
          activeServerState?.selection = .board
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("2"), modifiers: .command)
        Button("Show News") {
          activeServerState?.selection = .news
        }
        .disabled(activeHotline?.status != .loggedIn || (activeHotline?.serverVersion ?? 0) < 151)
        .keyboardShortcut(.init("3"), modifiers: .command)
        Button("Show Files") {
          activeServerState?.selection = .files
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("4"), modifiers: .command)
        Button("Show Accounts") {
          activeServerState?.selection = .accounts
        }
        .disabled(activeHotline?.status != .loggedIn || activeHotline?.access?.contains(.canOpenUsers) != true  )
        .keyboardShortcut(.init("5"), modifiers: .command)
      }
    }
    
    // MARK: Settings Window
    Settings {
      SettingsView()
    }
        
    // MARK: Image Preview Window
    WindowGroup(id: "preview-image", for: PreviewFileInfo.self) { $info in
      FilePreviewImageView(info: $info)
    }
    .windowResizability(.contentSize)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: true))
    .defaultSize(width: 350, height: 150)
    .defaultPosition(.center)
    
    // MARK: Text Preview Window
    WindowGroup(id: "preview-text", for: PreviewFileInfo.self) { $info in
      FilePreviewTextView(info: $info)
    }
    .windowResizability(.automatic)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: true))
    .defaultSize(width: 450, height: 550)
    .defaultPosition(.center)
  }

  func connect(to item: TrackerSelection) {
    if let server = item.server {
      openWindow(id: "server", value: server)
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
