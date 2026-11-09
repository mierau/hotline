import SwiftUI

fileprivate class NSWindowAccessorView: NSView {
  let executeBlock: (_ window: NSWindow? ) -> ()
  
  init(_ inConfigFunction: @escaping (_ window: NSWindow? ) -> () ) {
    executeBlock = inConfigFunction
    super.init( frame: NSRect() )
  }
  
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
  
  public override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    executeBlock( self.window ) // We pass it through even if it is nil.
  }
}

public struct NSWindowAccessor: NSViewRepresentable {
  var configCode: (_ window: NSWindow? ) -> ()
  
  public init(_ configCode: @escaping (_: NSWindow?) -> Void) { self.configCode = configCode }
  public func makeNSView(context: Context) -> NSView   { return NSWindowAccessorView( configCode ) }
  public func updateNSView(_ nsView: NSView, context: Context) {}
}


//import SwiftUI

  /// A helper view you can embed once per window to run a closure
/// with the underlying NSWindow reference.
struct WindowConfigurator: NSViewRepresentable {
  let configure: (NSWindow) -> Void
  
  func makeNSView(context: Context) -> NSView {
    let view = NSView()
    DispatchQueue.main.async {
      if let window = view.window {
        configure(window)
      }
    }
    return view
  }
  
  func updateNSView(_ nsView: NSView, context: Context) { }
}

/// Asks before a window closes, when closing it would lose something. SwiftUI can't keep a window
/// open, so this stands in as the window's delegate, and passes everything else on to the delegate
/// SwiftUI gave the window.
final class WindowCloseGuard: NSObject, NSWindowDelegate {
  /// The delegate the window had, which still gets every other message.
  nonisolated(unsafe) private weak var original: NSWindowDelegate?
  /// Whether the window can close now. When it can't, this asks, and returns false.
  private var shouldClose: @MainActor (NSWindow) -> Bool

  /// Where a window keeps its guard, as a window doesn't keep its delegate.
  private static var key: UInt8 = 0

  private init(original: NSWindowDelegate?, shouldClose: @escaping @MainActor (NSWindow) -> Bool) {
    self.original = original
    self.shouldClose = shouldClose
    super.init()
  }

  /// Guards the window, or updates the guard it has, wrapping whatever delegate it has now.
  @MainActor
  static func guardClosing(_ window: NSWindow, shouldClose: @escaping @MainActor (NSWindow) -> Bool) {
    if let existing = window.delegate as? WindowCloseGuard {
      existing.shouldClose = shouldClose
      return
    }

    let closeGuard = WindowCloseGuard(original: window.delegate, shouldClose: shouldClose)
    objc_setAssociatedObject(window, &Self.key, closeGuard, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    window.delegate = closeGuard
  }

  func windowShouldClose(_ sender: NSWindow) -> Bool {
    guard self.shouldClose(sender) else {
      return false
    }
    return self.original?.windowShouldClose?(sender) ?? true
  }

  // MARK: - Passing Messages On

  nonisolated override func responds(to aSelector: Selector!) -> Bool {
    super.responds(to: aSelector) || (self.original?.responds(to: aSelector) ?? false)
  }

  nonisolated override func forwardingTarget(for aSelector: Selector!) -> Any? {
    if self.original?.responds(to: aSelector) == true {
      return self.original
    }
    return super.forwardingTarget(for: aSelector)
  }
}
