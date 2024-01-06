import SwiftUI

class FilePreviewWindowController: NSWindowController, NSWindowDelegate {
  init(info: PreviewFileInfo) {
    let window = PreviewWindow(
      contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
      styleMask: [.titled, .unifiedTitleAndToolbar, .closable, .miniaturizable, .resizable, .fullSizeContentView],
      backing: .buffered, defer: false)
    
    super.init(window: window)
    
    window.toolbarStyle = .unified
    window.delegate = self
    window.title = info.name
    window.acceptsMouseMovedEvents = true
    window.appearance = NSAppearance(named: .darkAqua)
    window.collectionBehavior = .fullScreenAuxiliary
    
    window.standardWindowButton(.closeButton)?.isHidden = false
    window.standardWindowButton(.miniaturizeButton)?.isHidden = false
    window.standardWindowButton(.zoomButton)?.isHidden = false
    
    window.center()
    
    let rootView = PreviewWindowView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
    rootView.autoresizingMask = [.width, .height]
    
    let hostingView = NSHostingView(rootView: FilePreviewView(info: info))
    hostingView.frame = rootView.bounds
    hostingView.autoresizingMask = [.width, .height]
    rootView.addSubview(hostingView)
    
    window.contentView = rootView
    
//    let toolbar = NSToolbar()
//    toolbar.allowsUserCustomization = false
//    toolbar.displayMode = .iconOnly
//    
//    window.toolbar = toolbar
    
    self.showWindow(nil)
    window.makeFirstResponder(nil)
  }
  
  deinit {
    print("FilePreviewWindowController: dealloc")
  }
  
  required init?(coder: NSCoder) {
    return nil
  }
}

struct FilePreviewToolbar: View {
  var body: some View {
//    ToolbarItem(placement: .primaryAction) {
      Button {
        
      } label: {
        Image(systemName: "plus")
      }
      .buttonStyle(.accessoryBar)
//    }
  }
}

struct FilePreviewView: View {
  enum FilePreviewFocus: Hashable {
    case window
  }
  
  @Environment(\.controlActiveState) private var controlActiveState
  @Environment(\.colorScheme) private var colorScheme
  
  let info: PreviewFileInfo
  
  @State var preview: FilePreview? = nil
  @Namespace var mainNamespace
  @FocusState private var focusField: FilePreviewFocus?
  
  var body: some View {
    Group {
      if preview?.state != .loaded {
        ProgressView(value: max(0.0, min(1.0, preview?.progress ?? 0.0)))
          .focusable(false)
          .padding()
          .accentColor(colorScheme == .dark ? .white : .black)
          .frame(maxWidth: 250)
          .focusEffectDisabled()
      }
      else {
        if let img = preview?.image {
          AnimatedImageView(image: img)
            .focusable(false)
            .scaledToFit()
            .focusEffectDisabled()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        else {
          Text("UNSUPPORTED FORMAT:")
        }
      }
    }
    .focusable()
    .focusEffectDisabled()
    .focused($focusField, equals: .window)
//    .prefersDefaultFocus(in: mainNamespace)
//    .focusScope(mainNamespace)
//    .focusSection()
    
    .ignoresSafeArea()
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.black)
    .overlay(DraggableWindowView())
    .task {
      preview = FilePreview(info: info)
      preview?.download()
    }
    .onAppear {
      focusField = .window
    }
    .onDisappear {
      preview?.cancel()
    }
  }
}

fileprivate struct AnimatedImageView: NSViewRepresentable {
  var image: NSImage?
  
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
        if let window = imageView.window {
          window.aspectRatio = img.size
          
          var windowRect = window.frame
          let centerPoint = CGPoint(x: windowRect.midX, y: windowRect.midY)
          
          windowRect.size = img.size
          
          if let screen = window.screen {
            var paddedScreenSize = screen.frame.size
            paddedScreenSize.width *= 0.5
            paddedScreenSize.height *= 0.5
            
            window.minSize = aspectFit(source: windowRect.size, bounds: CGSize(width: 400, height: 400))
            windowRect.size = aspectFit(source: windowRect.size, bounds: paddedScreenSize, minimum: window.minSize)
          }
          
          windowRect.origin.x = centerPoint.x - windowRect.width / 2.0
          windowRect.origin.y = centerPoint.y - windowRect.height / 2.0
          
          window.setFrame(windowRect, display: true, animate: true)
        }
      }
    }
    
    return imageView
  }
  
  func updateNSView(_ nsView: NSImageView, context: Context) {
    nsView.image = self.image
  }
}

