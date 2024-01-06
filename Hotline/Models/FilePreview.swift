import SwiftUI
import UniformTypeIdentifiers

enum FilePreviewState: Equatable {
  case unloaded
  case loading
  case loaded
  case failed
}

@Observable
final class FilePreview: HotlineFileClientDelegate {
  @ObservationIgnored let info: PreviewFileInfo
  @ObservationIgnored var client: HotlineFileClient? = nil
  
  var state: FilePreviewState = .unloaded
  var progress: Double = 0.0
  
  #if os(macOS)
  var image: NSImage?
  #endif
  
  init(info: PreviewFileInfo) {
    self.info = info
    
    self.client = HotlineFileClient(address: info.address, port: UInt16(info.port), reference: info.id, size: UInt32(info.size), type: .preview)
    self.client?.delegate = self
  }
  
  func download() {
    self.client?.downloadToMemory()
  }
  
  func cancel() {
    self.client?.cancel(deleteIncompleteFile: true)
  }
  
  func hotlineFileStatusChanged(client: HotlineFileClient, reference: UInt32, status: HotlineFileClientStatus, timeRemaining: TimeInterval) {
    print("FILE STATUS CHANGED", status)
    
    switch status {
    case .unconnected:
      state = .unloaded
      progress = 0.0
    case .connecting:
      state = .loading
      progress = 0.0
    case .connected:
      state = .loading
      progress = 0.0
    case .progress(let p):
      state = .loading
      progress = p
    case .failed(_):
      state = .failed
      progress = 0.0
    case .completed:
      state = .loaded
      progress = 1.0
    }
  }
  
  func hotlineFileDownloadedData(client: HotlineFileClient, reference: UInt32, data: Data) {
    self.state = .loaded
    
    let fileExtension = (info.name as NSString).pathExtension
    if let fileType = UTType(filenameExtension: fileExtension) {
      if fileType.isSubtype(of: .image) {
        #if os(iOS)
//        self.image = UIImage(data: data)
        #elseif os(macOS)
        self.image = NSImage(data: data)
        #endif
      }
    }
  }
}
