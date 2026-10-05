import SwiftUI

/// A server window's colors, from its banner's, when server themed colors are on.
///
/// The sidebar is the banner's color, as the banner has it, and in dark mode, a dark version of it.
/// The rest keeps to the lightness of the window's usual colors, light or dark, and takes only the
/// banner's hue and some of its color, so text and controls read on it as well as on the usual
/// colors. Lightness and color here are as they look, in Oklab, where a yellow and a blue of the
/// same lightness look as light as each other, which they don't at the same HSB brightness.
struct ServerTheme: Equatable {
  /// The sidebar's color.
  let sidebar: NSColor
  /// The color that comes into the sidebar toward its bottom corner: the banner's accent, as it is,
  /// or in dark mode, brighter.
  let sidebarGlow: NSColor?
  /// Admins' names in the sidebar: the accent, as the unread dots are, or without one, Hotline's red,
  /// as light or dark as it has to be to read on it.
  let sidebarAdmin: NSColor
  /// The accent, as light or dark as it has to be to stand out on the sidebar, for what's marked
  /// there, like unread dots and transfers' progress.
  let sidebarAccent: NSColor?
  /// Behind chat, news and files.
  let content: NSColor
  /// Behind the board's posts and messages, and news's topics, a step deeper than the content.
  let page: NSColor
  /// The board's posts and messages, raised from the page.
  let card: NSColor
  /// The top of a post, where it says who posted it, a step from the card, with more of the color.
  let cardHeader: NSColor
  /// The window's tint, for controls and what has focus, as light or dark as the system's accent
  /// colors are, to show as well on the content.
  let accent: NSColor?
  /// Admins' names in chat and messages, and when they come and go: the accent, as in the sidebar,
  /// or without one, Hotline's red, as light or dark as it has to be to read on the content.
  let admin: NSColor
  /// Selected rows, in the sidebar and lists, about as dark as the system's selection, for white text
  /// on it.
  let selection: NSColor?
  /// Selected text, as light as the system's, or in dark mode, as dark.
  let textSelection: NSColor?
  /// What matters less in lists and chat, like dates, counts, disclosure arrows, and people coming
  /// and going: as light or dark on the content as the system's secondary text is, in the banner's
  /// hue.
  let secondaryText: NSColor
  /// What matters least, like the lines between days in chat: as light or dark on the content as
  /// the system's tertiary text is, in the banner's hue.
  let tertiaryText: NSColor

  init(_ colors: ColorArt, dark: Bool) {
    let banner = OKLCH(colors.backgroundColor)
    // How much color the surfaces take, from none for a gray banner, to all they take for a vivid
    // one.
    let intensity = min(banner.chroma / 0.12, 1)
    func surface(_ lightness: Double, _ chroma: Double) -> NSColor {
      OKLCH(lightness: lightness, chroma: chroma * intensity, hue: banner.hue).color
    }
    let contentLightness = dark ? 0.245 : 0.979
    self.content = surface(contentLightness, dark ? 0.024 : 0.022)
    self.page = dark ? surface(0.215, 0.024) : surface(0.955, 0.026)
    self.card = dark ? surface(0.285, 0.022) : surface(0.996, 0.006)
    self.cardHeader = dark ? surface(0.305, 0.026) : surface(0.975, 0.022)
    self.secondaryText = dark ? surface(0.685, 0.035) : surface(0.58, 0.045)
    self.tertiaryText = dark ? surface(0.46, 0.03) : surface(0.78, 0.035)

    // In dark mode, no lighter than dark mode's colors. In either, not so near the content's
    // lightness that the two run together, and darker if it is, as most sidebars are.
    var sidebarLightness = dark ? min(banner.lightness, 0.32) : banner.lightness
    if abs(sidebarLightness - contentLightness) < 0.045 {
      sidebarLightness = contentLightness - 0.045
    }
    self.sidebar = sidebarLightness == banner.lightness
      ? colors.backgroundColor
      : OKLCH(lightness: sidebarLightness, chroma: banner.chroma * sidebarLightness / max(banner.lightness, 0.01), hue: banner.hue).color

    // A banner without a colorful color for text takes its accent from its background's.
    let accent = colors.accentColor ?? colors.backgroundColor.contrastingShade
    self.sidebarGlow = dark ? accent?.withBrightness(atLeast: 0.8) : accent
    let hue = accent.map { OKLCH($0) }
    self.accent = hue.map {
      let range = dark ? 0.62...0.75 : 0.45...0.65
      return OKLCH(lightness: min(max($0.lightness, range.lowerBound), range.upperBound), chroma: max($0.chroma, 0.12), hue: $0.hue).color
    }
    // Near the system's lightness, but nearer the accent's own, so an orange is still orange, not
    // brown, as it would be as dark as the system's blue, and far enough from the sidebar's to show
    // on it, lighter or darker.
    self.selection = hue.map {
      let range = dark ? 0.45...0.55 : 0.5...0.6
      var selection = min(max($0.lightness, range.lowerBound), range.upperBound)
      if abs(selection - sidebarLightness) < 0.12 {
        selection = sidebarLightness < selection ? sidebarLightness + 0.12 : sidebarLightness - 0.12
      }
      return OKLCH(lightness: selection, chroma: min(max($0.chroma, 0.12), 0.2), hue: $0.hue).color
    }
    // The system's, in the accent's hue.
    self.textSelection = hue.map { OKLCH(lightness: dark ? 0.49 : 0.867, chroma: dark ? 0.077 : 0.068, hue: $0.hue).color }
    self.sidebarAdmin = Self.admin(hue, on: self.sidebar)
    self.admin = Self.admin(hue, on: self.content)
    // As much contrast as marks need, a little less than text.
    let sidebar = self.sidebar
    self.sidebarAccent = hue.map { Self.standingOut($0, on: sidebar, enough: 3) }
  }

