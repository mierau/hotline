import SwiftUI
import Kingfisher

struct HotlinePanelView: View {
  @Environment(\.openWindow) var openWindow
  @Environment(\.colorScheme) var colorScheme
  @Environment(\.appState) private var appState
  @Namespace private var selectionNamespace
  @State private var hoveredButton: PanelButton? = nil

  private var activeServerState: ServerState? {
    self.appState.activeServerState
  }

  private var activeHotline: HotlineState? {
    self.appState.activeHotline
  }

  private var bannerImage: Image {
    self.activeHotline?.bannerImage ?? Image("Default Banner")
  }

  private var backgroundColor: Color {
    Color(nsColor: self.activeHotline?.bannerColors?.backgroundColor ?? NSColor.windowBackgroundColor)
  }
  
  private var bannerFileURL: URL? {
    self.activeHotline?.bannerFileURL
  }
  
  private var bannerIsAnimated: Bool {
    self.activeHotline?.bannerImageFormat == .gif
  }

  var body: some View {
    VStack(spacing: 0) {
      
      self.bannerView
        .id("banner image view")
        .animation(.default, value: self.bannerFileURL)
        .background {
          Color.black
        }
        // Keep the banner above the button row so nothing from the glass bars draws over it.
        .zIndex(1)

      self.buttonRow
      
//      GroupBox {
//        HStack(spacing: 0) {
//          Text("Not Connected")
//            .font(.system(size: 10.0))
//            .lineLimit(1)
//            .truncationMode(.tail)
//            .opacity(0.5)
//            .padding(.vertical, 0.0)
//            .padding(.horizontal, 4.0)
//          
//          Spacer()
//        }
//      }
//      .padding([.leading, .bottom, .trailing], 4.0)
    }
    // Glass swallows clicks, so dragging by the window background stops working over the
    // button bars. Drag explicitly instead; buttons still get their own clicks. The panel never
    // becomes key, so let the gesture handle the clicks that would otherwise just activate it.
    .gesture(WindowDragGesture())
    .allowsWindowActivationEvents(true)
//    .frame(width: 468)
//    .background(colorScheme == .dark ? .black : .white)
//    .background(
//      VisualEffectView(material: .headerView, blendingMode: .behindWindow)
//        .cornerRadius(10.0)
//    )
  }
  
  // MARK: Button Row

