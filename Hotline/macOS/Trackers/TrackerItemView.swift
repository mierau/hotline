import SwiftUI

struct TrackerItemView: View {
  let bookmark: Bookmark
  let isExpanded: Bool
  let isLoading: Bool
  let count: Int
  let onToggleExpanded: () -> Void
  @Environment(\.appearsActive) private var appearsActive

  var body: some View {
    HStack(alignment: .center, spacing: 6) {
      if bookmark.type == .tracker {
        Button {
          self.onToggleExpanded()
        } label: {
          Text(Image(systemName: self.isExpanded ? "chevron.down" : "chevron.right"))
            .bold()
            .font(.system(size: 10))
            .opacity(0.5)
            .frame(alignment: .center)
        }
        .buttonStyle(.plain)
        .frame(width: 10)
        .padding(.leading, 4)
        .padding(.trailing, 2)
      }

      switch bookmark.type {
      case .tracker:
        Image("Tracker")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16, alignment: .center)
        Text(bookmark.name).bold().lineLimit(1).truncationMode(.tail)
        if isLoading {
          ProgressView()
            .padding([.leading, .trailing], 2)
            .controlSize(.mini)
        }
        Spacer(minLength: 0)
        if isExpanded && count > 0 {
          HStack(spacing: 4) {
            Text(String(count))

            SpinningGlobeView()
              .fontWeight(.semibold)
              .frame(width: 12, height: 12)
          }
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .foregroundStyle(.secondary)
//          .background(.quinary)
          .clipShape(.capsule)
        }
      case .server:
        Image(systemName: "bookmark.fill")
          .resizable()
          .scaledToFit()
          .foregroundStyle(Color.secondary)
          .frame(width: 11, height: 11, alignment: .center)
          .opacity(0.75)
          .padding(.leading, 3)
          .padding(.trailing, 2)
        Image("Server")
          .resizable()
          .scaledToFit()
          .frame(width: 16, height: 16, alignment: .center)
        Text(bookmark.name).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// In place of a tracker's servers, when it couldn't be reached, or stopped answering, with a
/// button to ask it again.
struct TrackerUnreachableRow: View {
  let bookmark: Bookmark
  let reconnect: () -> Void

  /// Where the tracker is, with its port, when it isn't the usual one.
  private var address: String {
    self.bookmark.port == HotlinePorts.DefaultTrackerPort ? self.bookmark.address : "\(self.bookmark.address):\(self.bookmark.port)"
  }

  var body: some View {
    HStack(spacing: 6) {
      Text("Could not connect to tracker: \(self.address)")
        .italic()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 0)
      Button(action: self.reconnect) {
        Image(systemName: "arrow.clockwise")
      }
      .buttonStyle(.borderless)
      .controlSize(.small)
      .help("Reconnect")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
