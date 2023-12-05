import SwiftUI

struct TrackerServerView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  
  let server: HotlineServer
  
  @State private var expanded = false
  
  func shouldDisplayDescription(server: HotlineServer) -> Bool {
    guard let name = server.name, let desc = server.description else {
      return false
    }
    
    return desc.count > 0 && desc != name && !desc.contains(/^-+/)
  }
  
  var body: some View {
    @Bindable var config = appState
    
    VStack(alignment: .leading) {
      HStack(alignment: .firstTextBaseline) {
        Text("🌎").font(.title3)
        VStack(alignment: .leading) {
          Text(server.name!).font(.title3).fontWeight(.medium)
          if shouldDisplayDescription(server: server) {
            Text(server.description!).opacity(0.6).font(.title3)
          }
        }
      }
      .padding()
      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
      .listRowSeparator(.hidden)
      .listRowBackground(Color(white: 0.96))

      //      .padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0))
//      ProgressView(value: 0.5)
//      
//      HStack(alignment: .center) {
//        Button("Connect") {
//          hotline.connect(to: server)
//          config.dismissTracker()
//          //          dismiss()
//        }
//        .bold()
//        .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
//        .frame(maxWidth: .infinity)
//        .foregroundColor(.black)
//        .background(LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom))
//        .overlay(
//          RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(0.4)
//        )
//        .cornerRadius(10.0)
//      }
    }
//  label: {
//      HStack(alignment: .firstTextBaseline) {
//        Text("🌎").font(.title3)
//        VStack(alignment: .leading) {
//          Text(server.name!).font(.title3).fontWeight(.medium)
//          if shouldDisplayDescription(server: server) {
//            Spacer()
//            Text(server.description!).opacity(0.6).font(.title3)
//          }
//        }
//      }
//      .padding()
//      .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
//      .listRowSeparator(.hidden)
//      .listRowBackground(Color(white: 0.96))
//    }
    .popover(isPresented: $expanded) {
      Text("Popover Content")
        .padding()
    }
    .background(Color(white: 0.96))
    .padding(EdgeInsets(top: 8.0, leading: 24.0, bottom: 8.0, trailing: 24.0))
    .presentationDetents([.fraction(0.4)])
    .presentationDragIndicator(.visible)
    .onTapGesture {
      expanded = true
//      withAnimation {
//        expanded.toggle()
//      }
    }
  }
}

#Preview {
  TrackerServerView(server: HotlineServer(address: "192.168.1.1", port: 5050, users: 5, name: "Ye Olde Server", description: "This is a server"))
    .environment(HotlineClient())
    .environment(HotlineState())
}
