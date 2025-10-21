import SwiftUI

struct BetterTextEditor: NSViewRepresentable {
  
  @Environment(\.lineSpacing) private var lineSpacing
  
  @Binding private var text: String
  
  private var customizations: [(NSTextView) -> Void] = []
  
  init(text: Binding<String>) {
    self._text = text
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }
  
  func makeNSView(context: Context) -> NSScrollView {
    let scrollview = NSTextView.scrollablePlainDocumentContentTextView()
    let textview = scrollview.documentView as! NSTextView
    
    textview.string = self.text
    textview.delegate = context.coordinator
    
//    let p = NSMutableParagraphStyle()
//    p.lineSpacing = self.lineSpacing
////    textview.defaultParagraphStyle = p
//    textview.typingAttributes = [
//      .paragraphStyle: p
//    ]
    
    textview.isEditable = true
    textview.isRichText = false
    textview.allowsUndo = true
    textview.isFieldEditor = false
    textview.usesAdaptiveColorMappingForDarkAppearance = true
    textview.drawsBackground = false // true
    textview.usesRuler = false
    textview.usesFindBar = false
    textview.isIncrementalSearchingEnabled = false
    textview.isAutomaticQuoteSubstitutionEnabled = false
    textview.isAutomaticDashSubstitutionEnabled = false
    textview.isAutomaticSpellingCorrectionEnabled = true
    textview.isAutomaticDataDetectionEnabled = false
    textview.isAutomaticLinkDetectionEnabled = false
    textview.usesInspectorBar = false
    textview.usesFontPanel = false
    textview.importsGraphics = false
    textview.allowsImageEditing = false
    textview.displaysLinkToolTips = true
    textview.backgroundColor = NSColor.textBackgroundColor
    textview.textContainerInset = NSSize(width: 16, height: 16)
    textview.isContinuousSpellCheckingEnabled = true
    textview.setSelectedRange(NSMakeRange(0, 0))
    self.customizations.forEach { $0(textview) }
    
    scrollview.scrollerStyle = .overlay
    
    return scrollview
  }
  
  func updateNSView(_ nsView: NSScrollView, context: Context) {
    let textview = nsView.documentView as! NSTextView
        
    if textview.string != text {
      textview.string = text
    }
    
    self.customizations.forEach { $0(textview) }
  }
  
  func betterEditorFont(_ font: NSFont) -> Self {
    self.customized { $0.font = font }
  }
  
  func betterEditorParagraphStyle(_ paragraphStyle: NSParagraphStyle) -> Self {
    self.customized { $0.defaultParagraphStyle = paragraphStyle }
  }
    
  func betterEditorAutomaticDashSubstitution(_ enabled: Bool) -> Self {
    self.customized { $0.isAutomaticDashSubstitutionEnabled = enabled }
  }
  
  func betterEditorAutomaticQuoteSubstitution(_ enabled: Bool) -> Self {
    self.customized { $0.isAutomaticQuoteSubstitutionEnabled = enabled }
  }
  
  func betterEditorAutomaticSpellingCorrection(_ enabled: Bool) -> Self {
    self.customized { $0.isAutomaticSpellingCorrectionEnabled = enabled }
  }
  
  func betterEditorTextInset(_ size: NSSize) -> Self {
    self.customized { $0.textContainerInset = size }
  }
  
  class Coordinator: NSObject, NSTextViewDelegate {
    var parent: BetterTextEditor
    
    init(_ parent: BetterTextEditor) {
      self.parent = parent
    }
    
    func textDidChange(_ notification: Notification) {
      guard let textview = notification.object as? NSTextView else {
        return
      }
      self.parent.text = textview.string
    }
  }
}

private extension BetterTextEditor {
  private func customized(_ customization: @escaping (NSTextView) -> Void) -> Self {
    var copy = self
    copy.customizations.append(customization)
    return copy
  }
}