  /// Admins' names: `color`, or without one, Hotline's red, made to read on `background` as well as
  /// text should, or as well as the sidebar's own white or black text does, if that's less.
  private static func admin(_ color: OKLCH?, on background: NSColor) -> NSColor {
    let color = color ?? OKLCH(NSColor(named: "Hotline Red") ?? .systemRed)
    let enough = min(4.5, contrastRatio(background.luminance, background.isDarkColor ? 1 : 0))
    return standingOut(color, on: background, enough: enough)
  }

  /// `color`, made as little lighter or darker as it takes to have `enough` contrast with
  /// `background`, or if it can't, as near as it gets.
  private static func standingOut(_ color: OKLCH, on background: NSColor, enough: Double) -> NSColor {
    let backgroundLuminance = background.luminance
    func contrast(_ lightness: Double) -> Double {
      contrastRatio(OKLCH(lightness: lightness, chroma: color.chroma, hue: color.hue).color.luminance, backgroundLuminance)
    }
    // Nearest the color's own lightness first, lighter and darker by turns.
    let lightnesses = stride(from: 0.0, through: 0.6, by: 0.01)
      .flatMap { [color.lightness - $0, color.lightness + $0] }
      .filter { (0.35...0.9).contains($0) }
    let lightness = lightnesses.first { contrast($0) >= enough } ?? lightnesses.max { contrast($0) < contrast($1) } ?? color.lightness
    return OKLCH(lightness: lightness, chroma: color.chroma, hue: color.hue).color
  }
}

extension EnvironmentValues {
  /// The theme of the server window a view's in, or nil for the window's usual colors.
  @Entry var serverTheme: ServerTheme? = nil
  /// The color of admins' names in a server's theme, which its sidebar has its own of.
  @Entry var serverAdminColor: Color? = nil
  /// The color of unread dots, when a server's themed sidebar has one that stands out on it.
  @Entry fileprivate var serverUnreadColor: Color? = nil
  /// The selection of the server-themed list a row's in, and how it's shown.
  @Entry fileprivate var serverListSelection: ServerListSelection? = nil
  /// The color of what matters less in a server-themed list's rows, in the theme, or on a selected
  /// row, the selection's.
  @Entry fileprivate var serverSecondaryColor: Color? = nil
}

/// A server-themed list's selection, and the color and corners its selected rows have in the theme.
private struct ServerListSelection {
  var selected: AnyHashable?
  var color: NSColor?
  var cornerRadius: CGFloat
}

