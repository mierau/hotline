import SwiftUI
import SwiftData

/// What a server window shows before it's connected, like a browser's address bar: the server's
/// address, with servers from your bookmarks and your trackers suggested as you type, and Connect
/// beside it. A login and password, for servers where you have an account, are a click away, and
/// where they'd be, servers you've been to lately, and bookmarked ones, to connect to in a click.
struct ConnectView: View {
  @Environment(\.appearsActive) private var appearsActive
  @Query(sort: \Bookmark.order) private var bookmarks: [Bookmark]

  @Binding var address: String
  @Binding var login: String
  @Binding var password: String

  /// Whether it's connecting, with what it's doing in `status`.
  var isConnecting: Bool = false
  /// What's happening while it's connecting, under the address.
  var status: String = ""
  var cancel: (() -> Void)? = nil
  var action: (() -> Void)? = nil

  @State private var showsAccount: Bool = false
  @State private var accountToggleHovered: Bool = false
  @State private var suggestions = ServerSuggestions()
  @State private var bookmarkSheetPresented: Bool = false
  /// Whether the suggestions show under the address: once something's typed, until one's chosen
  /// or they're put away.
  @State private var showsSuggestions: Bool = false
  /// The suggestion picked out with the arrow keys or the pointer, for Return to choose.
  @State private var selectedSuggestion: ServerSuggestion.ID?
  /// Set as a suggestion goes into the address, so that doesn't bring the suggestions back.
  @State private var choosingSuggestion: Bool = false
  /// Whether the servers to connect to in a click have come in, a moment after the form shows.
  @State private var quickServersShown: Bool = false
  /// How wide the room for them is, for how many columns they're in.
  @State private var quickServersWidth: CGFloat = 0

  private enum FocusFields {
    case address
    case login
    case password
  }

  @FocusState private var focusedField: FocusFields?

  /// As tall as the extra-large Connect beside it.
  private static let addressHeight: CGFloat = 36

