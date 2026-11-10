import SwiftUI

/// The Format menu, for Markdown in what you're writing, in chat, a private message, or a post:
/// its marks put around what's selected, or taken off it, links and images, and lists and quotes
/// for whole lines. Off anywhere else.
struct FormatMenuCommands: Commands {
  /// The editor for what you're writing, while it's Markdown that has the keys.
  private var editor: MarkdownEditor? {
    MarkdownEditorFocus.shared.editor
  }

  var body: some Commands {
    // In place of the system's Font and Text, which are for rich text.
    CommandGroup(replacing: .textFormatting) {
      ForEach(MarkdownStyle.allCases, id: \.self) { style in
        Button(style.title, systemImage: style.systemImage) {
          self.editor?.toggle(style)
        }
        .keyboardShortcut(style.shortcut)
        .disabled(self.editor?.allows(style) != true)
      }

      Divider()

      Button("Link", systemImage: "link") {
        self.editor?.link()
      }
      .keyboardShortcut(MarkdownEditor.linkShortcut)
      .disabled(self.editor?.allowsLink != true)

      Button("Image", systemImage: "photo") {
        self.editor?.image()
      }
      .disabled(self.editor?.allowsImage != true)

      Divider()

      ForEach(MarkdownLineStyle.allCases, id: \.self) { style in
        Button(style.title, systemImage: style.systemImage) {
          self.editor?.toggle(style)
        }
        .keyboardShortcut(style.shortcut)
        .disabled(self.editor?.allowsLines != true)
      }
    }
  }
}