/// Admins' names: Hotline's red, or in a server's theme, its color for them.
struct ServerAdminStyle: ShapeStyle {
  func resolve(in environment: EnvironmentValues) -> Color {
    environment.serverAdminColor ?? .hotlineRed
  }
}

extension ShapeStyle where Self == ServerAdminStyle {
  static var serverAdmin: ServerAdminStyle {
    ServerAdminStyle()
  }
}

/// What matters less, like dates and counts: the server's theme's color for it, as chat has it, or
/// the system's secondary without one. In a server-themed list, it's the list's secondary style,
/// taken where each row shows it, so a selected row has the text's color part way to the
/// selection's instead.
struct ServerSecondaryStyle: ShapeStyle {
  func resolve(in environment: EnvironmentValues) -> Color {
    environment.serverSecondaryColor ?? environment.serverTheme.map { Color(nsColor: $0.secondaryText) } ?? .secondary
  }
}

extension ShapeStyle where Self == ServerSecondaryStyle {
  static var serverSecondary: ServerSecondaryStyle {
    ServerSecondaryStyle()
  }
}

/// Disclosure arrows in a server list's rows: the theme's color for what matters less, as the
/// rows' dates and counts have, or without one, the primary color at half, as they've always been.
struct ServerDisclosureStyle: ShapeStyle {
  func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
    environment.serverSecondaryColor.map { AnyShapeStyle($0) } ?? AnyShapeStyle(.primary.opacity(0.5))
  }
}

extension ShapeStyle where Self == ServerDisclosureStyle {
  static var serverDisclosure: ServerDisclosureStyle {
    ServerDisclosureStyle()
  }
}

/// What a view's background is for in a server window, which gives its color in the server's theme,
/// or without one, the color it's always had.
enum ServerSurface {
  /// Behind chat, news and files.
  case content
  /// Behind the board's posts and messages.
  case page
  /// Behind a list to pick from, above what's picked, like news's topics above the article, and the
  /// toolbar over them. In the server's theme, it's a step deeper than the content, to set it apart,
  /// and without one, it's clear, as the list has its own.
  case browser
  /// A post on the board.
  case post
  /// The top of a post on the board, with its signature, and who posted it and when.
  case postHeader
  /// A message.
  case message
}

extension View {
  /// The server window's theme, from its banner's colors, or nil for its usual colors, for the views
  /// in it to take theirs from. When it changes, the window fades from its old colors to its new.
  func serverTheme(_ colors: ColorArt?, window: NSWindow?) -> some View {
    self.modifier(ServerThemeModifier(colors: colors, window: window))
  }

  /// A background in the server's theme for what the view's for, or the usual one without one.
  func serverBackground(_ surface: ServerSurface) -> some View {
    self.modifier(ServerBackground(surface: surface))
  }

  /// A list on the server's theme, without its own background or the system's white and gray rows,
  /// and with its rows showing `selection`, the list's selection, in the theme's color, or as it is
  /// without one.
  func serverThemedList<Selection: Hashable>(selection: Selection?) -> some View {
    self.modifier(ServerThemedList(selection: selection.map(AnyHashable.init)))
  }

  /// A sidebar painted in the server's theme in place of its own background, with light text on a
  /// dark color and dark text on a light one, and its rows showing `selection`, its selection, in
  /// the theme's color, or as it is without one.
  func serverThemedSidebar<Selection: Hashable>(selection: Selection?) -> some View {
    self.modifier(ServerThemedSidebar(selection: selection.map(AnyHashable.init)))
  }

  /// A horizontal divider drawn as the server's theme draws lines, a pixel of its tertiary color, as
  /// chat's lines between days are, or as it is without one.
  func serverThemedDivider() -> some View {
    self.modifier(ServerThemedDivider())
  }

  /// A dot on a sidebar row for something unread, at `opacity`, as it is, or in a server's theme, in
  /// its color for these instead, to stand out on its sidebar.
  func serverUnreadDot(opacity: Double = 1) -> some View {
    self.modifier(ServerUnreadDot(opacity: opacity))
  }