fileprivate struct DraggableWindowView: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    return DraggableWindowNSView()
  }
  
  func updateNSView(_ nsView: NSView, context: Context) { }
}

fileprivate class DraggableWindowNSView: NSView {
  override public func mouseDown(with event: NSEvent) {
    window?.performDrag(with: event)
  }
}

fileprivate class PreviewWindow: NSWindow {
  override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
    super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
    self.minSize = NSSize(width: 200, height: 200)
    self.isReleasedWhenClosed = true
    self.titlebarSeparatorStyle = .line
    self.acceptsMouseMovedEvents = true
  }
  
  deinit {
    print("FilePreviewWindow: dealloc")
  }
  
  override var canBecomeMain: Bool { return true }
  override var canBecomeKey: Bool { return true }
}

fileprivate class PreviewWindowView: NSView {
  private var trackingArea: NSTrackingArea? = nil
  private var windowIsFullscreen: Bool = false
  
  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)

    self.updateTrackingAreas()
  }
  
  required init?(coder: NSCoder) {
    return nil
  }
  
  deinit {
    print("FilePreviewWindowView: dealloc")
  }
  
  override func updateTrackingAreas() {
    if let t = self.trackingArea {
      self.removeTrackingArea(t)
      self.trackingArea = nil
    }
    
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
    self.trackingArea = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
    self.addTrackingArea(self.trackingArea!)
  }
  
//  override func viewDidMoveToWindow() {
//    print("VIEW MOVED TO WINDOW?")
//    if let w = self.window {
////      w.titlebarAppearsTransparent = false
//      let toolbarButtons = NSHostingView(rootView: FilePreviewToolbar())
//      toolbarButtons.frame.size = toolbarButtons.fittingSize
//
//      let titlebarAccessory = NSTitlebarAccessoryViewController()
//      titlebarAccessory.automaticallyAdjustsSize = true
//      titlebarAccessory.view = toolbarButtons
//      titlebarAccessory.layoutAttribute = .trailing
//      w.addTitlebarAccessoryViewController(titlebarAccessory)
//    }
//  }
  
  override func mouseEntered(with event: NSEvent) {
    if self.windowIsFullscreen {
      return
    }
    
    if let w = self.window {
      w.titlebarAppearsTransparent = false
      w.titleVisibility = .visible
      w.standardWindowButton(.closeButton)?.isHidden = false
      w.standardWindowButton(.miniaturizeButton)?.isHidden = false
      w.standardWindowButton(.zoomButton)?.isHidden = false
      w.toolbar?.isVisible = true
    }
  }
  
  override func mouseExited(with event: NSEvent) {
    if self.windowIsFullscreen {
      return
    }
    
    if let w = self.window {
      w.titlebarAppearsTransparent = true
      w.titleVisibility = .hidden
      w.standardWindowButton(.closeButton)?.isHidden = true
      w.standardWindowButton(.miniaturizeButton)?.isHidden = true
      w.standardWindowButton(.zoomButton)?.isHidden = true
      w.toolbar?.isVisible = false
    }
  }
  
  func setWindowIsFullscreen(_ isFullscreen: Bool) {
    self.windowIsFullscreen = isFullscreen
    
    if let w = self.window, isFullscreen {
      w.titlebarAppearsTransparent = false
      w.titleVisibility = .visible
      w.standardWindowButton(.closeButton)?.isHidden = false
      w.standardWindowButton(.miniaturizeButton)?.isHidden = false
      w.standardWindowButton(.zoomButton)?.isHidden = false
    }
  }
  
  override var acceptsFirstResponder: Bool { return true }
  
  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers?.first {
    case " ":
      self.window?.performClose(nil)
    default:
      break
    }
  }
}
