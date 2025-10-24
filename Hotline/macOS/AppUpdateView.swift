import SwiftUI
import MarkdownUI
import AppKit
import Observation

struct AppUpdateView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable private var update = AppUpdate.shared
  
  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      if let message = update.message {
        messageOnlyView(message)
      }
      else if update.release != nil {
        headerSection
        releaseNotesSection
        actionRow
      }
      else {
        defaultPlaceholder
      }
    }
    .padding(.horizontal, 24)
    .padding(.bottom, 24)
    .padding(.top, 8)
    .frame(width: update.message != nil ? 380 : 520)
    .frame(idealHeight: 360)
    .onChange(of: update.showWindow) { _, show in
      if !show {
        dismiss()
      }
    }
    .onDisappear {
      update.handleWindowDismissed()
    }
  }
  
  private var headerSection: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .scaledToFit()
        .frame(width: 56, height: 56)
        .shadow(color: Color.black.mix(with: .red, by: 0.4).opacity(0.15), radius: 3, y: 1.5)
      
      VStack(alignment: .leading, spacing: 2) {
        if let release = update.release {
          Text("Hotline \(release.displayVersion)")
            .font(.title2)
            .fontWeight(.semibold)
        }
        Text("A new version of Hotline is available. 🎉")
          .foregroundStyle(.secondary)
      }
    }
  }
  
  private var releaseNotesSection: some View {
    ScrollView(.vertical) {
      Markdown(releaseNotesMarkdown())
        .textSelection(.enabled)
        .markdownTheme(.gitHub.text(text: {
          FontSize(.em(0.85))
        }))
        .font(.system(size: 14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }
    .frame(minHeight: 220, maxHeight: 260)
    .background(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }
  
  private var actionRow: some View {
    HStack {
      Button("Not Now") {
        update.remindLater()
      }
      .buttonBorderShape(.capsule)
      .keyboardShortcut(.escape, modifiers: [])
      .controlSize(.large)
      .disabled(update.isDownloading)
      
      Spacer()
      
      if update.isDownloading {
        ProgressView()
          .controlSize(.small)
          .padding(.trailing, 12)
      }
      
      Button("Download") {
        update.startDownload()
      }
      .buttonBorderShape(.capsule)
      .keyboardShortcut(.defaultAction)
      .controlSize(.large)
      .disabled(update.isDownloading)
    }
  }
  
  @ViewBuilder
  private func messageOnlyView(_ message: AppUpdateMessage) -> some View {
    let iconName = {
      switch message.kind {
      case .info:
        return "info.circle"
      case .success:
        return "checkmark.circle.fill"
      case .error:
        return "exclamationmark.triangle.fill"
      }
    }()
    
    HStack(alignment: .center, spacing: 12) {
      
      if message.kind == .success {
        Text("👍")
          .font(.system(size: 42))
          .shadow(color: .yellow.mix(with: .black, by: 0.3).opacity(0.2), radius: 4, y: 1.5)
      }
      else {
        Image(systemName: iconName)
          .resizable()
          .scaledToFit()
          .symbolRenderingMode(.multicolor)
          .frame(width: 48, height: 48)
      }
      
      VStack(alignment: .leading, spacing: 2) {
        Text(message.title)
          .font(.title2)
          .fontWeight(.semibold)
        Text(message.detail)
          .foregroundStyle(.secondary)
      }
      
      Spacer()
    }
  }
  
  private var defaultPlaceholder: some View {
    VStack(alignment: .center, spacing: 12) {
      Text("No update information available.")
        .font(.headline)
      Button("Close") {
        update.acknowledgeMessage()
      }
      .keyboardShortcut(.defaultAction)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
  
  private func releaseNotesMarkdown() -> String {
    if let combined = update.releaseNotesCombined?
      .trimmingCharacters(in: .whitespacesAndNewlines),
       combined.isEmpty == false {
      return combined
    }
    
    let fallback = update.release?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return fallback.isEmpty ? "_No release notes provided._" : fallback
  }
}

#Preview {
  AppUpdate.shared.release = UpdateReleaseInfo(
    tagName: "1.0beta1",
    displayVersion: "1.0b1",
    versionNumber: 1.0,
    buildNumber: 1,
    notes: """
    - Added support for release notes in Markdown.
    - Improved the update workflow for macOS users.
    """,
    downloadURL: URL(string: "https://example.com")!,
    assetName: "Hotline.zip"
  )
  AppUpdate.shared.releases = [AppUpdate.shared.release!]
  AppUpdate.shared.releaseNotesCombined = nil
  AppUpdate.shared.showWindow = true
  return AppUpdateView()
}
