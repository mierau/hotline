import SwiftUI

struct TrackerBookmarkServerView: View {
  let server: BookmarkServer

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      Image("Server")
        .resizable()
        .scaledToFit()
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