  var body: some View {
    GlassGroup(spacing: 10) {
      HStack(alignment: .top, spacing: 10) {
        VStack(spacing: 12) {
          self.addressField
          if self.isConnecting {
            HStack(spacing: 6) {
              ProgressView()
                .controlSize(.mini)
              Text(self.status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                // From one step to the next.
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.2), value: self.status)
            }
          }
          else {
            self.accountToggle
          }
          // The login and password, or while they don't show, servers to connect to in a click, in
          // the login and password's room, kept either way, so the address doesn't move when they
          // show: two rows as tall as the address, with room above and below each, and the line
          // between them.
          ZStack(alignment: .top) {
            if self.showsAccount {
              self.accountFields
                .transition(.opacity)
            }
            else {
              self.quickServersGrid
                .transition(.opacity)
            }
          }
          .frame(maxWidth: .infinity)
          .frame(height: 2 * (Self.addressHeight + 8) + 1, alignment: .top)
          .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            self.quickServersWidth = width
          }
        }
        self.connectButton
      }
    }
    .frame(maxWidth: 526)
    .padding(.horizontal, 40)
    .onAppear {
      self.focusedField = .address
      self.showsAccount = !self.login.isBlank
    }
    .task {
      await self.suggestions.load(bookmarks: self.bookmarks)
    }
    .task {
      // Just after the form, so they come in after it.
      try? await Task.sleep(for: .milliseconds(120))
      self.quickServersShown = true
    }
    .onChange(of: self.address) {
      // A bookmark's saved login comes with it.
      if self.login.isBlank, let saved = self.suggestions.servers.first(where: { $0.completion == self.address && $0.login != nil }) {
        self.login = saved.login ?? ""
        self.password = saved.password ?? ""
        withAnimation(.snappy) {
          self.showsAccount = true
        }
      }
      // Typing brings the suggestions back, but a suggestion going into the address doesn't.
      if self.choosingSuggestion {
        self.choosingSuggestion = false
      }
      else {
        self.showsSuggestions = true
        self.selectedSuggestion = nil
      }
    }
    .onChange(of: self.isConnecting) {
      if self.isConnecting {
        self.showsSuggestions = false
      }
    }
    .sheet(isPresented: self.$bookmarkSheetPresented) {
      self.newBookmarkSheet
    }
  }

  /// A new bookmark for the server that's typed, if one is, with its login, whether that's typed
  /// before the server, as in user:password@, or in the login and password fields.
  private var newBookmarkSheet: some View {
    let typed = Server.parseServerAddress(self.address)
    guard !typed.host.isEmpty else {
      return ServerBookmarkSheet()
    }
    // Named for the server, if a bookmark or tracker knows its name, or else its address.
    let known = self.suggestions.servers.first { $0.address.caseInsensitiveCompare(typed.host) == .orderedSame && $0.port == typed.port }
    return ServerBookmarkSheet(
      name: known?.name ?? typed.host,
      address: typed.port == HotlinePorts.DefaultServerPort ? typed.host : "\(typed.host):\(typed.port)",
      login: typed.login ?? self.login,
      password: typed.login != nil ? typed.password ?? "" : self.password
    )
  }

  private var addressField: some View {
    HStack(spacing: 10) {
      // The globe the Servers window shows for servers.
      Image("Server")
        .resizable()
        .scaledToFit()
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
      TextField("Server name or address", text: self.$address)
        .textFieldStyle(.plain)
        // A step up from the 13 pt of the rest of the app, for the one thing the window is for.
        .font(.system(size: 15))
        .focused(self.$focusedField, equals: .address)
        .disabled(self.isConnecting)
        .onKeyPress(keys: [.upArrow, .downArrow, .return, .escape, .tab]) { press in
          self.handleKey(press)
        }
      if !self.isConnecting {
        self.bookmarksMenu
      }
    }
    .padding(.leading, 12)
    .padding(.trailing, 14)
    .frame(height: Self.addressHeight)
    .fieldBackground(in: Capsule())
    .background {
      let matches = self.matches
      SuggestionsPanel(
        isPresented: self.suggestionsVisible,
        bookmarks: matches.bookmarks,
        trackers: matches.trackers,
        selection: self.$selectedSuggestion,
        choose: { self.choose($0) },
        dismiss: { self.showsSuggestions = false }
      )
    }
  }

  /// The bookmarks and trackers' servers with what's typed in their name or address.
  private var matches: (bookmarks: [ServerSuggestion], trackers: [ServerSuggestion]) {
    self.suggestions.matching(self.typedServer.address)
  }

  /// Whether the suggestions are showing: while the address is typed in, in the front window,
  /// with something to suggest.
  private var suggestionsVisible: Bool {
    guard self.showsSuggestions, self.focusedField == .address, self.appearsActive, !self.isConnecting else {
      return false
    }
    let matches = self.matches
    return !matches.bookmarks.isEmpty || !matches.trackers.isEmpty
  }

  /// The arrow keys move through the suggestions, Return chooses one, and Escape puts them away.
  /// Tab chooses the one picked out, if there is one, and goes on to the login, opening it if it's
  /// closed.
  private func handleKey(_ press: KeyPress) -> KeyPress.Result {
    guard press.modifiers.isDisjoint(with: [.shift, .control, .option, .command]) else {
      return .ignored
    }
    let matches = self.matches
    let suggestions = matches.bookmarks + matches.trackers
    let selected = suggestions.firstIndex { $0.id == self.selectedSuggestion }
    switch press.key {
    case .downArrow:
      guard !suggestions.isEmpty else {
        return .ignored
      }
      // Down brings them back if they were put away.
      if !self.showsSuggestions {
        self.showsSuggestions = true
      }
      else {
        self.selectedSuggestion = suggestions[selected.map { min($0 + 1, suggestions.count - 1) } ?? 0].id
      }
      return .handled
    case .upArrow:
      guard self.suggestionsVisible else {
        return .ignored
      }
      // Up from the first, back to the address alone.
      self.selectedSuggestion = selected.flatMap { $0 > 0 ? suggestions[$0 - 1].id : nil }
      return .handled
    case .return:
      guard self.suggestionsVisible, let selected else {
        return .ignored
      }
      self.choose(suggestions[selected])
      return .handled
    case .escape:
      guard self.suggestionsVisible else {
        return .ignored
      }
      self.showsSuggestions = false
      return .handled
    case .tab:
      if self.suggestionsVisible, let selected {
        self.choose(suggestions[selected])
      }
      withAnimation(.snappy) {
        self.showsAccount = true
      }
      self.focusedField = .login
      return .handled
    default:
      return .ignored
    }
  }

  /// Puts a suggestion in the address, after any login typed before it, and the suggestions away.
  private func choose(_ server: ServerSuggestion) {
    self.setAddress(self.typedServer.credentials + server.completion)
    self.showsSuggestions = false
    self.selectedSuggestion = nil
  }

  /// Changes the address other than by typing, which doesn't bring up the suggestions.
  private func setAddress(_ address: String) {
    if address != self.address {
      self.choosingSuggestion = true
      self.address = address
    }
  }


  /// What's typed in the address field, split into a login and password typed before the server,
  /// as in user:password@, and the server's address.
  private var typedServer: (credentials: String, address: String) {
    guard let at = self.address.lastIndex(of: "@") else {
      return ("", self.address)
    }
    return (String(self.address[...at]), String(self.address[self.address.index(after: at)...]))
  }

  /// The bookmarked servers, to connect to one, and a new bookmark for what's typed.
  private var bookmarksMenu: some View {
    BookmarksMenu(
      bookmarks: self.bookmarks.filter { $0.type == .server },
      open: { self.open($0) },
      newBookmark: { self.bookmarkSheetPresented = true }
    )
    .fixedSize()
    // Its arrow has room after it already, so without this it would end further in than the
    // field's padding.
    .padding(.trailing, -6)
  }

  /// Connects to a bookmarked server, with its login, the way a browser goes to a bookmark.
  private func open(_ bookmark: Bookmark) {
    self.connect(to: Self.addressText(bookmark.address, port: bookmark.port), login: bookmark.login, password: bookmark.password)
  }

  /// Connects to a server, with a login if there's one for it, which shows.
  private func connect(to address: String, login: String?, password: String?) {
    self.setAddress(address)
    self.login = login ?? ""
    self.password = password ?? ""
    withAnimation(.snappy) {
      self.showsAccount = !self.login.isBlank
    }
    // Once the window has the new address.
    DispatchQueue.main.async {
      self.action?()
    }
  }

  /// A server's address as it's typed, with its port only if it isn't Hotline's usual one.
  private static func addressText(_ address: String, port: Int) -> String {
    port == HotlinePorts.DefaultServerPort ? address : "\(address):\(port)"
  }

  /// A server to connect to in a click: one logged in to lately, or a bookmarked one.
  private struct QuickServer: Identifiable {
    let id: String
    let name: String
    /// As it goes in the address field.
    let address: String
    let login: String?
    let password: String?
    let isRecent: Bool
    /// When you were last on it, for a recent one.
    let lastConnected: Date?
  }

  /// The narrowest a column of servers can be, with room for a short name and how long ago.
  private static let quickServerWidth: CGFloat = 150

  /// As many columns of servers as fit, up to three.
  private var quickServerColumns: Int {
    max(1, min(3, Int((self.quickServersWidth + 6) / (Self.quickServerWidth + 6))))
  }

  /// The servers logged in to lately, the latest first, then bookmarked ones, to fill three rows of
  /// as many columns as fit. A recent server that's bookmarked too comes with the bookmark's login.
  private var quickServers: [QuickServer] {
    let bookmarks = self.bookmarks.filter { $0.type == .server }
    var servers: [QuickServer] = []
    for recent in Prefs.shared.recentServers {
      let bookmark = bookmarks.first { $0.address.caseInsensitiveCompare(recent.address) == .orderedSame && $0.port == recent.port }
      servers.append(QuickServer(id: recent.id, name: recent.name, address: Self.addressText(recent.address, port: recent.port), login: bookmark?.login, password: bookmark?.password, isRecent: true, lastConnected: recent.lastConnected))
    }
    for bookmark in bookmarks {
      let id = "\(bookmark.address.lowercased()):\(bookmark.port)"
      guard !servers.contains(where: { $0.id == id }) else {
        continue
      }
      servers.append(QuickServer(id: id, name: bookmark.name.isBlank ? bookmark.address : bookmark.name, address: Self.addressText(bookmark.address, port: bookmark.port), login: bookmark.login, password: bookmark.password, isRecent: false, lastConnected: nil))
    }
    return Array(servers.prefix(3 * self.quickServerColumns))
  }

  /// The servers to connect to in a click, in as many columns as fit, coming in one after another
  /// as the form shows, and dimmed while it's connecting.
  private var quickServersGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: self.quickServerColumns), alignment: .leading, spacing: 4) {
      ForEach(Array(self.quickServers.enumerated()), id: \.element.id) { index, server in
        QuickServerButton(name: server.name, address: server.address, lastConnected: server.lastConnected) {
          self.connect(to: server.address, login: server.login, password: server.password)
        }
        .contextMenu {
          if server.isRecent {
            Button("Remove from Recent Servers") {
              withAnimation(.snappy) {
                Prefs.shared.recentServers.removeAll { $0.id == server.id }
              }
            }
          }
        }
        .opacity(self.quickServersShown ? 1 : 0)
        .offset(y: self.quickServersShown ? 0 : 6)
        .animation(.spring(duration: 0.5, bounce: 0.2).delay(0.04 * Double(index)), value: self.quickServersShown)
      }
    }
    .padding(.top, 2)
    .opacity(self.isConnecting ? 0.4 : 1)
    .disabled(self.isConnecting)
  }

  /// Connect, a blue circle beside the address, which turns into a plain X that stops it while it's
  /// connecting.
  private var connectButton: some View {
    Button {
      if self.isConnecting {
        self.cancel?()
      }
      else {
        self.action?()
      }
    } label: {
      Image(systemName: self.isConnecting ? "xmark" : "arrow.right")
        .font(.system(size: 15, weight: .semibold))
        .contentTransition(.symbolEffect(.replace))
        // With the 10 points around it, as tall as the address.
        .frame(width: Self.addressHeight - 20, height: Self.addressHeight - 20)
    }
    .buttonStyle(RoundButtonStyle(prominent: !self.isConnecting))
    // Return connects, unless it's to choose a suggestion, and Escape stops it.
    .keyboardShortcut(self.isConnecting ? .cancelAction : self.suggestionsVisible && self.selectedSuggestion != nil ? nil : .defaultAction)
    .disabled(!self.isConnecting && self.address.isBlank)
    .help(self.isConnecting ? "Stop Connecting" : "Connect")
    .accessibilityLabel(self.isConnecting ? "Stop Connecting" : "Connect")
  }

  private var accountToggle: some View {
    Button {
      withAnimation(.snappy) {
        self.showsAccount.toggle()
      }
      if self.showsAccount {
        self.focusedField = .login
      }
    } label: {
      HStack(spacing: 4) {
        Text("Log in with an account")
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .rotationEffect(.degrees(self.showsAccount ? 180 : 0))
      }
      .font(.callout)
      .foregroundStyle(.secondary)
      // In a capsule while the pointer's over it, to show it's a button.
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(.quaternary.opacity(self.accountToggleHovered ? 1 : 0), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.15)) {
        self.accountToggleHovered = hovering
      }
    }
    .onDisappear {
      self.accountToggleHovered = false
    }
    // The capsule's room taken back, so the space around it is as it was.
    .padding(.vertical, -4)
  }

  /// The login and password, together in one card, a row each.
  private var accountFields: some View {
    VStack(spacing: 0) {
      self.accountRow(systemImage: "person") {
        TextField("Login", text: self.$login)
          .focused(self.$focusedField, equals: .login)
      }
      // From where the fields start, as the address does above them.
      Divider()
        .padding(.leading, 38)
      self.accountRow(systemImage: "key") {
        SecureField("Password", text: self.$password)
          .focused(self.$focusedField, equals: .password)
      }
    }
    .fieldBackground(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    .disabled(self.isConnecting)
  }

  private func accountRow(systemImage: String, @ViewBuilder field: () -> some View) -> some View {
    HStack(spacing: 8) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 16)
        .accessibilityHidden(true)
      field()
        .textFieldStyle(.plain)
    }
    .padding(.horizontal, 14)
    .frame(height: Self.addressHeight)
    // Room between the row and the edge of the card, or the divider.
    .padding(.vertical, 4)
  }
}

