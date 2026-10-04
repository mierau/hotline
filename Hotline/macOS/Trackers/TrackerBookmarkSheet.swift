import SwiftUI
import SwiftData

struct TrackerBookmarkSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  
  @State private var bookmark: Bookmark? = nil
  @State private var trackerAddress: String = ""
  @State private var trackerName: String = ""
  
  init() {
    
  }
  
  init(_ editingBookmark: Bookmark) {
    _bookmark = .init(initialValue: editingBookmark)
    _trackerAddress = .init(initialValue: editingBookmark.displayAddress)
    _trackerName = .init(initialValue: editingBookmark.name)
  }
  
  var body: some View {
    VStack(alignment: .leading) {
      Form {
        if self.bookmark == nil {
          HStack(alignment: .top, spacing: 10) {
            GroupedIconView(color: .blue, systemName: "point.3.filled.connected.trianglepath.dotted", padding: 5.0)
              .frame(width: 28, height: 28)
            
            VStack(alignment: .leading) {
              Text("Add a Hotline Tracker")
              
              Text("Enter the address and name of a Hotline Tracker you want to add.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
          }
        }
        else {
          HStack(alignment: .top, spacing: 10) {
            GroupedIconView(color: .blue, systemName: "point.3.filled.connected.trianglepath.dotted", padding: 5.0)
              .frame(width: 28, height: 28)
            
            VStack(alignment: .leading) {
              Text("Edit Hotline Tracker")
              
              Text("Change the address and name of your Hotline Tracker.")
                .foregroundStyle(.secondary)
                .font(.subheadline)
            }
          }
        }
        
        Group {
          TextField(text: $trackerAddress) {
            Text("Address")
          }
          TextField(text: $trackerName, prompt: Text("Optional")) {
            Text("Name")
          }
        }
//        .textFieldStyle(.roundedBorder)
        .controlSize(.large)
      }
      .formStyle(.grouped)
    }
    .frame(width: 350)
    .fixedSize(horizontal: true, vertical: true)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button {
          self.saveTracker()
        } label: {
          if self.bookmark != nil {
            Text("Save")
          }
          else {
            Text("Add")
          }
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          self.trackerName = ""
          self.trackerAddress = ""
          
          self.dismiss()
        }
      }
    }
  }
  
  private func saveTracker() {
    var displayName = trackerName.trimmingCharacters(in: .whitespacesAndNewlines)
    let (host, port) = Tracker.parseTrackerAddressAndPort(trackerAddress)
    
    if displayName.isEmpty {
      displayName = host
    }
    
    if !displayName.isEmpty && !host.isEmpty {
      if !host.isEmpty {
        if self.bookmark != nil {
          // We're editing an existing bookmark.
          self.bookmark?.name = displayName
          self.bookmark?.address = host
          self.bookmark?.port = port
        }
        else {
          // We're creating a new bookmark.
          let newBookmark = Bookmark(type: .tracker, name: displayName, address: host, port: port)
          Bookmark.add(newBookmark, context: modelContext)
        }
        
        self.trackerName = ""
        self.trackerAddress = ""
        
        self.dismiss()
      }
    }
  }
}