  /// A row of a server-themed list or sidebar, for `item`, as it's tagged, without a line under it,
  /// which shows itself selected in the theme's color in place of the system's, when it has one.
  func serverThemedRow<Item: Hashable>(for item: Item) -> some View {
    self.modifier(ServerThemedRow(item: AnyHashable(item)))
  }
}

private struct ServerThemeModifier: ViewModifier {
  @Environment(\.colorScheme) private var colorScheme
  /// The colors the window shows, which change after it's set to fade.
  @State private var shown: ColorArt?
  let colors: ColorArt?
  let window: NSWindow?

  init(colors: ColorArt?, window: NSWindow?) {
    self.colors = colors
    self.window = window
    self._shown = State(initialValue: colors)
  }

  func body(content: Content) -> some View {
    let theme = self.shown.map { ServerTheme($0, dark: self.colorScheme == .dark) }
    content
      .environment(\.serverTheme, theme)
      .environment(\.serverAdminColor, theme.map { Color(nsColor: $0.admin) })
      .tint(theme?.accent.map { Color(nsColor: $0) })
      .onChange(of: self.colors) { _, colors in
        // Everything at once, text and all, as the window does going between light and dark, and
        // not each color on its own, which would show light text on a light background part way.
        // On the window's frame, so the toolbar fades with the rest.
        let fade = CATransition()
        fade.duration = 0.6
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        (self.window?.contentView?.superview ?? self.window?.contentView)?.layer?.add(fade, forKey: "server theme")
        // The colors move too, for what shows them as they are, not as they fade, like the edges
        // under the toolbar, to keep up.
        withAnimation(.easeInOut(duration: 0.6)) {
          self.shown = colors
        }
      }
  }
}

private struct ServerBackground: ViewModifier {
  @Environment(\.serverTheme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  let surface: ServerSurface

  func body(content: Content) -> some View {
    content.background(self.style, ignoresSafeAreaEdges: .all)
  }

  private var style: AnyShapeStyle {
    if let theme = self.theme {
      switch self.surface {
      case .content:
        return AnyShapeStyle(Color(nsColor: theme.content))
      case .page, .browser:
        return AnyShapeStyle(Color(nsColor: theme.page))
      case .post, .message:
        return AnyShapeStyle(Color(nsColor: theme.card))
      case .postHeader:
        return AnyShapeStyle(Color(nsColor: theme.cardHeader))
      }
    }
    switch self.surface {
    case .content:
      if #available(macOS 26.0, *) {
        return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
      }
      return AnyShapeStyle(Color(nsColor: .textBackgroundColor))
    case .page:
      return AnyShapeStyle(Color(nsColor: .underPageBackgroundColor).opacity(self.colorScheme == .light ? 0.25 : 1))
    case .browser:
      return AnyShapeStyle(Color.clear)
    case .post:
      return AnyShapeStyle(Color(nsColor: .textBackgroundColor))
    case .postHeader:
      return AnyShapeStyle(.quinary.opacity(self.colorScheme == .light ? 0.7 : 0.3))
    case .message:
      return self.colorScheme == .light ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.thickMaterial)
    }
  }
}

private struct ServerThemedList: ViewModifier {
  @Environment(\.serverTheme) private var theme
  let selection: AnyHashable?

  func body(content: Content) -> some View {
    content
      .scrollContentBackground(self.theme == nil ? .automatic : .hidden)
      .alternatingRowBackgrounds(self.theme == nil ? .enabled : .disabled)
      // What matters less in the rows, in the theme's hue, or as it is without one.
      .foregroundStyle(.primary, self.theme == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(ServerSecondaryStyle()))
      .environment(\.serverSecondaryColor, self.theme.map { Color(nsColor: $0.secondaryText) })
      // Where the system has its selection, inset as much, and as round.
      .environment(\.serverListSelection, ServerListSelection(selected: self.selection, color: self.theme?.selection, cornerRadius: 6))
  }
}

// MARK: - Sidebar

private struct ServerThemedSidebar: ViewModifier {
  @Environment(\.serverTheme) private var theme
  @Environment(\.colorScheme) private var colorScheme
  let selection: AnyHashable?