/// A server in the connect form to connect to in a click: its globe and name, and for a recent one,
/// how long ago you were on it, in a capsule while the pointer's over it, with an arrow for going
/// there in place of the time, and its whole name and address as its help.
private struct QuickServerButton: View {
  let name: String
  let address: String
  let lastConnected: Date?
  let action: () -> Void
  @State private var hovered = false

  var body: some View {
    Button(action: self.action) {
      HStack(spacing: 6) {
        // The globe the address field has, and where it has it.
        Image("Server")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16)
          .accessibilityHidden(true)
        // The name, with all the room there is, close up to the time.
        HStack(spacing: 4) {
          Text(self.name)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
          // A bookmark without a time only makes room for the arrow while it shows.
          if self.lastConnected != nil || self.hovered {
            ZStack(alignment: .trailing) {
              if let lastConnected = self.lastConnected {
                // Kept up to date while the form's open, from the time it's redrawn, as the minute
                // it's for can be most of a minute before.
                TimelineView(.everyMinute) { _ in
                  Text(Self.age(of: lastConnected, now: .now))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                }
                .opacity(self.hovered ? 0 : 1)
              }
              Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .opacity(self.hovered ? 1 : 0)
                .accessibilityHidden(true)
            }
          }
        }
      }
      .font(.callout)
      .foregroundStyle(self.hovered ? .primary : .secondary)
      .padding(.leading, 12)
      .padding(.trailing, 8)
      .frame(height: 26)
      .background(.quaternary.opacity(self.hovered ? 1 : 0), in: Capsule())
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.15)) {
        self.hovered = hovering
      }
    }
    // The whole name, as it can be cut short, its address, and when you were last on it.
    .help([self.name, self.address, self.lastConnected.map { "Last connected \($0.formatted(date: .abbreviated, time: .shortened))" }].compactMap { $0 }.joined(separator: "\n"))
    .accessibilityLabel("Connect to \(self.name)")
  }

  /// How long ago, as short as it can be: now, 5m, 5h, 6d, 8mo, 2y.
  static func age(of date: Date, now: Date) -> String {
    let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date, to: now)
    if let years = parts.year, years > 0 {
      return "\(years)y"
    }
    if let months = parts.month, months > 0 {
      return "\(months)mo"
    }
    if let days = parts.day, days > 0 {
      return "\(days)d"
    }
    if let hours = parts.hour, hours > 0 {
      return "\(hours)h"
    }
    if let minutes = parts.minute, minutes > 0 {
      return "\(minutes)m"
    }
    return "now"
  }
}

