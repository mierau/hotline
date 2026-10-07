import SwiftUI

/// Choosing people to chat with privately: to start a private chat with, and what about, or to
/// invite to one you're in. Those who turn down private chats are there, but can't be chosen.
/// People are chosen with a click, or from the keyboard: the arrow keys and typing a name go to
/// someone, and Space chooses them.
struct PrivateChatInviteSheet: View {
  @Environment(HotlineState.self) private var model: HotlineState
  @Environment(\.dismiss) private var dismiss

  /// The chat they're invited to, or nil to start one.
  let chatID: UInt32?
  /// Given a new chat, once it's started.
  var onStart: (UInt32) -> Void

  @State private var chosen: Set<UInt16>
  @State private var subject: String = ""
  @State private var sending: Bool = false
  /// The person the keyboard is on, and what's been typed to go to someone, and when.
  @State private var current: UInt16? = nil
  @State private var typed: String = ""
  @State private var typedAt: Date = .distantPast
  @FocusState private var listFocused: Bool

  init(chatID: UInt32?, chosen: Set<UInt16> = [], onStart: @escaping (UInt32) -> Void = { _ in }) {
    self.chatID = chatID
    self._chosen = State(initialValue: chosen)
    self.onStart = onStart
  }

  /// Who can be asked: everyone but you and whoever's in the chat already, by name.
  private var people: [User] {
    let here = Set(self.chatID.flatMap { self.model.privateChat($0) }?.users.map(\.id) ?? [])
    return self.model.users
      .filter { $0.id != self.model.ownUserID && !here.contains($0.id) }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }

  /// What the sheet's for: a new chat, or the one they're invited to, by its subject, if it has one.
  private var title: String {
    guard let chatID = self.chatID else {
      return "New Private Chat"
    }
    let subject = self.model.privateChat(chatID)?.subject ?? ""
    return subject.isBlank ? "Invite to Private Chat" : "Invite to \(subject)"
  }

  var body: some View {
    let people = self.people

    VStack(alignment: .leading, spacing: 16) {
      // What it's for, at the top, with the icon private chats have in the sidebar.
      HStack(alignment: .top, spacing: 12) {
        Image("Section Users")
          .resizable()
          .scaledToFit()
          .frame(width: 32, height: 32)

        VStack(alignment: .leading, spacing: 2) {
          Text(self.title)
            .font(.title3)
            .fontWeight(.semibold)
          Text(self.chatID == nil ? "Choose who to invite to a private chat. You can invite others later." : "Choose who to invite to this chat.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }

      VStack(spacing: 10) {
        // The people, each a row to click to choose, in a box of their own.
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 2) {
              ForEach(people) { user in
                PrivateChatPersonRow(user: user, isChosen: self.chosen.contains(user.id), isCurrent: self.listFocused && self.current == user.id) {
                  self.current = user.id
                  self.listFocused = true
                  self.toggle(user)
                }
                .id(user.id)
              }
            }
            .padding(PrivateChatPersonRow.inset)
          }
          .frame(height: 252)
          // A fill, rather than a color, which the sheet's white in light mode would hide.
          .background(.fill.quaternary, in: .rect(cornerRadius: PrivateChatPersonRow.boxCornerRadius))
          .focusable()
          .focusEffectDisabled()
          .focused(self.$listFocused)
          .onKeyPress(phases: .down) { press in
            self.handle(press, among: people)
          }
          .onChange(of: self.current) { _, current in
            if let current {
              proxy.scrollTo(current)
            }
          }
        }
        .overlay {
          if people.isEmpty {
            VStack(spacing: 6) {
              Image(systemName: "person.2.slash")
                .font(.title2)
              Text(self.chatID == nil ? "There's no one else here." : "Everyone here is in the chat.")
            }
            .foregroundStyle(.secondary)
          }
        }

        // What a new one's about, which anyone in it can change.
        if self.chatID == nil {
          PrivateChatSheetField(systemImage: "quote.closing", prompt: "Subject (optional)", text: self.$subject)
        }
      }
    }
    .padding(20)
    .frame(width: 380)
    // Typing a name goes to them right away.
    .defaultFocus(self.$listFocused, true)
    .toolbar {
      if self.sending {
        ToolbarItem {
          ProgressView()
            .controlSize(.small)
        }
      }

      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.dismiss()
        }
      }

      ToolbarItem(placement: .confirmationAction) {
        Button(self.chatID == nil ? "Start Chat" : "Invite") {
          // In the order they're listed.
          let userIDs = people.map(\.id).filter { self.chosen.contains($0) }
          Task {
            self.sending = true
            defer { self.sending = false }

            do {
              if let chatID = self.chatID {
                try await self.model.inviteToPrivateChat(chatID, userIDs: userIDs)
              }
              else {
                let subject = self.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                let chatID = try await self.model.startPrivateChat(with: userIDs, subject: subject)
                self.onStart(chatID)
              }
              self.dismiss()
            }
            catch {
              // It didn't go through, so the sheet stays open to try again.
            }
          }
        }
        .disabled(self.chosen.isEmpty || self.sending)
      }
    }
  }

  private func toggle(_ user: User) {
    guard !user.refusesPrivateChat else {
      return
    }
    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
      if self.chosen.contains(user.id) {
        self.chosen.remove(user.id)
      }
      else {
        self.chosen.insert(user.id)
      }
    }
  }

  /// The keys for choosing people: the arrows go up and down among those who can be chosen, Space
  /// chooses or unchooses the one the keyboard is on, and typing goes to the first whose name starts
  /// with it. Return is the sheet's, to start the chat.
  private func handle(_ press: KeyPress, among people: [User]) -> KeyPress.Result {
    let choosable = people.filter { !$0.refusesPrivateChat }
    let index = choosable.firstIndex(where: { $0.id == self.current })

    switch press.key {
    case .downArrow, .upArrow:
      guard !choosable.isEmpty else {
        return .ignored
      }
      let down = press.key == .downArrow
      let next = index.map { down ? min($0 + 1, choosable.count - 1) : max($0 - 1, 0) } ?? (down ? 0 : choosable.count - 1)
      self.current = choosable[next].id
      return .handled

    case .space:
      guard let index else {
        return .ignored
      }
      self.toggle(choosable[index])
      return .handled

    default:
      let characters = press.characters
      guard press.modifiers.isDisjoint(with: [.command, .control, .option]), !characters.isEmpty,
            characters.allSatisfy({ $0.isLetter || $0.isNumber || $0.isPunctuation || $0.isSymbol }) else {
        return .ignored
      }
      // Typed together, the letters go on from the ones before; after a pause, they start over.
      let now = Date()
      self.typed = now.timeIntervalSince(self.typedAt) < 1 ? self.typed + characters : characters
      self.typedAt = now
      if let match = choosable.first(where: { $0.name.range(of: self.typed, options: [.anchored, .caseInsensitive, .diacriticInsensitive]) != nil }) {
        self.current = match.id
      }
      return .handled
    }
  }
}

