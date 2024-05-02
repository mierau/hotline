import Cocoa
import SwiftUI

class HotlinePanel: NSPanel {
  init(_ view: HotlinePanelView) {
    super.init(contentRect: .zero, styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
    
    // Make sure that the panel is in front of almost all other windows
    self.isFloatingPanel = false
    self.level = .floating
    self.hidesOnDeactivate = true
    self.animationBehavior = .utilityWindow
    
    // Allow the panel to appear in a fullscreen space
    self.collectionBehavior.insert(.fullScreenAuxiliary)

    // Don't delete panel state when it's closed.
    self.isReleasedWhenClosed = false
    
    self.standardWindowButton(.closeButton)?.isHidden = true
    self.standardWindowButton(.zoomButton)?.isHidden = true
    self.standardWindowButton(.miniaturizeButton)?.isHidden = true
    
    // Make it transparent, the view inside will have to set the background.
    // This is necessary because otherwise, we will have some space for the titlebar on top of the height of the view itself which we don't want.
    self.isOpaque = false
    self.backgroundColor = .clear
    
    // Since we don't show a statusbar, this allows us to drag the window by its background instead of the titlebar.
    self.isMovableByWindowBackground = true
    self.titlebarAppearsTransparent = true
    
    let hostingView = NSHostingView(rootView: view.edgesIgnoringSafeArea(.top))
    hostingView.sizingOptions = [.standardBounds]

    self.contentView = hostingView
    
    self.cascadeTopLeft(from: NSMakePoint(16, 16))
  }
    
  override var canBecomeKey: Bool {
    return false
  }
  
  override var canBecomeMain: Bool {
    return false
  }
}
