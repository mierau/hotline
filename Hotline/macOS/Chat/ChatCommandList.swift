#if os(macOS)
import SwiftUI

/// The list above the chat's field while a command's being typed: the commands that fit what's
/// typed of one, or the people it could be for, to choose from with the arrow keys and Tab or
/// Return, or a click; and when Return finds something wrong with what's typed, what, with what
/// could be meant instead. Not on the main actor, as the field's text view's delegate, which runs it,
/// isn't, though it's only ever used there.
@Observable
final class ChatCommandList {
  /// A row in the list.
  enum Row: Identifiable, Equatable {
    /// A command, to put in for what's typed of its name.
    case command(ChatCommand)
    /// Someone, to put in for what's typed of their name.
    case person(User)
    /// A command what was typed might have been meant as.
    case suggestion(ChatCommand)
    /// What was typed, to send as a message after all.
    case message(String)
    /// An icon, by its number, to change yours to.
    case icon(Int)

    var id: String {
      switch self {
      case .command(let command):
        return "command \(command.rawValue)"
      case .person(let user):
        return "person \(user.id)"
      case .suggestion(let command):
        return "suggestion \(command.rawValue)"
      case .message:
        return "message"
      case .icon(let iconID):
        return "icon \(iconID)"
      }
    }

    /// The same row, showing the same: someone with the same name, icon and status, too.
    static func == (lhs: Row, rhs: Row) -> Bool {
      if case .person(let a) = lhs, case .person(let b) = rhs {
        return a.id == b.id && a.name == b.name && a.iconID == b.iconID && a.status == b.status
      }
      return lhs.id == rhs.id
    }
  }

  private(set) var rows: [Row] = []
  /// The row Tab and Return choose.
  private(set) var selection = 0
  /// What's wrong with what was typed, as Return found it, until it's changed.
  private(set) var problem: String?
  /// Whether it's for a private chat, where some commands do what they do there.
  private(set) var inPrivateChat = false
  /// Chooses a row that's clicked, in the field the list is for.
  @ObservationIgnored var choose: ((Int) -> Void)?

  var isShown: Bool {
    !self.rows.isEmpty || self.problem != nil
  }

  /// Whether it's icons, which are in a grid.
  var isGrid: Bool {
    if case .icon = self.rows.first {
      return true
    }
    return false
  }
  /// How many icons are across the grid, as many as fit, up to `maxIconColumns`, for the arrows to
  /// go up and down by. Set by the grid, as it's laid out.
  @ObservationIgnored var iconColumns = ChatCommandList.maxIconColumns
  static let maxIconColumns = 10

  /// Shows rows, and what's wrong, if anything, with the first row selected, or the one given, unless
  /// they're the rows it's showing, which keep the one that is.
  func show(_ rows: [Row], problem: String? = nil, inPrivateChat: Bool, selecting: Row? = nil) {
    if rows != self.rows {
      self.rows = rows
      self.selection = selecting.flatMap { rows.firstIndex(of: $0) } ?? 0
    }
    if problem != self.problem {
      self.problem = problem
    }
    if inPrivateChat != self.inPrivateChat {
      self.inPrivateChat = inPrivateChat
    }
  }

  func hide() {
    self.show([], inPrivateChat: self.inPrivateChat)
  }

  /// Selects the row above or below, stopping at the top and bottom, as menus do, or in a grid, the
  /// icon beside, above, or below, staying put at its edges.
  func move(by offset: Int) {
    let next = self.selection + offset
    guard !self.rows.isEmpty, !self.isGrid || self.rows.indices.contains(next) else {
      return
    }
    self.selection = min(max(next, 0), self.rows.count - 1)
  }
}

/// The list, floating over the bottom of the chat, just above its field, with its rows' text where
/// the field's starts.
struct ChatCommandListView: View {
  let list: ChatCommandList

  /// How wide the list is, as wide as there's room for, up to its widest, for how many icons fit
  /// across.
  @State private var width: CGFloat = 420

