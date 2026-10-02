import Foundation
import AudioToolbox

enum SoundEffect: String {
  case loggedIn = "logged-in"
  case chatMessage = "chat-message"
  case transferComplete = "transfer-complete"
  case userLogin = "user-login"
  case userLogout = "user-logout"
  case newNews = "new-news"
  case serverMessage = "server-message"
  case error = "error"

  static var all: [SoundEffect] = [.loggedIn, .chatMessage, .transferComplete, .userLogin, .userLogout, .newNews, .serverMessage, .error]
}

/// Plays sound effects through System Sound Services.
///
/// The system sound server plays them in its own process, so a busy moment in the app (like
/// logging in) can't cause hiccups. They play at the system alert volume, on the sound
/// effects output device. The files already have the app's 0.75 volume applied.
class SoundEffects {
  static let shared = SoundEffects()

  static func play(_ name: SoundEffect) {
    Self.shared.play(name)
  }

  /// Register the sounds at launch rather than on the first play, which is usually during login.
  static func prepare() {
    _ = Self.shared
  }

  private var soundIDs: [SoundEffect: SystemSoundID] = [:]

  private init() {
    for effect in SoundEffect.all {
      guard let soundFileURL = Bundle.main.url(forResource: effect.rawValue, withExtension: "aiff") else {
        continue
      }

      var soundID: SystemSoundID = 0
      guard AudioServicesCreateSystemSoundID(soundFileURL as CFURL, &soundID) == noErr else {
        print("SoundEffects: Couldn't register \(effect.rawValue)")
        continue
      }

      // Hotline has its own sound settings, so play even when the system's
      // "Play user interface sound effects" option is off.
      var isUISound: UInt32 = 0
      AudioServicesSetProperty(
        kAudioServicesPropertyIsUISound,
        UInt32(MemoryLayout<SystemSoundID>.size), &soundID,
        UInt32(MemoryLayout<UInt32>.size), &isUISound
      )

      self.soundIDs[effect] = soundID
    }
  }

  func play(_ name: SoundEffect) {
    guard let soundID = self.soundIDs[name] else {
      return
    }
    AudioServicesPlaySystemSound(soundID)
  }
}