  func body(content: Content) -> some View {
    content
      .environment(\.serverListSelection, ServerListSelection(selected: self.selection, color: self.theme?.selection, cornerRadius: 8))
      .environment(\.serverAdminColor, self.theme.map { Color(nsColor: $0.sidebarAdmin) })
      .environment(\.serverUnreadColor, self.theme?.sidebarAccent.map { Color(nsColor: $0) })
      .scrollContentBackground(self.theme == nil ? .automatic : .hidden)
      .background {
        if let theme = self.theme {
          ServerThemedBackground(color: theme.sidebar, accent: theme.sidebarGlow)
            .ignoresSafeArea()
            .transition(.opacity)
        }
      }
      .environment(\.colorScheme, self.theme.map { $0.sidebar.isDarkColor ? .dark : .light } ?? self.colorScheme)
  }
}

/// A sidebar's color, with its accent color coming in toward the bottom-trailing corner, under a
/// touch of the panel's light from the top-leading one: white, blended with soft light, which
/// lightens the color without washing it out.
private struct ServerThemedBackground: View {
  let color: NSColor
  let accent: NSColor?

  var body: some View {
    Group {
      if self.accent != nil {
        MeshGradient(width: 3, height: 3, points: [
          [0, 0], [0.5, 0], [1, 0],
          [0, 0.5], [0.5, 0.5], [1, 0.5],
          [0, 1], [0.5, 1], [1, 1],
        ], colors: [
          self.mixed(0), self.mixed(0), self.mixed(0),
          self.mixed(0), self.mixed(0), self.mixed(0.12),
          self.mixed(0.1), self.mixed(0.22), self.mixed(0.38),
        ])
      }
      else {
        Color(nsColor: self.color)
      }
    }
    .overlay {
      LinearGradient(colors: [.white.opacity(0.2), .white.opacity(0)], startPoint: .topLeading, endPoint: .bottomTrailing)
        .blendMode(.softLight)
    }
    .compositingGroup()
  }

  /// The color, with as much of the accent mixed in.
  private func mixed(_ fraction: CGFloat) -> Color {
    guard fraction > 0, let accent = self.accent, let mixed = self.color.blended(withFraction: fraction, of: accent) else {
      return Color(nsColor: self.color)
    }
    return Color(nsColor: mixed)
  }
}

/// A row of a server-themed list, selected: a capsule in the theme's selection color, in the window
/// in front with text in white or black, whichever shows on it, admins' names too, or in other
/// windows fainter, with the text as it is, as the system's selection does.
private struct ServerThemedRow: ViewModifier {
  @Environment(\.serverListSelection) private var selection
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  @Environment(\.serverAdminColor) private var adminColor
  @Environment(\.serverSecondaryColor) private var secondaryColor
  @Environment(\.serverUnreadColor) private var unreadColor
  let item: AnyHashable

  func body(content: Content) -> some View {
    // The same views themed or not, so the table's highlight is switched by the same view each time.
    let selectionColor = self.selection?.color
    let color = self.selection?.selected == self.item ? selectionColor : nil
    let emphasized = self.controlActiveState == .key
    let textOnColor = emphasized ? color.map { $0.isDarkColor ? ColorScheme.dark : .light } : nil
    // What matters less, on the selection, the text's color, part way to the selection's.
    let secondaryOnColor = textOnColor.map { $0 == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.6) }
    content
      .environment(\.colorScheme, textOnColor ?? self.colorScheme)
      .environment(\.serverAdminColor, textOnColor.map { $0 == .dark ? .white : .black } ?? self.adminColor)
      .environment(\.serverSecondaryColor, secondaryOnColor ?? self.secondaryColor)
      // On the selection, the usual dot, in the text's color.
      .environment(\.serverUnreadColor, textOnColor == nil ? self.unreadColor : nil)
      .listRowBackground(color.map { SelectionCapsule(color: $0, emphasized: emphasized, cornerRadius: self.selection?.cornerRadius ?? 8) })
      .listRowSeparator(.hidden)
      .background { TableHighlight(isShown: selectionColor == nil) }
  }
}

private struct ServerThemedDivider: ViewModifier {
  @Environment(\.serverTheme) private var theme
  @Environment(\.displayScale) private var displayScale

