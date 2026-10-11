import SwiftUI
import AVFoundation

/// Play and pause, where it's got to and how much is left, and its timeline, which shows what's
/// come of it, for audio or video playing in a preview: in a row, or bigger, over a video or a
/// cover, with a way to turn its sound off.
struct MediaControls: View {
  let playback: MediaPlayback
  let downloaded: [Range<Double>]
  /// Bigger, over a video or a cover, with a way to turn its sound off.
  let large: Bool

  var body: some View {
    HStack(spacing: self.large ? 10 : 6) {
      Button {
        self.playback.toggle()
      } label: {
        Image(systemName: self.playback.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: self.large ? 20 : 14))
          .contentTransition(.symbolEffect(.replace))
          .frame(width: self.large ? 30 : 20, height: self.large ? 30 : 20)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(.primary)
      .help(self.playback.isPlaying ? "Pause" : "Play")
      .accessibilityLabel(self.playback.isPlaying ? "Pause" : "Play")

      Group {
        // Waiting for more to come before it can play on.
        if self.playback.isWaiting {
          ProgressView()
            .controlSize(.mini)
        }
        else {
          Text(Self.time(self.playback.time))
        }
      }
      .frame(minWidth: 32, alignment: .trailing)
      .allowsHitTesting(false)

      MediaTimeline(
        position: self.playback.duration > 0 ? self.playback.time / self.playback.duration : 0,
        downloaded: self.downloaded,
        duration: self.playback.duration
      ) { fraction, done in
        // There as it's dragged, through what's come, and anywhere once it's let go, so dragging
        // it across what hasn't doesn't fetch each part it crosses.
        if done || self.downloaded.contains(where: { $0.contains(fraction) }) {
          self.playback.seek(to: fraction, done: done)
        }
        else {
          self.playback.show(fraction)
        }
      }

      Text("-" + Self.time(max(0, self.playback.duration - self.playback.time)))
        .frame(minWidth: 36, alignment: .leading)
        .allowsHitTesting(false)

      if self.large {
        Button {
          self.playback.toggleMute()
        } label: {
          Image(systemName: self.playback.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            .font(.system(size: 13))
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 24, height: 30)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .help(self.playback.isMuted ? "Turn Sound On" : "Turn Sound Off")
        .accessibilityLabel(self.playback.isMuted ? "Turn Sound On" : "Turn Sound Off")
      }
    }
    .font(.system(size: 11))
    .monospacedDigit()
    .foregroundStyle(.secondary)
  }

  /// Minutes and seconds, or hours, minutes and seconds, for anything an hour or longer.
  static func time(_ seconds: Double) -> String {
    let duration = Duration.seconds(seconds.isFinite ? max(0, seconds.rounded(.down)) : 0)
    return duration.formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
  }
}

/// Where it's got to, along how long it is, over what's come of it, which can be clicked, or
/// dragged along, to go to anywhere in it.
private struct MediaTimeline: View {
  /// How far it's got, from 0 to 1.
  let position: Double
  let downloaded: [Range<Double>]
  let duration: Double
  /// Goes there, from 0 to 1, as it's dragged, and once it's let go.
  let seek: (_ fraction: Double, _ done: Bool) -> Void

  @State private var dragging: Double? = nil
  @State private var hovering = false

  private static let height: CGFloat = 4
  private static let knob: CGFloat = 10

