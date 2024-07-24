import SwiftUI

@Observable
class TransferInfo: Identifiable, Equatable, Hashable {
  var id: UInt32
  
  var title: String
  var size: UInt
  var progress: Double = 0.0
  var timeRemaining: TimeInterval = 0.0
  var completed: Bool = false
  var failed: Bool = false
  
  // For file based transfers (i.e. not previews)
  var fileURL: URL? = nil
  
  var progressCallback: ((TransferInfo, Double) -> Void)? = nil
  var downloadCallback: ((TransferInfo, URL) -> Void)? = nil
  var uploadCallback: ((TransferInfo) -> Void)? = nil
  var previewCallback: ((TransferInfo, Data) -> Void)? = nil
  
  init(id: UInt32, title: String, size: UInt) {
    self.id = id
    self.title = title
    self.size = size
  }
  
  static func == (lhs: TransferInfo, rhs: TransferInfo) -> Bool {
    return lhs.id == rhs.id
  }
  
  func hash(into hasher: inout Hasher) {
    hasher.combine(self.id)
  }
}
