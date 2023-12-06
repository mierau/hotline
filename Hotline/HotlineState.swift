import Foundation
import SwiftUI

@Observable
class HotlineState {
  var agreementPresented = false
  var trackerPresented = true
  
  func presentTracker() {
    self.trackerPresented = true
  }
  
  func dismissTracker() {
    self.trackerPresented = false
  }
  
  func presentAgreement() {
    self.agreementPresented = true
  }
  
  func dismissAgreement() {
    self.agreementPresented = false
  }
}