  func body(content: Content) -> some View {
    content
      .opacity(self.theme == nil ? 1 : 0)
      .overlay(alignment: .top) {
        if let theme = self.theme {
          Color(nsColor: theme.tertiaryText)
            .frame(height: 1 / self.displayScale)
        }
      }
  }
}

/// An unread dot, in a server's theme, its color drawn over the usual dot, which isn't shown, so
/// without one, the usual dot is just as it is, in the sidebar's own colors.
private struct ServerUnreadDot: ViewModifier {
  @Environment(\.serverUnreadColor) private var color
  let opacity: Double

  func body(content: Content) -> some View {
    content
      .opacity(self.color == nil ? self.opacity : 0)
      .overlay {
        if let color = self.color {
          Circle().fill(color)
        }
      }
  }
}

/// A selected row's background, where the system's would be.
private struct SelectionCapsule: View {
  let color: NSColor
  let emphasized: Bool
  let cornerRadius: CGFloat

  var body: some View {
    RoundedRectangle(cornerRadius: self.cornerRadius, style: .continuous)
      .fill(Color(nsColor: self.color).opacity(self.emphasized ? 1 : 0.35))
      .padding(.horizontal, 10)
  }
}

/// The sidebar's own selection highlight, shown or not. SwiftUI's sidebar is an AppKit outline view,
/// which draws it in the system's accent color, so it's turned off for the rows to draw their own.
/// It's found from a row, up through the views the row's in.
private struct TableHighlight: NSViewRepresentable {
  let isShown: Bool

  func makeNSView(context: Context) -> Finder {
    Finder()
  }

  func updateNSView(_ view: Finder, context: Context) {
    view.isShown = self.isShown
  }

  final class Finder: NSView {
    /// What each table's highlight was before it was turned off, to turn it back on as it was.
    private static var originalStyles: [ObjectIdentifier: NSTableView.SelectionHighlightStyle] = [:]

    var isShown = true {
      didSet {
        if self.isShown != oldValue {
          self.apply()
        }
      }
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      self.apply()
    }

    // Clicks go to the row.
    override func hitTest(_ point: NSPoint) -> NSView? {
      nil
    }

    /// On the next turn of the run loop, and only if it's different. Changing it adds the table's
    /// rows again, this view among them, which mustn't happen while they're being added or laid out.
    /// Turned back on, it's as it was.
    private func apply() {
      DispatchQueue.main.async { [weak self] in
        guard let self, self.window != nil else {
          return
        }
        var view = self.superview
        while let current = view {
          if let table = current as? NSTableView {
            if self.isShown {
              if let original = Self.originalStyles.removeValue(forKey: ObjectIdentifier(table)) {
                table.selectionHighlightStyle = original
              }
            }
            else if table.selectionHighlightStyle != .none {
              Self.originalStyles[ObjectIdentifier(table)] = table.selectionHighlightStyle
              table.selectionHighlightStyle = .none
            }
            return
          }
          view = current.superview
        }
      }
    }
  }
}

// MARK: - Text Views

extension NSTextView {
  /// Selected text, and the insertion point, in the server's theme's colors, or the system's without
  /// one.
  func applyServerTheme(_ theme: ServerTheme?) {
    let selection = theme?.textSelection ?? .selectedTextBackgroundColor
    if self.selectedTextAttributes[.backgroundColor] as? NSColor != selection {
      self.selectedTextAttributes = [.backgroundColor: selection, .foregroundColor: NSColor.selectedTextColor]
    }
    let insertionPoint = theme?.accent ?? .textInsertionPointColor
    if self.insertionPointColor != insertionPoint {
      self.insertionPointColor = insertionPoint
    }
  }
}

// MARK: - Colors