  @ViewBuilder
  private var buttonRow: some View {
    if #available(macOS 26.0, *) {
      self.glassButtonRow
    }
    else {
      self.classicButtonRow
    }
  }

  private var classicButtonRow: some View {
    // Touching 32 pt button cells with this padding put the icons where they've always been,
    // 12 pt apart in a 44 pt row.
    HStack(spacing: 0) {
      self.sectionButtons
      Spacer()
      self.utilityButtons
    }
    .padding(.vertical, 8)
    .padding(.horizontal, 6)
    .background(self.backgroundColor)
    .foregroundStyle(.primary)
    .animation(.default, value: self.backgroundColor)
    .animation(.snappy(duration: 0.25), value: self.selectedButton)
  }

  /// Section buttons in a glass bar on the left, utilities in a smaller one on the right.
  @available(macOS 26.0, *)
  private var glassButtonRow: some View {
    GlassEffectContainer(spacing: 12) {
      HStack(spacing: 0) {
        // 4 pt around the 28 pt button cells makes 36 pt bars, the height of system toolbar glass,
        // and keeps the selection capsule 4 pt from the bar's edge on every side.
        // Cells touch, so the selection capsule's possible positions sit end to end.
        HStack(spacing: 0) {
          self.sectionButtons
        }
        .padding(4)
        .glassEffect(.clear.interactive(), in: .capsule)

        Spacer(minLength: 0)

        HStack(spacing: 0) {
          self.utilityButtons
        }
        .padding(4)
        .glassEffect(.clear.interactive(), in: .capsule)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(self.barBackground)
    .animation(.default, value: self.backgroundColor)
    .animation(.snappy(duration: 0.25), value: self.selectedButton)
  }

  /// The banner's background color at the top, lightening toward the bottom of the window.
  /// Without a banner, just the plain window background.
  ///
  /// White blended with soft light lightens the color while keeping its hue and saturation,
  /// rather than washing it out the way a plain white overlay would.
  @ViewBuilder
  private var barBackground: some View {
    if self.activeHotline?.bannerColors != nil {
      self.backgroundColor
        .overlay {
          LinearGradient(colors: [.white.opacity(0), .white.opacity(0.5)], startPoint: .top, endPoint: .bottom)
            .blendMode(.softLight)
        }
        .compositingGroup()
    }
    else {
      self.backgroundColor
    }
  }

  /// The most colorful of the banner's other colors, at full strength so it shows through the glass.
  ///
  /// ColorArt's primary, secondary, and detail colors are meant for text and often fall back to plain
  /// white or black, so those banners get a tint of their background color instead. Plain glass
  /// without a banner.
  private var glassTint: Color? {
    guard let colors = self.activeHotline?.bannerColors else {
      return nil
    }

    let saturation = { (color: NSColor) in color.usingColorSpace(.genericRGB)?.saturationComponent ?? 0 }
    let accent = [colors.primaryColor, colors.secondaryColor, colors.detailColor].max { saturation($0) < saturation($1) }
    let tint = accent.flatMap { saturation($0) >= 0.2 ? $0 : nil } ?? colors.backgroundColor

    return Color(nsColor: tint)
  }

  // MARK: Buttons

  @ViewBuilder
  private var sectionButtons: some View {
    self.panelButton(.servers, "Section Servers", help: "Hotline Servers") {
      if NSEvent.modifierFlags.contains(.option) {
        openWindow(id: "server")
      }
      else {
        openWindow(id: "servers")
      }
    }

    self.panelButton(.chat, "Section Chat", help: "Public Chat", disabled: self.activeServerState == nil) {
      self.showSection(.chat)
    }

    self.panelButton(.board, "Section Board", help: "Message Board", disabled: self.activeServerState == nil) {
      self.showSection(.board)
    }

    self.panelButton(.news, "Section News", help: "News", disabled: self.activeServerState == nil || (self.activeHotline?.serverVersion ?? 0) < 151) {
      self.showSection(.news)
    }

    self.panelButton(.files, "Section Files", help: "Files", disabled: self.activeServerState == nil) {
      self.showSection(.files)
    }
  }

  @ViewBuilder
  private var utilityButtons: some View {
    if self.activeHotline?.access?.contains(.canOpenUsers) == true {
      self.panelButton(.users, "Section Users", help: "Manage Accounts", disabled: self.activeServerState == nil) {
//        self.activeServerState?.selection = .accounts
        self.activeServerState?.accountsShown = true
        self.activeServerState?.window?.makeKeyAndOrderFront(nil)
      }
    }

    self.panelButton(.transfers, "Section Transfers", help: "File Transfers") {
      self.openWindow(id: "transfers")
    }

    self.panelButton(.settings, "Section Settings", help: "Settings") {
      self.openWindow(id: "settings")
    }
  }

  /// Show a section of the current server, bringing its window forward if another window is in front.
  private func showSection(_ section: ServerNavigationType) {
    self.activeServerState?.selection = section
    self.activeServerState?.window?.makeKeyAndOrderFront(nil)
  }

  /// A cell around the 20 pt icon. The whole cell is clickable, and the selection capsule fills it.
  private func panelButton(_ button: PanelButton, _ imageName: String, help: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(imageName)
        .resizable()
        .scaledToFit()
        .frame(width: 20, height: 20)
        .frame(width: self.buttonCellWidth, height: 28)
        .contentShape(.capsule)
    }
    .buttonStyle(.plain)
    .background {
      if self.selectedButton == button {
        Capsule()
          .fill(.quaternary)
          // One highlight per bar: it slides between buttons in a bar, and fades between bars.
          .matchedGeometryEffect(id: button.bar, in: self.selectionNamespace)
          .transition(.opacity.combined(with: .scale(scale: 0.8)))
      }
      else if self.hoveredButton == button && !disabled {
        // A lighter version of the selection capsule, so the selected button still stands out.
        Capsule()
          .fill(.quaternary.opacity(0.6))
          .transition(.opacity)
      }
    }
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        if hovering {
          self.hoveredButton = button
        }
        else if self.hoveredButton == button {
          self.hoveredButton = nil
        }
      }
    }
    .disabled(disabled)
    .help(help)
  }

  /// Roomier cells in the macOS 26 glass bars. The older row keeps 32 pt cells so its icons stay
  /// where they've always been.
  private var buttonCellWidth: CGFloat {
    if #available(macOS 26.0, *) {
      return 40
    }
    return 32
  }

  // MARK: Selection

  private enum PanelButton: Hashable {
    case servers, chat, board, news, files
    case users, transfers, settings

    enum Bar {
      case sections
      case utilities
    }

    var bar: Bar {
      switch self {
      case .servers, .chat, .board, .news, .files: .sections
      case .users, .transfers, .settings: .utilities
      }
    }
  }

  /// The button for what's in front: the focused window's, or the section a focused server window is showing.
  private var selectedButton: PanelButton? {
    switch self.appState.focusedWindow {
    case .servers: .servers
    case .transfers: .transfers
    case .settings: .settings
    case .server:
      switch self.activeServerState?.selection {
      case .chat: .chat
      case .board: .board
      case .news: .news
      case .files: .files
      default: nil
      }
    case nil: nil
    }
  }

  // MARK: Banner

  private var bannerView: some View {
    ZStack {
      if self.bannerIsAnimated {
        KFAnimatedImage
          .url(self.bannerFileURL)
          .placeholder {
            Image("Default Banner")
          }
          .cacheMemoryOnly()
          .cacheOriginalImage()
          .scaledToFill()
          .frame(width: 468, height: 60)
          .frame(minWidth: 468, maxWidth: 468, minHeight: 60, maxHeight: 60)
          .clipped()
          .transition(.opacity)
          .id("animated banner \(self.bannerFileURL?.absoluteString ?? "")")
      }
      else {
        KFImage
          .url(self.bannerFileURL)
          .resizable()
          .interpolation(.high)
          .placeholder {
            Image("Default Banner")
          }
          .cacheMemoryOnly()
          .cacheOriginalImage()
          .scaledToFill()
          .frame(width: 468, height: 60)
          .frame(minWidth: 468, maxWidth: 468, minHeight: 60, maxHeight: 60)
          .clipped()
          .transition(.opacity)
          .id("static banner \(self.bannerFileURL?.absoluteString ?? "")")
      }
    }
    .allowsHitTesting(false)
    .animation(.default, value: self.bannerIsAnimated)
    .animation(.default, value: self.bannerFileURL)
  }
}

#Preview {
  HotlinePanelView()
    .environment(HotlineState())
}
