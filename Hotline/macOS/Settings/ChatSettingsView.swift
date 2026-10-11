import SwiftUI

struct ChatSettingsView: View {
  @Environment(\.openWindow) private var openWindow
  @State private var newWatchWord: String = ""
  @State private var expandedWord: String?
  @State private var servers: [ChatStore.ServerListing] = []
  @State private var serverToDelete: ChatStore.ServerListing?
  @State private var showDeleteAllConfirmation: Bool = false
  /// How long to keep chat for, when that's less than now, to ask about first.
  @State private var shorterRetention: ChatHistoryRetention?

  var body: some View {
    @Bindable var preferences = Prefs.shared

    Form {
      Toggle("Show connections in chat", isOn: $preferences.showJoinLeaveMessages)
      Toggle("Show user icons in chat", isOn: $preferences.showChatIcons)
      Toggle("Preview image links in chat", isOn: $preferences.previewChatImages)

      Section("Highlighted Words") {
        HStack(spacing: 8) {
          let mentionWord = HighlightWord(word: preferences.username, color: preferences.mentionHighlightColor)
          Text(preferences.username)
            .foregroundStyle(Color(nsColor: mentionWord.nsForegroundColor))
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(
              RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: mentionWord.nsBackgroundColor))
            )

          Spacer()

          HighlightColorPicker(
            highlightWord: mentionWord,
            isExpanded: self.expandedWord == "__mentions__",
            onToggle: {
              withAnimation(.easeInOut(duration: 0.2)) {
                self.expandedWord = self.expandedWord == "__mentions__" ? nil : "__mentions__"
              }
            },
            onSelect: { colorKey in
              Prefs.shared.mentionHighlightColor = colorKey
              withAnimation(.easeInOut(duration: 0.2)) {
                self.expandedWord = nil
              }
            }
          )

          if self.expandedWord != "__mentions__" {
            Toggle("", isOn: $preferences.highlightMentions)
              .labelsHidden()
              .toggleStyle(.switch)
              .controlSize(.mini)
          }
        }

        if !preferences.watchWords.isEmpty {
          ForEach(Array(preferences.watchWords.enumerated()), id: \.element) { index, highlightWord in
            HStack(spacing: 8) {
              Text(highlightWord.word)
                .foregroundStyle(Color(nsColor: highlightWord.nsForegroundColor))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(
                  RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: highlightWord.nsBackgroundColor))
                )

              Spacer()

              HighlightColorPicker(
                highlightWord: highlightWord,
                isExpanded: self.expandedWord == highlightWord.word,
                onToggle: {
                  withAnimation(.easeInOut(duration: 0.2)) {
                    self.expandedWord = self.expandedWord == highlightWord.word ? nil : highlightWord.word
                  }
                },
                onSelect: { colorKey in
                  if let idx = Prefs.shared.watchWords.firstIndex(where: { $0.word == highlightWord.word }) {
                    Prefs.shared.watchWords[idx].color = colorKey
                  }
                  withAnimation(.easeInOut(duration: 0.2)) {
                    self.expandedWord = nil
                  }
                }
              )

              if self.expandedWord != highlightWord.word {
                Button {
                  Prefs.shared.watchWords.removeAll { $0 == highlightWord }
                } label: {
                  Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        HStack {
          TextField(text: self.$newWatchWord, prompt: Text("Word or phrase")) {}
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .onSubmit {
              self.addWatchWord()
            }
          Button("Add") {
            self.addWatchWord()
          }
          .disabled(self.newWatchWord.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }

      Section("Chat History") {
        Picker("Keep chat history", selection: Binding(
          get: { preferences.chatHistoryRetention },
          set: { retention in
            // Deleting what's saved is asked about first.
            if preferences.chatHistoryRetention.keepsMore(than: retention), !self.servers.isEmpty {
              self.shorterRetention = retention
            }
            else {
              self.keepHistory(for: retention)
            }
          }
        )) {
          ForEach(ChatHistoryRetention.allCases) { retention in
            Text(retention.title)
              .tag(retention)
          }
        }
        if preferences.chatHistoryRetention == .forever {
          Label("Chat is kept forever, so it'll slowly take up more space. You can clear it any time.", systemImage: "info.circle")
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        if self.servers.isEmpty {
          Text("No chat history")
            .foregroundStyle(.secondary)
        } else {
          ForEach(self.servers) { server in
            HStack {
              VStack(alignment: .leading, spacing: 2) {
                Text(server.metadata.serverName ?? server.metadata.id)
                  .fontWeight(.medium)
                if server.metadata.serverName != nil {
                  Text(server.metadata.id)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              Spacer()

              Text(server.entryCount == 1 ? "1 message" : "\(server.entryCount.formatted()) messages")
                .font(.caption)
                .foregroundStyle(.secondary)

              Button {
                self.openWindow(id: "chat-log", value: ChatStore.SessionKey(address: server.metadata.address, port: server.metadata.port))
              } label: {
                Image(systemName: "eye")
              }
              .buttonStyle(.borderless)
              .help("View Chat History")
              .accessibilityLabel("View Chat History")

              Button(role: .destructive) {
                self.serverToDelete = server
              } label: {
                Image(systemName: "trash")
              }
              .buttonStyle(.borderless)
            }
          }

          Button("Clear All…", role: .destructive) {
            self.showDeleteAllConfirmation = true
          }
        }
      }
    }
    .formStyle(.grouped)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .confirmationDialog(
      "Clear chat history?",
      isPresented: Binding(
        get: { self.serverToDelete != nil },
        set: { if !$0 { self.serverToDelete = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let server = self.serverToDelete {
        Button("Clear", role: .destructive) {
          let key = ChatStore.SessionKey(
            address: server.metadata.address,
            port: server.metadata.port
          )
          Task {
            await ChatStore.shared.clearHistory(for: key)
            self.servers.removeAll { $0.id == server.id }
          }
        }
      }
      Button("Cancel", role: .cancel) {
        self.serverToDelete = nil
      }
    } message: {
      if let server = self.serverToDelete {
        Text("This will permanently delete your \(server.metadata.serverName ?? server.metadata.id) chat history. This cannot be undone.")
      }
    }
    .confirmationDialog(
      self.shorterRetention == .never ? "Delete all chat history?" : "Delete older chat history?",
      isPresented: Binding(
        get: { self.shorterRetention != nil },
        set: { if !$0 { self.shorterRetention = nil } }
      ),
      titleVisibility: .visible
    ) {
      if let retention = self.shorterRetention {
        Button("Delete", role: .destructive) {
          self.keepHistory(for: retention)
          self.shorterRetention = nil
        }
      }
      Button("Cancel", role: .cancel) {
        self.shorterRetention = nil
      }
    } message: {
      if let retention = self.shorterRetention {
        if retention == .never {
          Text("All of your saved chat and private messages will be permanently deleted, and new ones won't be saved. This cannot be undone.")
        }
        else {
          Text("Chat and private messages older than \(retention.phrase) will be permanently deleted. This cannot be undone.")
        }
      }
    }
    .confirmationDialog("Clear all chat histories?", isPresented: self.$showDeleteAllConfirmation, titleVisibility: .visible) {
      Button("Clear All", role: .destructive) {
        Task {
          await ChatStore.shared.clearAll()
          self.servers = []
        }
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text("This will permanently delete all of your chat history across all of the servers you've connected to. This cannot be undone.")
    }
    .task {
      self.servers = await ChatStore.shared.listServers()
    }
  }

  /// Keeps chat for `retention` from now on, deleting what's older.
  private func keepHistory(for retention: ChatHistoryRetention) {
    Prefs.shared.chatHistoryRetention = retention
    Task {
      await ChatStore.shared.setRetention(retention)
      self.servers = await ChatStore.shared.listServers()
    }
  }

  private func addWatchWord() {
    let trimmed = self.newWatchWord.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    let lowercased = trimmed.lowercased()
    if !Prefs.shared.watchWords.contains(where: { $0.word.lowercased() == lowercased }) {
      Prefs.shared.watchWords.append(HighlightWord(word: trimmed, color: "primary"))
    }
    self.newWatchWord = ""
  }
}

// MARK: - HighlightColorPicker

private struct HighlightColorPicker: View {
  let highlightWord: HighlightWord
  let isExpanded: Bool
  let onToggle: () -> Void
  let onSelect: (String) -> Void

  private func fillColor(for colorKey: String) -> Color {
    if colorKey == "primary" {
      return Color(nsColor: .textColor)
    }
    return HighlightWord(word: "", color: colorKey).swiftUIColor
  }

  var body: some View {
    HStack(spacing: 2) {
      if self.isExpanded {
        ForEach(HighlightWord.allColors, id: \.self) { colorKey in
          let isSelected = self.highlightWord.color == colorKey
          ColorSwatch(
            color: self.fillColor(for: colorKey),
            isSelected: isSelected,
            showHover: !isSelected
          )
          .onTapGesture {
            self.onSelect(colorKey)
          }
          .transition(.scale.combined(with: .opacity))
        }
      } else {
        Circle()
          .fill(self.fillColor(for: self.highlightWord.color))
          .frame(width: 12, height: 12)
          .onTapGesture {
            self.onToggle()
          }
      }
    }
    .animation(.easeInOut(duration: 0.2), value: self.isExpanded)
  }
}

private struct ColorSwatch: View {
  let color: Color
  let isSelected: Bool
  let showHover: Bool
  @State private var isHovered: Bool = false

  var body: some View {
    Circle()
      .fill(self.color)
      .frame(width: 12, height: 12)
      .padding(4)
      .overlay(
        Circle()
          .strokeBorder(Color.accentColor, lineWidth: self.isSelected ? 2 : 0)
      )
      .scaleEffect(self.showHover && self.isHovered ? 1.25 : 1.0)
      .animation(.easeInOut(duration: 0.15), value: self.isHovered)
      .onHover { hovering in
        self.isHovered = hovering
      }
  }
}
