import SwiftUI

/// An animated globe icon that cycles through different world regions
///
/// Displays a spinning globe effect by cycling through SF Symbol images showing
/// different parts of the world. Useful for indicating network activity or global content.
///
/// Example:
/// ```swift
/// SpinningGlobeView()
///   .frame(width: 16, height: 16)
///
/// SpinningGlobeView(frameDelay: 0.5)
///   .frame(width: 24, height: 24)
/// ```
struct SpinningGlobeView: View {
  /// Delay between frames in seconds (default: 0.3)
  let frameDelay: TimeInterval

  /// SF Symbol names for each frame of the globe animation
  private let globeFrames = [
    "globe.americas.fill",
    "globe.europe.africa.fill",
    "globe.central.south.asia.fill",
    "globe.asia.australia.fill"
  ]

  @State private var currentFrameIndex = 0
  @State private var animationTask: Task<Void, Never>?

  init(frameDelay: TimeInterval = 0.25) {
    self.frameDelay = frameDelay
  }

  var body: some View {
    Image(systemName: globeFrames[currentFrameIndex])
      .onAppear {
        startAnimation()
      }
      .onDisappear {
        stopAnimation()
      }
  }

  private func startAnimation() {
    animationTask = Task {
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: UInt64(frameDelay * 1_000_000_000))

        guard !Task.isCancelled else { break }

        currentFrameIndex = (currentFrameIndex + 1) % globeFrames.count
      }
    }
  }

  private func stopAnimation() {
    animationTask?.cancel()
    animationTask = nil
  }
}

#Preview {
  VStack(spacing: 20) {
    HStack(spacing: 20) {
      SpinningGlobeView()
        .frame(width: 12, height: 12)

      SpinningGlobeView()
        .frame(width: 16, height: 16)

      SpinningGlobeView()
        .frame(width: 24, height: 24)
    }

    Text("Different frame delays:")

    HStack(spacing: 20) {
      SpinningGlobeView(frameDelay: 0.1)
        .frame(width: 16, height: 16)

      SpinningGlobeView(frameDelay: 0.3)
        .frame(width: 16, height: 16)

      SpinningGlobeView(frameDelay: 0.6)
        .frame(width: 16, height: 16)
    }
  }
  .padding()
}
