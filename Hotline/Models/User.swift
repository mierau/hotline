import SwiftUI

struct UserStatus: OptionSet {
  let rawValue: UInt

  static let idle = UserStatus(rawValue: 1 << 0)
  static let admin = UserStatus(rawValue: 1 << 1)
}

struct User: Identifiable {
  let id: UInt
  var name: String
  var iconID: UInt
  var status: UserStatus
  
  init(hotlineUser: HotlineUser) {
    var status: UserStatus = UserStatus()
    if hotlineUser.isIdle { status.update(with: .idle) }
    if hotlineUser.isAdmin { status.update(with: .admin) }
    
    self.id = UInt(hotlineUser.id)
    self.name = hotlineUser.name
    self.iconID = UInt(hotlineUser.iconID)
    self.status = status
  }
  
  init(id: UInt, name: String, iconID: UInt, status: UserStatus) {
    self.id = id
    self.name = name
    self.iconID = iconID
    self.status = status
  }
}