  /// How tall a row is, and how many show before the rest scroll: all the commands there are in a
  /// private chat, and fewer where there isn't the room.
  static let rowHeight: CGFloat = 26
  private static let visibleRows = 10

  var body: some View {
    // Here, rather than in the chat, so only the list's drawn again as it changes.
    ZStack(alignment: .bottomLeading) {
      if self.list.isShown {
        self.panel
          .transition(.opacity.combined(with: .offset(y: 4)))
      }
    }
    .animation(.easeOut(duration: 0.12), value: self.list.isShown)
  }

  private var panel: some View {
    VStack(alignment: .leading, spacing: 0) {
      if let problem = self.list.problem {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Image(systemName: "exclamationmark.circle.fill")
            .foregroundStyle(.red)
          Text(problem)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
      }
      if self.list.isGrid {
        self.icons
      }
      else if !self.list.rows.isEmpty {
        self.rows
      }
    }
    .font(.system(size: NSFont.systemFontSize))
    .padding(4)
    .frame(maxWidth: 420, alignment: .leading)
    .onGeometryChange(for: CGFloat.self) { proxy in
      proxy.size.width
    } action: { width in
      self.width = width
    }
    .background(.regularMaterial, in: .rect(cornerRadius: 10, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(.separator, lineWidth: 0.5)
    }
    .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
  }

  private var rows: some View {
    ScrollViewReader { proxy in
      ScrollView(.vertical) {
        // Made as they're scrolled to, for everyone on a busy server.
        LazyVStack(spacing: 0) {
          ForEach(Array(self.list.rows.enumerated()), id: \.element.id) { index, row in
            ChatCommandRowView(row: row, selected: index == self.list.selection, inPrivateChat: self.list.inPrivateChat)
              .id(row.id)
              .onTapGesture {
                self.list.choose?(index)
              }
          }
        }
      }
      .scrollIndicators(self.list.rows.count > Self.visibleRows ? .automatic : .hidden)
      // As tall as its rows, up to how many show at once, or the room there is above the field.
      .frame(maxHeight: CGFloat(min(self.list.rows.count, Self.visibleRows)) * Self.rowHeight)
      // The selected row in view, as the arrow keys move it past the ones showing.
      .onChange(of: self.list.selection) { _, selection in
        if self.list.rows.indices.contains(selection) {
          proxy.scrollTo(self.list.rows[selection].id)
        }
      }
    }
  }

  /// How big an icon's place in the grid is, and how many rows of them show before the rest scroll.
  static let iconCell = CGSize(width: 40, height: 30)
  private static let visibleIconRows = 5

  /// The icons, in a grid, as Settings has them, with yours, or the one whose number's typed, chosen
  /// to begin with, and in view.
  private var icons: some View {
    let icons = self.list.rows.compactMap { row -> Int? in
      if case .icon(let iconID) = row {
        return iconID
      }
      return nil
    }
    // As many across as fit inside the list's padding.
    let columns = max(1, min(ChatCommandList.maxIconColumns, Int((self.width - 8) / Self.iconCell.width)))
    let gridRows = (icons.count + columns - 1) / columns
    return ScrollViewReader { proxy in
      ScrollView(.vertical) {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.iconCell.width), spacing: 0), count: columns), spacing: 0) {
          ForEach(Array(icons.enumerated()), id: \.element) { index, iconID in
            ChatCommandIconView(iconID: iconID, selected: index == self.list.selection)
              .id(iconID)
              .onTapGesture {
                self.list.choose?(index)
              }
          }
        }
      }
      .scrollIndicators(gridRows > Self.visibleIconRows ? .automatic : .hidden)
      .frame(maxHeight: CGFloat(min(gridRows, Self.visibleIconRows)) * Self.iconCell.height)
      .onChange(of: columns, initial: true) { _, columns in
        self.list.iconColumns = columns
      }
      .onAppear {
        if icons.indices.contains(self.list.selection) {
          proxy.scrollTo(icons[self.list.selection], anchor: .center)
        }
      }
      .onChange(of: self.list.selection) { _, selection in
        if icons.indices.contains(selection) {
          proxy.scrollTo(icons[selection])
        }
      }
    }
  }
}