/// The bookmarks menu, made with AppKit for the globe beside each bookmark: from macOS 27, menus
/// hide their items' images unless an item asks to show its image, which a SwiftUI menu can't.
private struct BookmarksMenu: NSViewRepresentable {
  let bookmarks: [Bookmark]
  let open: (Bookmark) -> Void
  let newBookmark: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> NSPopUpButton {
    let button = NSPopUpButton(frame: .zero, pullsDown: true)
    button.isBordered = false
    button.contentTintColor = .secondaryLabelColor
    button.toolTip = "Bookmarks"
    let menu = NSMenu()
    menu.autoenablesItems = false
    menu.delegate = context.coordinator
    // A pull-down menu shows its first item on the button rather than in the menu.
    let icon = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    icon.image = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: "Bookmarks")?
      .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
    menu.addItem(icon)
    // Filled in to start with too, since a pull-down with nothing in it won't open.
    context.coordinator.menuNeedsUpdate(menu)
    button.menu = menu
    return button
  }

  func updateNSView(_ button: NSPopUpButton, context: Context) {
    context.coordinator.parent = self
  }

  /// Fills in the menu as it opens, rather than every time what's typed changes.
  final class Coordinator: NSObject, NSMenuDelegate {
    var parent: BookmarksMenu

    init(_ parent: BookmarksMenu) {
      self.parent = parent
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
      while menu.items.count > 1 {
        menu.removeItem(at: 1)
      }
      let open = self.parent.open
      for bookmark in self.parent.bookmarks {
        let item = ChatMenuItem(bookmark.name) { open(bookmark) }
        item.subtitle = bookmark.displayAddress
        item.image = NSImage(named: "Server")
        if #available(macOS 27, *) {
          item.preferredImageVisibility = .visible
        }
        menu.addItem(item)
      }
      if !self.parent.bookmarks.isEmpty {
        menu.addItem(.separator())
      }
      menu.addItem(ChatMenuItem("New Bookmark…", handler: self.parent.newBookmark))
    }
  }
}

