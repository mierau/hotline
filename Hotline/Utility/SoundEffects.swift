import Foundation
import AVFAudio

enum SoundEffects: String {
  case loggedIn = "logged-in"
  case chatMessage = "chat-message"
  case transferComplete = "transfer-complete"
  case userLogin = "user-login"
  case userLogout = "user-logout"
  case newNews = "new-news"
}

@Observable
class SoundEffectPlayer: NSObject, AVAudioPlayerDelegate {
  var activeSounds: [AVAudioPlayer] = []
  
  func playSoundEffect(_ name: SoundEffects) {
    // Load a local sound file
    guard let soundFileURL = Bundle.main.url(
      forResource: name.rawValue,
      withExtension: "aiff"
    ) else {
      return
    }
    
    do {
      let soundEffect = try AVAudioPlayer(contentsOf: soundFileURL)
      soundEffect.delegate = self
      
      self.activeSounds.append(soundEffect)
      
      soundEffect.volume = 0.75
      soundEffect.play()
    }
    catch {}
  }
  
  func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    if let i = self.activeSounds.firstIndex(of: player) {
      self.activeSounds.remove(at: i)
    }
  }
}