/// An icon in the grid, as Settings has them: its number when the pointer's over it, and the
/// selected one on the color the server's lists have.
private struct ChatCommandIconView: View {
  let iconID: Int
  let selected: Bool

  @Environment(\.serverTheme) private var theme
  @State private var hovered = false

  var body: some View {
    Image("Classic/\(self.iconID)")
      .resizable()
      .interpolation(.none)
      .scaledToFit()
      .frame(width: 32, height: 16)
      .frame(width: ChatCommandListView.iconCell.width, height: ChatCommandListView.iconCell.height)
      .background {
        if self.selected {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(self.theme?.selection.map { Color(nsColor: $0) } ?? Color(nsColor: .selectedContentBackgroundColor))
        }
        else if self.hovered {
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.primary.opacity(0.06))
        }
      }
      .contentShape(.rect)
      .onHover { hovered in
        self.hovered = hovered
      }
      .help("Icon \(String(self.iconID))")
      .accessibilityElement()
      .accessibilityLabel("Icon \(String(self.iconID))")
      .accessibilityAddTraits(self.selected ? [.isButton, .isSelected] : .isButton)
  }
}

/// A row in the list: a command, what goes after its name, and what it does; or someone, as the
/// user list has them; or what was typed, to send after all.
private struct ChatCommandRowView: View {
  let row: ChatCommandList.Row
  let selected: Bool
  let inPrivateChat: Bool

  @Environment(\.serverTheme) private var theme
  @State private var hovered = false

  var body: some View {
    HStack(spacing: 6) {
      switch self.row {
      case .command(let command), .suggestion(let command):
        Text(command.name)
          .fontWeight(.medium)
        Text(command.placeholder(inPrivateChat: self.inPrivateChat))
          .foregroundStyle(self.selected ? AnyShapeStyle(Color.white.opacity(0.65)) : AnyShapeStyle(.tertiary))
        Spacer(minLength: 16)
        Text(command.summary(inPrivateChat: self.inPrivateChat))
          .foregroundStyle(self.selected ? AnyShapeStyle(Color.white.opacity(0.85)) : AnyShapeStyle(.secondary))
      case .person(let user):
        // Fainter while they're idle, as the user list has them.
        HStack(spacing: 5) {
          UserIconView(iconID: Int(user.iconID))
            .padding(.horizontal, 2)
          Text(user.name.hidingOffensiveWords)
            .foregroundStyle(self.selected ? AnyShapeStyle(Color.white) : user.isAdmin ? AnyShapeStyle(.serverAdmin) : AnyShapeStyle(.primary))
        }
        .opacity(user.isIdle ? 0.5 : 1)
        Spacer(minLength: 16)
      case .message:
        Image(systemName: "arrow.up.circle")
        Text("Send as a message")
        Spacer(minLength: 16)
      case .icon(let iconID):
        // In the grid, rather than a row, but for the odd one.
        UserIconView(iconID: iconID)
        Text(String(iconID))
        Spacer(minLength: 16)
      }
    }
    .lineLimit(1)
    .foregroundStyle(self.selected ? AnyShapeStyle(Color.white) : AnyShapeStyle(.primary))
    .padding(.horizontal, 8)
    .frame(height: ChatCommandListView.rowHeight)
    .background {
      if self.selected {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(self.selectionColor)
      }
      else if self.hovered {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(.primary.opacity(0.06))
      }
    }
    .contentShape(.rect)
    .onHover { hovered in
      self.hovered = hovered
    }
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(self.selected ? [.isButton, .isSelected] : .isButton)
  }

  /// Selected rows' color, as the server's lists have it, or the system's.
  private var selectionColor: Color {
    self.theme?.selection.map { Color(nsColor: $0) } ?? Color(nsColor: .selectedContentBackgroundColor)
  }
}
#endif