/// The suggestions in a window of their own just under the address field: a child of the server
/// window, so it moves with it, and can hang past the bottom of it, as a menu can. It never
/// takes the keys from the field, and a click anywhere else puts it away.
private struct SuggestionsPanel: NSViewRepresentable {
  let isPresented: Bool
  let bookmarks: [ServerSuggestion]
  let trackers: [ServerSuggestion]
  @Binding var selection: ServerSuggestion.ID?
  let choose: (ServerSuggestion) -> Void
  let dismiss: () -> Void

  /// Between the field and the list.
  private static let gap: CGFloat = 4

  func makeCoordinator() -> Coordinator {
    Coordinator()
  }

  func makeNSView(context: Context) -> AnchorView {
    let view = AnchorView()
    view.moved = { [weak coordinator = context.coordinator] in
      coordinator?.position()
    }
    return view
  }

  func updateNSView(_ view: AnchorView, context: Context) {
    let coordinator = context.coordinator
    coordinator.anchor = view
    coordinator.dismiss = self.dismiss
    guard self.isPresented, let window = view.window else {
      coordinator.hide()
      return
    }
    let field = window.convertToScreen(view.convert(view.bounds, to: nil))
    // No taller than there's room for on the screen below the field, scrolling past that.
    let screenBottom = (window.screen ?? NSScreen.main)?.visibleFrame.minY ?? 0
    let room = field.minY - Self.gap - screenBottom - 8
    coordinator.show(
      SuggestionList(
        bookmarks: self.bookmarks,
        trackers: self.trackers,
        selection: self.$selection,
        choose: self.choose,
        maxHeight: max(min(room, SuggestionList.preferredMaxHeight), 2 * SuggestionList.rowHeight)
      ),
      in: window
    )
  }

