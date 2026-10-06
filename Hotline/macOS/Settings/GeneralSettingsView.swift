import SwiftUI

struct GeneralSettingsView: View {
  var body: some View {
    @Bindable var preferences = Prefs.shared

    Form {
      Toggle("Refuse private messages", isOn: $preferences.refusePrivateMessages)
      Toggle("Refuse private chat invites", isOn: $preferences.refusePrivateChat)
      Toggle("Automatic Response", isOn: $preferences.enableAutomaticMessage)
      if preferences.enableAutomaticMessage {
        DeferredTextField(title: "", text: $preferences.automaticMessage, prompt: Text("Write a response message"))
          .lineLimit(2)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity)
      }

      Section {
        Toggle("Show recent servers", isOn: $preferences.showRecentServers)
        // Themes are only on macOS 27 and later.
        if #available(macOS 27, *) {
          Toggle("Use server themed colors", isOn: $preferences.useServerThemedColors)
        }
      }

      Section("Downloads") {
        HStack(spacing: 4) {
          VStack(alignment: .leading, spacing: 4) {
            Text("Download files to:")
            HStack(spacing: 4) {
              Image(nsImage: NSWorkspace.shared.icon(forFile: preferences.resolvedDownloadFolder.resolvingSymlinksInPath().path))
                .resizable()
                .frame(width: 16, height: 16)
              Text(preferences.downloadFolderDisplay ?? "Downloads")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            }
          }

          Spacer()

          Button("Change…") {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.message = "Choose a location for your downloads"
            if panel.runModal() == .OK, let url = panel.url {
              if url.standardizedFileURL == URL.downloadsDirectory.standardizedFileURL {
                preferences.downloadFolderBookmark = nil
              } else if let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                preferences.downloadFolderBookmark = bookmark
              }
            }
          }
          .buttonBorderShape(.capsule)
          .controlSize(.small)
          if preferences.downloadFolderDisplay != nil {
            Button("Reset") {
              preferences.downloadFolderBookmark = nil
            }
            .buttonBorderShape(.capsule)
            .controlSize(.small)
          }
        }
      }

    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}