/// Someone to choose in the sheet: their icon and name, bolder with a checkmark and a touch of the
/// tint once they're chosen, which a click anywhere on the row puts there or takes away, and a ring
/// in the tint while the keyboard is on them. Those who turn down private chats are fainter, with a
/// raised hand where the checkmark would be, and can't be chosen.
private struct PrivateChatPersonRow: View {
  /// The box the rows are in: how round it is, and how far in from its edges they are, which makes
  /// their corners as round as its, inside it.
  static let boxCornerRadius: CGFloat = 12
  static let inset: CGFloat = 5

  let user: User
  let isChosen: Bool
  let isCurrent: Bool
  let toggle: () -> Void

  @State private var hovered: Bool = false

  var body: some View {
    Button(action: self.toggle) {
      HStack(spacing: 8) {
        if let iconImage = HotlineState.getClassicIcon(Int(self.user.iconID)) {
          Image(nsImage: iconImage)
            .frame(width: 16, height: 16)
            .padding(.horizontal, 2)
        }
        else {
          Image("User")
            .frame(width: 16, height: 16)
            .padding(.horizontal, 2)
        }

        Text(self.user.name)
          .lineLimit(1)
          .fontWeight(self.isChosen ? .semibold : .regular)
          .foregroundStyle(self.user.isAdmin ? AnyShapeStyle(.serverAdmin) : AnyShapeStyle(.primary))

        Spacer(minLength: 8)

        if self.user.refusesPrivateChat {
          Image(systemName: "hand.raised.fill")
            .foregroundStyle(.secondary)
        }
        else {
          PrivateChatCheckmark(isChosen: self.isChosen)
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 8)
      .background {
        RoundedRectangle(cornerRadius: Self.boxCornerRadius - Self.inset)
          .fill(self.background)
      }
      .overlay {
        RoundedRectangle(cornerRadius: Self.boxCornerRadius - Self.inset)
          .strokeBorder(.tint.opacity(self.isCurrent ? 0.6 : 0), lineWidth: 2)
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    // Chosen with the list's keys, not on its own as a button.
    .focusable(false)
    .disabled(self.user.refusesPrivateChat)
    .opacity(self.user.refusesPrivateChat ? 0.5 : 1)
    .help(self.user.refusesPrivateChat ? "\(self.user.name) turns down private chats" : "")
    .onHover { hovered in
      self.hovered = hovered
    }
    .accessibilityAddTraits(self.isChosen ? .isSelected : [])
  }

  private var background: AnyShapeStyle {
    // The tint, which is a server's theme's accent, as the checkmark is.
    if self.isChosen {
      return AnyShapeStyle(.tint.opacity(0.14))
    }
    if self.hovered && !self.user.refusesPrivateChat {
      return AnyShapeStyle(.fill.quaternary)
    }
    return AnyShapeStyle(Color.clear)
  }
}

/// The checkmark of someone chosen, which draws itself in as they're chosen and away as they're not,
/// or before macOS 26, which can't, grows in and shrinks away.
private struct PrivateChatCheckmark: View {
  let isChosen: Bool

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        Image(systemName: "checkmark")
          .symbolEffect(.drawOff, isActive: !self.isChosen)
      }
      else if self.isChosen {
        Image(systemName: "checkmark")
          .transition(.scale(scale: 0.3).combined(with: .opacity))
      }
    }
    .fontWeight(.semibold)
    .foregroundStyle(.tint)
    // The row says whether they're chosen.
    .accessibilityHidden(true)
  }
}

/// A field in the sheet, in a box like the people's, with a symbol saying what it's for, and the
/// tint around it while it's being typed in.
private struct PrivateChatSheetField: View {
  let systemImage: String
  let prompt: String
  @Binding var text: String

  @FocusState private var focused: Bool

  var body: some View {
    HStack(spacing: 8) {
      Image(systemName: self.systemImage)
        .foregroundStyle(.secondary)
        .frame(width: 20)
      TextField(self.prompt, text: self.$text)
        .textFieldStyle(.plain)
        .focused(self.$focused)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 9)
    .background(.fill.quaternary, in: .rect(cornerRadius: 10))
    .overlay {
      RoundedRectangle(cornerRadius: 10)
        .strokeBorder(.tint.opacity(self.focused ? 0.6 : 0), lineWidth: 2)
    }
    .animation(.easeOut(duration: 0.15), value: self.focused)
  }
}