  static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
    coordinator.hide()
  }

  /// Where the field is, so the list can go under it, wherever the window lays it out.
  final class AnchorView: NSView {
    var moved: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      self.watchFrames()
      self.moved?()
    }

    /// The field moves when any view it's in does, as the window resizes or lays itself out
    /// again, so every one of them is watched, not just this one.
    private func watchFrames() {
      for observer in self.observers {
        NotificationCenter.default.removeObserver(observer)
      }
      self.observers = []
      guard self.window != nil else {
        return
      }
      var view: NSView? = self
      while let current = view {
        current.postsFrameChangedNotifications = true
        self.observers.append(NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: current, queue: .main) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.moved?()
          }
        })
        view = current.superview
      }
    }

    // Only marks the place; clicks go to the field.
    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }
  }

  @MainActor
  final class Coordinator {
    weak var anchor: NSView?
    var dismiss: (() -> Void)?

    private lazy var panel: NSPanel = {
      let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = true
      panel.isReleasedWhenClosed = false
      panel.becomesKeyOnlyIfNeeded = true
      panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
      panel.contentView = self.hostingView
      return panel
    }()
    private let hostingView = ListHostingView(rootView: AnyView(EmptyView()))
    private var isShowing = false
    private var clickMonitor: Any?

    func show(_ list: some View, in window: NSWindow) {
      self.hostingView.rootView = AnyView(list)
      self.panel.appearance = window.effectiveAppearance
      let isNew = !self.isShowing
      self.isShowing = true
      self.position()
      if isNew {
        // In quickly, as a menu comes.
        self.panel.alphaValue = 0
        window.addChildWindow(self.panel, ordered: .above)
        NSAnimationContext.runAnimationGroup { context in
          context.duration = 0.12
          self.panel.animator().alphaValue = 1
        }
        self.watchForClicksAway()
      }
    }

    func hide() {
      if let monitor = self.clickMonitor {
        NSEvent.removeMonitor(monitor)
        self.clickMonitor = nil
      }
      guard self.isShowing else {
        return
      }
      self.isShowing = false
      self.panel.parent?.removeChildWindow(self.panel)
      self.panel.orderOut(nil)
    }

    /// Just under the field, as wide as it, and as tall as the list.
    func position() {
      guard self.isShowing, let anchor = self.anchor, let window = anchor.window else {
        return
      }
      let field = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
      let height = self.hostingView.fittingSize.height
      self.panel.setFrame(NSRect(x: field.minX, y: field.minY - SuggestionsPanel.gap - height, width: field.width, height: height), display: true)
      self.panel.invalidateShadow()
    }

    /// A click anywhere but in the list or the field puts the list away, as it does a menu.
    private func watchForClicksAway() {
      self.clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
        MainActor.assumeIsolated {
          guard let self, event.window !== self.panel else {
            return
          }
          if let anchor = self.anchor, event.window === anchor.window, anchor.bounds.contains(anchor.convert(event.locationInWindow, from: nil)) {
            return
          }
          self.dismiss?()
        }
        return event
      }
    }
  }

  /// Takes the first click, rather than spending it on making the panel key, which it never is.
  final class ListHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
      true
    }
  }
}

