import SwiftUI

public struct VisualEffectView: NSViewRepresentable {
  let material: NSVisualEffectView.Material
  let blendingMode: NSVisualEffectView.BlendingMode
  
  public init(
    material: NSVisualEffectView.Material = .contentBackground,
    blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
  ) {
    self.material = material
    self.blendingMode = blendingMode
  }
  
  public func makeNSView(context: Context) -> NSVisualEffectView {
    let visualEffectView = NSVisualEffectView()
    visualEffectView.material = material
    visualEffectView.blendingMode = blendingMode
    visualEffectView.state = NSVisualEffectView.State.active
    return visualEffectView
  }
  
  public func updateNSView(_ visualEffectView: NSVisualEffectView, context: Context) {
    visualEffectView.material = material
    visualEffectView.blendingMode = blendingMode
  }
}
