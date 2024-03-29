import SwiftUI
import SwiftData
import UniformTypeIdentifiers

@main
struct Application: App {
  #if os(iOS)
  private var model = Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient())
  #endif
  
  #if os(macOS)
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openURL) private var openURL
  #endif
  
  @State private var preferences = Prefs()
  @State private var soundEffects = SoundEffectPlayer()
  @State private var bookmarks = Bookmarks()
  
  @FocusedValue(\.activeHotlineModel) private var activeHotline: Hotline?
  @FocusedValue(\.activeServerState) private var activeServerState: ServerState?
  
  var body: some Scene {
    #if os(iOS)
    WindowGroup {
      TrackerView()
        .environment(model)
    }
    #elseif os(macOS)
    // MARK: Tracker Window
    Window("Servers", id: "servers") {
      TrackerView()
        .frame(minWidth: 250, minHeight: 250)
        .environment(bookmarks)
    }
    .keyboardShortcut(.init(.init("R"), modifiers: .command))
    .defaultSize(width: 700, height: 550)
    .defaultPosition(.center)
        
    // MARK: Server Window
    WindowGroup(id: "server", for: Server.self) { server in
      ServerView(server: server)
        .frame(minWidth: 430, minHeight: 300)
        .environment(preferences)
        .environment(soundEffects)
        .environment(bookmarks)
    } defaultValue: {
      Server(name: nil, description: nil, address: "")
    }
    .defaultSize(width: 750, height: 700)
    .defaultPosition(.center)
    .commands {
      CommandGroup(replacing: CommandGroupPlacement.newItem) {
        Button("Connect to Server...") {
          openWindow(id: "server")
        }
        .keyboardShortcut(.init("K"), modifiers: .command)
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
      }
      CommandMenu("Server") {
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
        Button("Show News") {
          activeServerState?.selection = .news
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("2"), modifiers: .command)
        Button("Show Message Board") {
          activeServerState?.selection = .board
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("3"), modifiers: .command)
        Button("Show Files") {
          activeServerState?.selection = .files
        }
        .disabled(activeHotline?.status != .loggedIn)
        .keyboardShortcut(.init("4"), modifiers: .command)
      }
    }
    
    // MARK: Settings Window
    Settings {
      SettingsView()
        .environment(preferences)
    }
    
    // MARK: News Editor Window
//    WindowGroup(id: "news-editor", for: NewsArticle.self) { $article in
//      NewsEditorView(article: $article)
//    }
//    .windowResizability(.contentSize)
//    .windowStyle(.titleBar)
//    .windowToolbarStyle(.unifiedCompact(showsTitle: true))
//    .defaultSize(width: 450, height: 550)
//    .defaultPosition(.center)
    
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

    #endif
  }
}