/// The servers suggested as an address is typed, in a list under the field like the one under a
/// browser's address bar, and as wide: bookmarks, then what the trackers list.
private struct SuggestionList: View {
  let bookmarks: [ServerSuggestion]
  let trackers: [ServerSuggestion]
  @Binding var selection: ServerSuggestion.ID?
  let choose: (ServerSuggestion) -> Void
  /// How tall it can be, past which it scrolls.
  var maxHeight: CGFloat = Self.preferredMaxHeight

  static let rowHeight: CGFloat = 40
  /// Half a row past a whole number of them, so a list that scrolls looks it.
  static let preferredMaxHeight: CGFloat = 7.5 * rowHeight
  private static let padding: CGFloat = 6
  private static let cornerRadius: CGFloat = 16

  var body: some View {
    let showsDivider = !self.bookmarks.isEmpty && !self.trackers.isEmpty
    let height = CGFloat(self.bookmarks.count + self.trackers.count) * Self.rowHeight + (showsDivider ? 9 : 0) + Self.padding * 2
    let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
    ScrollViewReader { proxy in
      ScrollView {
        VStack(spacing: 0) {
          ForEach(self.bookmarks) { server in
            self.row(server)
          }
          if showsDivider {
            Divider()
              .padding(.horizontal, 10)
              .padding(.vertical, 4)
          }
          ForEach(self.trackers) { server in
            self.row(server)
          }
        }
        .padding(Self.padding)
      }
      .scrollDisabled(height <= self.maxHeight)
      .scrollIndicators(.automatic)
      // The one picked out with the keys kept in view.
      .onChange(of: self.selection) {
        if let selection = self.selection {
          proxy.scrollTo(selection)
        }
      }
    }
    .frame(height: min(height, self.maxHeight))
    .suggestionsBackground(in: shape)
  }

