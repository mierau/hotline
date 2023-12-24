import SwiftUI

enum PrefsKeys: String {
  case username = "username"
  case userIconID = "user icon id"
  case refusePrivateMessages = "refuse private messages"
  case refusePrivateChat = "refuse private chat"
  case enableAutomaticMessage = "enable automatic message"
  case automaticMessage = "automatic message"
}

@Observable
class Prefs {
  init() {
    UserDefaults.standard.register(defaults:[
      PrefsKeys.username.rawValue: "guest",
      PrefsKeys.userIconID.rawValue: 137,
      PrefsKeys.refusePrivateMessages.rawValue: false,
      PrefsKeys.refusePrivateChat.rawValue: false,
      PrefsKeys.enableAutomaticMessage.rawValue: false,
      PrefsKeys.automaticMessage.rawValue: "",
    ])
    
    self.username = UserDefaults.standard.string(forKey: PrefsKeys.username.rawValue)!
    self.userIconID = UserDefaults.standard.integer(forKey: PrefsKeys.userIconID.rawValue)
    self.refusePrivateMessages = UserDefaults.standard.bool(forKey: PrefsKeys.refusePrivateMessages.rawValue)
    self.refusePrivateChat = UserDefaults.standard.bool(forKey: PrefsKeys.refusePrivateChat.rawValue)
    self.enableAutomaticMessage = UserDefaults.standard.bool(forKey: PrefsKeys.enableAutomaticMessage.rawValue)
    self.automaticMessage = UserDefaults.standard.string(forKey: PrefsKeys.automaticMessage.rawValue)!
  }
  
  var username: String {
    didSet { UserDefaults.standard.set(self.username, forKey: PrefsKeys.username.rawValue) }
  }
  
  var userIconID: Int {
    didSet { UserDefaults.standard.set(self.userIconID, forKey: PrefsKeys.userIconID.rawValue) }
  }
  
  var refusePrivateMessages: Bool {
    didSet { UserDefaults.standard.set(self.refusePrivateMessages, forKey: PrefsKeys.refusePrivateMessages.rawValue) }
  }
  
  var refusePrivateChat: Bool {
    didSet { UserDefaults.standard.set(self.refusePrivateChat, forKey: PrefsKeys.refusePrivateChat.rawValue) }
  }
  
  var enableAutomaticMessage: Bool {
    didSet { UserDefaults.standard.set(self.enableAutomaticMessage, forKey: PrefsKeys.enableAutomaticMessage.rawValue) }
  }
  
  var automaticMessage: String {
    didSet { UserDefaults.standard.set(self.automaticMessage, forKey: PrefsKeys.automaticMessage.rawValue) }
  }
}

//@Observable
//final class Preferences {
//  
//  var username: String {
//    get {
//      access(keyPath: \.username)
//      return UserDefaults.standard.object(forKey: "username") as? String ?? "guest"
//    }
//    set {
//      withMutation(keyPath: \.username) {
//        UserDefaults.standard.set(newValue, forKey: "username")
//      }
//    }
//  }
//  
//  var refusePrivateMessages: Bool {
//    get { return UserDefaults.standard.object(forKey: "refuse private messages") as? Bool ?? false }
//    set { UserDefaults.standard.set(newValue, forKey: "refuse private messages") }
//  }
//  
//  var refusePrivateChat: Bool {
//    get { return UserDefaults.standard.object(forKey: "refuse private chat") as? Bool ?? false }
//    set { UserDefaults.standard.set(newValue, forKey: "refuse private chat") }
//  }
//  
//  var automaticResponseEnabled: Bool {
//    get { return UserDefaults.standard.object(forKey: "enable automatic response") as? Bool ?? false }
//    set { UserDefaults.standard.set(newValue, forKey: "enable automatic response") }
//  }
//  
//  var automaticResponse: String {
//    get { return UserDefaults.standard.object(forKey: "automatic response") as? String ?? "" }
//    set { UserDefaults.standard.set(newValue, forKey: "automatic response") }
//  }
//  
//  var userIconID: Int {
//    get { return UserDefaults.standard.object(forKey: "user icon") as? Int ?? 404 }
//    set { UserDefaults.standard.set(newValue, forKey: "user icon") }
//  }
//  
////  @AppStorage("username") public var username: String = "guest"
////  @AppStorage("refuse private messages") public var refusePrivateMessages: Bool = false
////  @AppStorage("refuse private chat") public var refusePrivateChat: Bool = false
////  @AppStorage("enable automatic response") public var enableAutomaticResponse: Bool = false
////  @AppStorage("automatic response") public var automaticResponse: String = ""
////  
////  // Icon
////  @AppStorage("user icon id") public var iconID: Int = 404
//  
//  public static let shared = Preferences()
//}
