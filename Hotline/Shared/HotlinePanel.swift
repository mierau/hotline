import Cocoa
import SwiftUI

fileprivate let HOTLINE_PANEL_SIZE: CGSize = CGSizeMake(468, 114 - 10)

class HotlinePanel: NSPanel {
  init(_ view: HotlinePanelView) {
    super.init(contentRect: NSRect(x: 0, y: 0, width: HOTLINE_PANEL_SIZE.width, height: HOTLINE_PANEL_SIZE.height), styleMask: [.nonactivatingPanel, .titled, .closable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: false)
    
    // Make sure that the panel is in front of almost all other windows
    self.isFloatingPanel = false
    self.level = .floating
    self.hidesOnDeactivate = true
    self.animationBehavior = .utilityWindow
    
    // Allow the panel to appear in a fullscreen space
//    self.collectionBehavior.insert(.fullScreenAuxiliary)
    self.collectionBehavior.insert(.canJoinAllSpaces)
    self.collectionBehavior.insert(.ignoresCycle)
    
//    self.appearance = NSAppearance(named: .vibrantDark)

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
    hostingView.sizingOptions = [.preferredContentSize]

    let visualEffectView = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: HOTLINE_PANEL_SIZE.width, height: HOTLINE_PANEL_SIZE.height))
    visualEffectView.material = .sidebar
    visualEffectView.blendingMode = .behindWindow
    visualEffectView.state = NSVisualEffectView.State.active
    visualEffectView.autoresizingMask = [.width, .height]
    visualEffectView.autoresizesSubviews = true
    visualEffectView.addSubview(hostingView)
    
    self.contentView = visualEffectView
    
    hostingView.frame = visualEffectView.bounds
    
    self.cascadeTopLeft(from: NSMakePoint(16, 16))
  }
    
  override var canBecomeKey: Bool {
    return false
  }
  
  override var canBecomeMain: Bool {
    return false
  }
}