  var body: some View {
    GeometryReader { geometry in
      let width = geometry.size.width
      let shown = self.dragging ?? min(max(self.position, 0), 1)
      ZStack(alignment: .leading) {
        // One bar, rounded at its ends, with what's come and what's played along it.
        ZStack(alignment: .leading) {
          Rectangle()
            .fill(.primary.opacity(0.12))
          ForEach(Array(self.downloaded.enumerated()), id: \.offset) { _, part in
            Rectangle()
              .fill(.primary.opacity(0.18))
              .frame(width: max(1, (part.upperBound - part.lowerBound) * width))
              .offset(x: part.lowerBound * width)
          }
          Rectangle()
            .fill(.primary)
            .frame(width: shown * width)
        }
        .clipShape(Capsule())
        Circle()
          .fill(.primary)
          .frame(width: Self.knob, height: Self.knob)
          .shadow(color: .black.opacity(0.3), radius: 1.5)
          .offset(x: shown * width - Self.knob / 2)
          .opacity(self.hovering || self.dragging != nil ? 1 : 0)
      }
      .frame(height: Self.height)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .contentShape(.rect)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let fraction = Self.fraction(value.location.x, of: width)
            self.dragging = fraction
            self.seek(fraction, false)
          }
          .onEnded { value in
            self.seek(Self.fraction(value.location.x, of: width), true)
            self.dragging = nil
          }
      )
      .onHover { hovering in
        withAnimation(.easeOut(duration: 0.15)) {
          self.hovering = hovering
        }
      }
    }
    .frame(height: 18)
    .accessibilityElement()
    .accessibilityLabel("Position")
    .accessibilityValue(MediaControls.time(self.position * self.duration))
    .accessibilityAdjustableAction { direction in
      guard self.duration > 0 else {
        return
      }
      let step = 10 / self.duration
      switch direction {
      case .increment:
        self.seek(min(1, self.position + step), true)
      case .decrement:
        self.seek(max(0, self.position - step), true)
      @unknown default:
        break
      }
    }
  }

  private static func fraction(_ x: CGFloat, of width: CGFloat) -> Double {
    width > 0 ? min(max(x / width, 0), 1) : 0
  }
}

/// How a player's doing as it plays: where it's got to, how long what it's playing is, and
/// whether it's playing, or waiting for more to come so it can.
@MainActor
@Observable
final class MediaPlayback {
  let player: AVPlayer
  private(set) var time: Double = 0
  private(set) var duration: Double = 0
  private(set) var isPlaying = false
  private(set) var isWaiting = false
  private(set) var isMuted = false

  @ObservationIgnored private var timeObserver: Any?
  @ObservationIgnored private var observations: [NSKeyValueObservation] = []
  /// Where it's been dragged to, which it's shown at until it's there.
  @ObservationIgnored private var seeking: Double?

  init(player: AVPlayer) {
    self.player = player
    self.timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.update()
      }
    }
    self.observations = [
      player.observe(\.timeControlStatus) { [weak self] _, _ in
        Task { @MainActor in
          self?.update()
        }
      },
      player.observe(\.currentItem?.duration) { [weak self] _, _ in
        Task { @MainActor in
          self?.update()
        }
      },
      player.observe(\.isMuted) { [weak self] _, _ in
        Task { @MainActor in
          self?.update()
        }
      },
    ]
    self.update()
  }

  private func update() {
    let duration = self.player.currentItem?.duration.seconds ?? .nan
    self.duration = duration.isFinite ? duration : 0
    if self.seeking == nil {
      let time = self.player.currentTime().seconds
      self.time = time.isFinite ? time : 0
    }
    self.isPlaying = self.player.timeControlStatus != .paused
    self.isWaiting = self.player.timeControlStatus == .waitingToPlayAtSpecifiedRate
    self.isMuted = self.player.isMuted
  }

  /// Plays, from the start again if it's at the end, or pauses.
  func toggle() {
    if self.player.timeControlStatus == .paused {
      if self.duration > 0, self.time >= self.duration - 0.25 {
        self.player.seek(to: .zero)
      }
      self.player.play()
    }
    else {
      self.player.pause()
    }
    self.update()
  }

  /// Shows it at `fraction` of the way through, as it's dragged there, without going there yet.
  func show(_ fraction: Double) {
    guard self.duration > 0 else {
      return
    }
    self.seeking = fraction * self.duration
    self.time = fraction * self.duration
  }

  func toggleMute() {
    self.player.isMuted.toggle()
    self.update()
  }

  /// Goes to `fraction` of the way through, roughly as it's dragged, and exactly once it's let go.
  func seek(to fraction: Double, done: Bool) {
    guard self.duration > 0 else {
      return
    }
    let seconds = fraction * self.duration
    self.time = seconds
    self.seeking = seconds
    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    let tolerance: CMTime = done ? .zero : CMTime(seconds: 0.5, preferredTimescale: 600)
    self.player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
      guard finished, done else {
        return
      }
      Task { @MainActor in
        guard let self, self.seeking == seconds else {
          return
        }
        self.seeking = nil
        self.update()
      }
    }
  }

  func stop() {
    if let timeObserver = self.timeObserver {
      self.player.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    for observation in self.observations {
      observation.invalidate()
    }
    self.observations = []
  }
}