  private func row(_ server: ServerSuggestion) -> some View {
    Button {
      self.choose(server)
    } label: {
      SuggestionRow(server: server, isSelected: server.id == self.selection)
    }
    .buttonStyle(.plain)
    // Picked out by the pointer too, as in a menu.
    .onHover { inside in
      if inside {
        self.selection = server.id
      }
      else if self.selection == server.id {
        self.selection = nil
      }
    }
    .id(server.id)
  }
}

/// A suggested server: the globe from the address field, its name with its address under it, and
/// a bookmark at the end if it's bookmarked, all in white on the accent while it's picked out.
private struct SuggestionRow: View {
  let server: ServerSuggestion
  let isSelected: Bool

  var body: some View {
    let secondary = self.isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary)
    HStack(spacing: 8) {
      Image("Server")
        .accessibilityHidden(true)
      VStack(alignment: .leading, spacing: 1) {
        Text(self.server.name)
          .font(.system(size: 13))
          .lineLimit(1)
        Text(self.server.completion)
          .font(.system(size: 11))
          .foregroundStyle(secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      // Its room first, before the gap to the bookmark.
      .layoutPriority(1)
      Spacer(minLength: 8)
      if self.server.source == .bookmark {
        Image(systemName: "bookmark.fill")
          .font(.system(size: 12))
          .foregroundStyle(secondary)
          .accessibilityLabel("Bookmark")
      }
    }
    .foregroundStyle(self.isSelected ? Color.white : Color.primary)
    .padding(.horizontal, 10)
    .frame(height: SuggestionList.rowHeight)
    .background(self.isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    .contentShape(Rectangle())
  }
}

/// A round button, 10 points bigger than its label all around: blue glass when it's prominent and
/// plain glass when not, or before macOS 26, a blue or gray circle. Unlike glassProminent and
/// glass, which are two different buttons, it's the same button either way, so its symbol can turn
/// from one to the other.
private struct RoundButtonStyle: ButtonStyle {
  let prominent: Bool
  @Environment(\.isEnabled) private var isEnabled

  @ViewBuilder
  func makeBody(configuration: Configuration) -> some View {
    // Plain when it can't be clicked, as glassProminent is.
    let tinted = self.prominent && self.isEnabled
    let label = configuration.label
      .foregroundStyle(tinted ? AnyShapeStyle(.white) : self.isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
      .padding(10)
      .contentShape(Circle())
    if #available(macOS 26, *) {
      label.glassEffect(tinted ? .regular.tint(.accentColor).interactive() : .regular.interactive(), in: Circle())
    }
    else {
      label.background(tinted ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary), in: Circle())
        .opacity(configuration.isPressed ? 0.8 : 1)
    }
  }
}

/// Glass shapes that sit together, so they're drawn as one, from macOS 26.
private struct GlassGroup<Content: View>: View {
  let spacing: CGFloat
  @ViewBuilder let content: Content

  var body: some View {
    if #available(macOS 26, *) {
      GlassEffectContainer(spacing: self.spacing) {
        self.content
      }
    }
    else {
      self.content
    }
  }
}

private extension View {
  /// What's behind a field: Liquid Glass, or before macOS 26, a field's own fill and edge.
  @ViewBuilder
  func fieldBackground(in shape: some Shape) -> some View {
    if #available(macOS 26, *) {
      self.glassEffect(.regular, in: shape)
        // Fading in where it is, the way it fades out, rather than growing out of the glass beside
        // it.
        .glassEffectTransition(.materialize)
    }
    else {
      self.background(Color(nsColor: .controlBackgroundColor), in: shape)
        .overlay(shape.stroke(Color(nsColor: .separatorColor)))
    }
  }

  /// What's behind the suggestions: Liquid Glass, or before macOS 26, a window's background and
  /// edge. The window they're in casts their shadow.
  @ViewBuilder
  func suggestionsBackground(in shape: some Shape) -> some View {
    if #available(macOS 26, *) {
      self.glassEffect(.regular, in: shape)
    }
    else {
      self.background(Color(nsColor: .windowBackgroundColor), in: shape)
        .overlay(shape.stroke(Color(nsColor: .separatorColor)))
    }
  }
}
