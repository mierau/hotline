import SwiftUI

@Observable
class HotlineClientModel {
  var status: HotlineClientStatus = .disconnected
  var server: HotlineServer?
  var userlist: [HotlineUser]?
  var chat: [(HotlineUser, String)]?
  var agreement: String?
}
