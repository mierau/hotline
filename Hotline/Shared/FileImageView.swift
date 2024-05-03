import SwiftUI

struct FileImageView: NSViewRepresentable {
  var image: NSImage?
  
  let minimumSize: CGSize = CGSize(width: 350, height: 350)
  let presentationPaddingRatio: Double = 0.5
  
  func makeNSView(context: Context) -> NSImageView {
    let imageView = NSImageView()
    imageView.imageScaling = .scaleProportionallyUpOrDown
    imageView.animates = true
    imageView.isEditable = false
    imageView.allowsCutCopyPaste = true
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
    imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    
    if let img = self.image {
      imageView.image = img
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.resizeWindowForImageView(imageView)
      }
    }
    
    return imageView
  }
  
  func updateNSView(_ nsView: NSImageView, context: Context) {
    nsView.image = self.image
  }
  
  // MARK: -
  
  func resizeWindowForImageView(_ imageView: NSImageView) {
    guard let window = imageView.window, let img = imageView.image else {
      return
    }
    
    var windowRect = window.contentLayoutRect
    let windowChromeSize = CGSize(width: window.frame.width - windowRect.width, height: window.frame.height - windowRect.height)
    
    var windowMinSize: CGSize = windowRect.size
    let centerPoint = CGPoint(x: window.frame.midX, y: window.frame.midY)
    
    windowRect.size = img.size
    
    if let screen = window.screen {
      var paddedScreenSize = screen.frame.size
      paddedScreenSize.width *= self.presentationPaddingRatio
      paddedScreenSize.height *= self.presentationPaddingRatio
      
      windowMinSize = aspectFit(source: windowRect.size, bounds: self.minimumSize)
      windowRect.size = aspectFit(source: windowRect.size, bounds: paddedScreenSize, minimum: windowMinSize)
    }
    
    windowRect.size.width += windowChromeSize.width
    windowRect.size.height += windowChromeSize.height
    
    windowRect.origin.x = centerPoint.x - windowRect.width / 2.0
    windowRect.origin.y = centerPoint.y - windowRect.height / 2.0
    
    window.setFrame(windowRect, display: true, animate: true)
    
//    Do these APIs even work??
//    window.aspectRatio = windowRect.size
//    window.contentAspectRatio = windowRect.size
  }
  
  func aspectFit(source sourceSize: CGSize, bounds boundingSize: CGSize, minimum minSize: CGSize? = nil) -> CGSize {
    let sourceAspectRatio = sourceSize.width / sourceSize.height
    
    var fitSize: CGSize = sourceSize
    
    if fitSize.width > boundingSize.width {
      fitSize.width = boundingSize.width
      fitSize.height = fitSize.width / sourceAspectRatio
    }
    
    if fitSize.height > boundingSize.height {
      fitSize.height = boundingSize.height
      fitSize.width = fitSize.height * sourceAspectRatio
    }
    
    if let m = minSize {
      if fitSize.width < m.width {
        fitSize.width = m.width
        fitSize.height = fitSize.width / sourceAspectRatio
      }
      
      if fitSize.height < m.height {
        fitSize.height = m.height
        fitSize.width = fitSize.height * sourceAspectRatio
      }
    }
    
    return fitSize
  }
}
