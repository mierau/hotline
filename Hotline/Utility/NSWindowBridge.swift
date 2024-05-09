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
