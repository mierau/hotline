import SwiftUI

struct TrackerServerView: View {
  @Environment(HotlineState.self) private var appState
  @Environment(HotlineClient.self) private var hotline
  @Environment(\.dismiss) private var dismiss
  
  let server: HotlineServer
  
  var body: some View {
    @Bindable var config = appState
    
    VStack(alignment: .leading) {
      HStack {
        Text("🌎").dynamicTypeSize(.xxxLarge)
        Text(server.name!).bold().dynamicTypeSize(.xxxLarge)
      }
      .padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0))
      
      Text(server.description!).opacity(0.6).dynamicTypeSize(.xLarge).padding(EdgeInsets(top: 0, leading: 0, bottom: 8.0, trailing: 0)).textSelection(.enabled)
      Text(server.address).opacity(0.3).dynamicTypeSize(.medium).textSelection(.enabled)
      
      Spacer()
      
      HStack(alignment: .center) {
        Button("Connect") {
          hotline.connect(to: server)
          config.dismissTracker()
//          dismiss()
        }
        .bold()
        .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
        .frame(maxWidth: .infinity)
        .foregroundColor(.black)
        .background(LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom))
        .
        overlay(
          RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(0.4)
        )
        .cornerRadius(10.0)
      }
    }
    .padding(EdgeInsets(top: 28.0, leading: 24.0, bottom: 24.0, trailing: 24.0))
    .presentationDetents([.fraction(0.4)])
    .presentationDragIndicator(.automatic)
  }
}

#Preview {
  TrackerServerView(server: HotlineServer(address: "192.168.1.1", port: 5050, users: 5, name: "Ye Olde Server", description: "This is a server"))
    .environment(HotlineClient())
}