private extension NSColor {
  /// The same hue, brighter on a dark color, where there's room to be, and deeper and richer on any
  /// other, to stand out against it, or nil for a color close to gray or black, which has no hue to
  /// take.
  /// Going by brightness, not how dark it looks, a bright, saturated blue, which looks dark, is made
  /// deeper, not brighter, which it already nearly is.
  var contrastingShade: NSColor? {
    guard let color = self.usingColorSpace(.genericRGB), color.saturationComponent >= 0.15, color.brightnessComponent >= 0.2 else {
      return nil
    }
    let brightness = color.brightnessComponent
    if brightness < 0.55 {
      return NSColor(colorSpace: .genericRGB, hue: color.hueComponent, saturation: color.saturationComponent, brightness: min(max(brightness + 0.4, 0.7), 1), alpha: 1)
    }
    return NSColor(colorSpace: .genericRGB, hue: color.hueComponent, saturation: min(color.saturationComponent + 0.25, 1), brightness: max(brightness - 0.35, 0.2), alpha: 1)
  }

  /// How light it looks, for contrast, as WCAG works it out.
  var luminance: Double {
    let color = self.usingColorSpace(.sRGB) ?? .black
    return 0.2126 * linearSRGB(color.redComponent) + 0.7152 * linearSRGB(color.greenComponent) + 0.0722 * linearSRGB(color.blueComponent)
  }

  /// The same hue and saturation, at least as bright as `limit`.
  func withBrightness(atLeast limit: CGFloat) -> NSColor {
    guard let color = self.usingColorSpace(.genericRGB), color.brightnessComponent < limit else {
      return self
    }
    return NSColor(colorSpace: .genericRGB, hue: color.hueComponent, saturation: color.saturationComponent, brightness: limit, alpha: color.alphaComponent)
  }
}

/// A color as Oklab has it, by how light it looks, how much color it has, and its hue, in radians.
private struct OKLCH {
  var lightness: Double
  var chroma: Double
  var hue: Double

  init(lightness: Double, chroma: Double, hue: Double) {
    self.lightness = lightness
    self.chroma = chroma
    self.hue = hue
  }

  init(_ color: NSColor) {
    let color = color.usingColorSpace(.sRGB) ?? .black
    let red = linearSRGB(color.redComponent), green = linearSRGB(color.greenComponent), blue = linearSRGB(color.blueComponent)
    let l = cbrt(0.4122214708 * red + 0.5363325363 * green + 0.0514459929 * blue)
    let m = cbrt(0.2119034982 * red + 0.6806995451 * green + 0.1073969566 * blue)
    let s = cbrt(0.0883024619 * red + 0.2817188376 * green + 0.6299787005 * blue)
    let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    let b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    self.init(lightness: 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s, chroma: hypot(a, b), hue: atan2(b, a))
  }

  /// In sRGB, with as much of its chroma as sRGB has at its lightness and hue.
  var color: NSColor {
    func linear(chroma: Double) -> [Double] {
      let a = chroma * cos(self.hue), b = chroma * sin(self.hue)
      let l = pow(self.lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
      let m = pow(self.lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
      let s = pow(self.lightness - 0.0894841775 * a - 1.2914855480 * b, 3)
      return [
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
      ]
    }
    func fits(_ rgb: [Double]) -> Bool {
      rgb.allSatisfy { $0 >= -0.0001 && $0 <= 1.0001 }
    }
    var rgb = linear(chroma: self.chroma)
    if !fits(rgb) {
      // The most chroma that fits, found by halves, from a gray, which always does.
      var fitting = 0.0, over = self.chroma
      rgb = linear(chroma: 0)
      for _ in 0..<16 {
        let tried = linear(chroma: (fitting + over) / 2)
        if fits(tried) {
          fitting = (fitting + over) / 2
          rgb = tried
        }
        else {
          over = (fitting + over) / 2
        }
      }
    }
    let srgb = rgb.map { value in
      let value = min(max(value, 0), 1)
      return value <= 0.0031308 ? 12.92 * value : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
    return NSColor(srgbRed: srgb[0], green: srgb[1], blue: srgb[2], alpha: 1)
  }
}

/// An sRGB component as the light it stands for, without its gamma.
private func linearSRGB(_ value: CGFloat) -> Double {
  let value = min(max(Double(value), 0), 1)
  return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
}

/// Contrast between two luminances, as WCAG works it out.
private func contrastRatio(_ a: Double, _ b: Double) -> Double {
  (max(a, b) + 0.05) / (min(a, b) + 0.05)
}
