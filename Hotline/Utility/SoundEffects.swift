import Foundation
import AVFAudio

enum SoundEffects: String {
  case loggedIn = "logged-in"
  case chatMessage = "chat-message"
  case transferComplete = "transfer-complete"
  case userLogin = "user-login"
  case userLogout = "user-logout"
  case newNews = "new-news"
  case serverMessage = "server-message"
  case error = "error"
}

@Observable
class SoundEffectPlayer: NSObject, AVAudioPlayerDelegate {
  static let shared = SoundEffectPlayer()
  
  private var activeSounds: [AVAudioPlayer] = []
  
  func playSoundEffect(_ name: SoundEffects) {
    // Load a local sound file
    guard let soundFileURL = Bundle.main.url(
      forResource: name.rawValue,
      withExtension: "aiff"
    ) else {
      return
    }
    
    DispatchQueue.main.async { [weak self] in
      guard let self = self else {
        return
      }
      
      if let soundEffect = try? AVAudioPlayer(contentsOf: soundFileURL) {
        soundEffect.delegate = self
        soundEffect.volume = 0.75
        soundEffect.play()
        
        self.activeSounds.append(soundEffect)
      }
    }
  }

  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if let i = self.activeSounds.firstIndex(of: player) {
      self.activeSounds.remove(at: i)
    }
  }
}
