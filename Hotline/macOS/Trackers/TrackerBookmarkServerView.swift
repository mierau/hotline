import SwiftUI

/// A server's globe, with a lock on it when the server takes secure connections, or the connection
/// to it is secure.
struct ServerIcon: View {
  var name: String = "Server"
  var isSecure: Bool = false

  /// The name of the globe with the lock drawn into it, for a globe.
  static func secureName(for name: String) -> String? {
    switch name {
    case "Server": "Sever Secure"
    case "Server Large": "Server Secure Large"
    default: nil
    }
  }

  /// The small globe for a menu item, with the lock for a server that's secure. The one with the
  /// lock is wider, so for a menu with both, `matchingSecure` makes the plain one as wide, with the
  /// globe at its left, so the names after them line up.
  static func menuImage(isSecure: Bool, matchingSecure: Bool = false) -> NSImage? {
    let plain = NSImage(named: "Server")
    guard let secure = Self.secureName(for: "Server").flatMap({ NSImage(named: $0) }) else {
      return plain
    }
    if isSecure {
      return secure
    }
    guard matchingSecure, let plain, secure.size.width > plain.size.width else {
      return plain
    }
    // Drawn as it's shown, so it's the globe for the menu's appearance, light or dark.
    return NSImage(size: NSSize(width: secure.size.width, height: plain.size.height), flipped: false) { _ in
      plain.draw(in: NSRect(origin: .zero, size: plain.size))
      return true
    }
  }

  var body: some View {
    // With its size, which for the small globe is wider than the globe, for the lock.
    let secure = self.isSecure ? Self.secureName(for: self.name).flatMap { name in NSImage(named: name).map { (name: name, size: $0.size) } } : nil
    Image(self.name)
      .resizable()
      .scaledToFit()
      // Laid out as the plain globe, so the globe's the same size and names after it line up,
      // secure or not.
      .opacity(secure == nil ? 1 : 0)
      .overlay(alignment: .topLeading) {
        if let secure {
          // The same globe, with the lock on it, past the small globe's right edge, out into the
          // space after it.
          GeometryReader { geometry in
            let scale = geometry.size.height / max(secure.size.height, 1)
            Image(secure.name)
              .resizable()
              .frame(width: secure.size.width * scale, height: geometry.size.height)
          }
        }
      }
      .help(self.isSecure ? "Supports secure connections" : "")
      .accessibilityElement()
      .accessibilityLabel(self.isSecure ? "Secure" : "")
      .accessibilityHidden(!self.isSecure)
  }
}

struct TrackerBookmarkServerView: View {
  let server: BookmarkServer

  /// Whether it's listed with a TLS port, or it's been connected to over TLS.
  private var isSecure: Bool {
    self.server.tlsPort != nil || ServerTrust.shared.record(address: self.server.address, port: self.server.port) != nil
  }

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      ServerIcon(isSecure: self.isSecure)
        .frame(width: 16, height: 16, alignment: .center)
      Text(self.server.name ?? "Server").lineLimit(1).truncationMode(.tail)
      if let serverDescription = self.server.description {
        Text(serverDescription)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 0)
      if self.server.users > 0 {
        Text(String(self.server.users))
          .foregroundStyle(.secondary)
          .lineLimit(1)

        PulsingDot(color: .fileComplete)
          .frame(width: 7, height: 7)
          .padding(.trailing, 6)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// A pulsing status dot animated by Core Animation rather than SwiftUI.
///
/// The animation is interpolated by the render server, so it costs the app no
/// per-frame main thread work and stops drawing whenever the window is off screen.
private struct PulsingDot: NSViewRepresentable {
  let color: NSColor

  func makeNSView(context: Context) -> PulsingDotView {
    PulsingDotView()
  }

  func updateNSView(_ view: PulsingDotView, context: Context) {
    view.color = self.color
  }
}

private final class PulsingDotView: NSView {
  private static let pulseKey = "pulse"
  private static let pulseDuration: CFTimeInterval = 3.0

  var color: NSColor = .systemGreen {
    didSet { self.needsDisplay = true }
  }

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    self.wantsLayer = true
    self.layerContentsRedrawPolicy = .duringViewResize
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override var wantsUpdateLayer: Bool { true }

  override func updateLayer() {
    // AppKit sets the view's appearance as current here, so asset colors resolve for light/dark.
    self.layer?.backgroundColor = self.color.cgColor
    self.layer?.cornerRadius = min(self.bounds.width, self.bounds.height) / 2
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()

    guard let layer = self.layer else { return }
    layer.removeAnimation(forKey: Self.pulseKey)
    guard self.window != nil else { return }

    // Hold for 2s, fade out over 0.5s, fade back in over 0.5s.
    let pulse = CAKeyframeAnimation(keyPath: "opacity")
    pulse.values = [1.0, 1.0, 0.6, 1.0]
    pulse.keyTimes = [0.0, 0.667, 0.833, 1.0]
    pulse.timingFunctions = [
      CAMediaTimingFunction(name: .linear),
      CAMediaTimingFunction(name: .easeInEaseOut),
      CAMediaTimingFunction(name: .easeInEaseOut),
    ]
    pulse.duration = Self.pulseDuration
    pulse.repeatCount = .infinity
    pulse.isRemovedOnCompletion = false
    // Align to a shared clock so every row's dot pulses in unison.
    pulse.beginTime = floor(CACurrentMediaTime() / Self.pulseDuration) * Self.pulseDuration
    layer.add(pulse, forKey: Self.pulseKey)
  }
}
