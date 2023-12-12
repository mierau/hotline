import SwiftUI

struct TrackerConnectView: View {
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.dismiss) var dismiss
  @Environment(\.colorScheme) var colorScheme
  
  @State private var server: Server?
  @State private var address = ""
  @State private var login = ""
  @State private var password = ""
  @State private var connecting = false
  
  func connectionStatusToProgress(status: HotlineClientStatus) -> Double {
    switch status {
    case .disconnected:
      return 0.0
    case .connecting:
      return 0.1
    case .connected:
      return 0.25
    case .loggingIn:
      return 0.5
    case .loggedIn:
      return 1.0
    }
  }
  
  var body: some View {
      VStack(alignment: .leading) {
        if !connecting {
          TextField("Server Address", text: $address)
            .keyboardType(.URL)
            .disableAutocorrection(true)
            .frame(height: 48)
            .textFieldStyle(.plain)
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .background {
              Color.black.cornerRadius(8).blendMode(.overlay)
            }
          TextField("Login", text: $login)
            .disableAutocorrection(true)
            .frame(height: 48)
            .textFieldStyle(.plain)
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .background {
              Color.black.cornerRadius(8).blendMode(.overlay)
            }
          SecureField("Password", text: $password)
            .disableAutocorrection(true)
            .textFieldStyle(.plain)
            .frame(height: 48)
            .padding(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .background {
              Color.black.cornerRadius(8).blendMode(.overlay)
            }
        }
        else {
          ProgressView(value: connectionStatusToProgress(status: model.status))
            .frame(minHeight: 10)
            .accentColor(colorScheme == .dark ? .white : .black)
        }
        
        Spacer()
        
        HStack {
          Button {
            dismiss()
            server = nil
            model.disconnect()
          } label: {
            Text("Cancel")
          }
          .bold()
          .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
          .frame(maxWidth: .infinity)
          .foregroundColor(colorScheme == .dark ? .white : .black)
          .background(
            colorScheme == .dark ?
            LinearGradient(gradient: Gradient(colors: [Color(white: 0.4), Color(white: 0.3)]), startPoint: .top, endPoint: .bottom)
            :
              LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(colorScheme == .dark ? 0.0 : 0.2)
          )
          .cornerRadius(10.0)
          Button {
            let s = Server(name: address, description: nil, address: address, port: Server.defaultPort, users: 0)
            server = s
            connecting = true
            Task {
              let loggedIn = await model.login(server: s, login: login, password: password, username: "bolt", iconID: 128)
              if !loggedIn {
                connecting = false
              }
            }
          } label: {
            Text("Connect")
          }
          .disabled(connecting)
          .bold()
          .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
          .frame(maxWidth: .infinity)
          .foregroundColor(colorScheme == .dark ? .white : .black)
          .background(
            colorScheme == .dark ?
            LinearGradient(gradient: Gradient(colors: [Color(white: 0.4), Color(white: 0.3)]), startPoint: .top, endPoint: .bottom)
            :
              LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom)
          )
          .overlay(
            RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(colorScheme == .dark ? 0.0 : 0.2)
          )
          .cornerRadius(10.0)
        }
        .padding()
      }
      .padding()
      .onChange(of: model.status) {
        print("MODEL STATUS CHANGED")
        if model.server != nil && server != nil && model.server! == server! {
          if model.status == .loggedIn {
            dismiss()
          }
          else {
            connecting = (model.status != .disconnected)
          }
        }
      }
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("Connect to Server")
            .font(.headline)
        }
      }
//    .presentationBackground(.regularMaterial, in: Color(uiColor: .systemGroupedBackground))
    .presentationBackground {
      Color.clear
        .background(Material.regular)
    }
    .presentationDetents([.height(300), .large])
    .presentationDragIndicator(.visible)
    .presentationCornerRadius(20)
    //    .background(Color(uiColor: .systemGroupedBackground))
  }
}

struct TrackerView: View {
  
  //  @Environment(\.modelContext) private var modelContext
  //  @Query private var items: [Item]
  
  @Environment(Hotline.self) private var model: Hotline
  @Environment(\.colorScheme) var colorScheme
  
  //  @State private var tracker = Tracker(address: "hltracker.com", service: trackerService)
  
  @State private var servers: [Server] = []
  @State private var selectedServer: Server?
  @State private var scrollOffset: CGFloat = CGFloat.zero
  @State private var initialLoadComplete = false
  @State private var refreshing = false
  @State private var topBarOpacity: Double = 1.0
  @State private var connectVisible = false
  @State private var connectDismissed = true
  @State private var serverVisible = false
  
  func shouldDisplayDescription(server: Server) -> Bool {
    guard let desc = server.description else {
      return false
    }
    
    return desc.count > 0 && desc != server.name
  }
  
  func connectionStatusToProgress(status: HotlineClientStatus) -> Double {
    switch status {
    case .disconnected:
      return 0.0
    case .connecting:
      return 0.1
    case .connected:
      return 0.25
    case .loggingIn:
      return 0.5
    case .loggedIn:
      return 1.0
    }
  }
  
  func inverseLerp(lower: Double, upper: Double, v: Double) -> Double {
    return (v - lower) / (upper - lower)
  }
  
  func updateServers() async {
//    "hltracker.com"
//    "tracker.preterhuman.net"
//    "hotline.ubersoft.org"
//    "tracked.nailbat.com"
//    "hotline.duckdns.org"
//    "tracked.agent79.org"
    self.servers = await model.getServers(address: "hltracker.com")
  }
  
  var body: some View {
    ZStack(alignment: .center) {
      VStack(alignment: .center) {
        ZStack(alignment: .top) {
          HStack(alignment: .center) {
            Button {
              connectVisible = true
              connectDismissed = false
            } label: {
              Text(Image(systemName: "gearshape.fill"))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.primary)
                .font(.title2)
                .padding(.leading, 16)
            }
            .sheet(isPresented: $connectVisible) {
              connectDismissed = true
            } content: {
              TrackerConnectView()
            }
            Spacer()
          }
          .frame(height: 40.0)
          Image("Hotline")
            .resizable()
            .renderingMode(.template)
            .foregroundColor(Color(hex: 0xE10000))
            .scaledToFit()
            .frame(width: 40.0, height: 40.0)
          HStack(alignment: .center) {
            Spacer()
            Button {
              connectVisible = true
              connectDismissed = false
            } label: {
              Text(Image(systemName: "point.3.connected.trianglepath.dotted"))
                .symbolRenderingMode(.hierarchical)
                .foregroundColor(.primary)
                .font(.title2)
                .padding(.trailing, 16)
            }
            .sheet(isPresented: $connectVisible) {
              connectDismissed = true
            } content: {
              TrackerConnectView()
            }
          }
          .frame(height: 40.0)
        }
        .padding()
        
        Spacer()
      }
      .opacity(inverseLerp(lower: -50, upper: 0, v: scrollOffset))
      .opacity(scrollOffset > 65 ? 0.0 : 1.0)
      .opacity(topBarOpacity)
      .zIndex(scrollOffset > 0 ? 1 : 3)
      ObservableScrollView(scrollOffset: $scrollOffset) {
        LazyVStack(alignment: .leading) {
          ForEach(self.servers) { server in
            VStack(alignment: .leading) {
              HStack(alignment: .firstTextBaseline) {
                Image(systemName: "globe.americas.fill").font(.title3)
                VStack(alignment: .leading) {
                  Text(server.name).font(.title3).fontWeight(.medium)
                  if shouldDisplayDescription(server: server) {
                    Spacer()
                    Text(server.description!).opacity(0.5).font(.system(size: 16))
                  }
                  Spacer()
                  Text("\(server.address):" + String(format: "%i", server.port)).opacity(0.3).font(.system(size: 13))
                }
                Spacer()
                if server.users > 0 {
                  Text("\(server.users)").opacity(0.3).font(.system(size: 16)).fontWeight(.medium)
                }
              }
              if server == selectedServer {
                Spacer(minLength: 16)
                
                if model.status != .disconnected && model.server != nil && model.server! == server {
                  ProgressView(value: connectionStatusToProgress(status: model.status))
                    .frame(minHeight: 10)
                    .accentColor(colorScheme == .dark ? .white : .black)
                }
                else {
                  Button("Connect") {
                    Task {
                      await model.login(server: server, login: "", password: "", username: "bolt", iconID: 128)
                    }
                  }
                  .bold()
                  .padding(EdgeInsets(top: 16, leading: 24, bottom: 16, trailing: 24))
                  .frame(maxWidth: .infinity)
                  .foregroundColor(colorScheme == .dark ? .white : .black)
                  .background(
                    colorScheme == .dark ?
                    LinearGradient(gradient: Gradient(colors: [Color(white: 0.4), Color(white: 0.3)]), startPoint: .top, endPoint: .bottom)
                    :
                      LinearGradient(gradient: Gradient(colors: [Color(white: 0.95), Color(white: 0.91)]), startPoint: .top, endPoint: .bottom)
                  )
                  .overlay(
                    RoundedRectangle(cornerRadius: 10.0).stroke(.black, lineWidth: 3).opacity(colorScheme == .dark ? 0.0 : 0.2)
                  )
                  .cornerRadius(10.0)
                }
              }
            }
            .multilineTextAlignment(.leading)
            .padding()
            .background(colorScheme == .dark ? Color(white: 0.12) : .white)
            .cornerRadius(16)
            .shadow(color: Color(white: 0.0, opacity: 0.1), radius: 16, x: 0, y: 10)
            .onTapGesture {
              withAnimation(.bouncy(duration: 0.25, extraBounce: 0.2)) {
                selectedServer = server
              }
            }
          }
          .padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
        }
        .padding(EdgeInsets(top: 75, leading: 0, bottom: 0, trailing: 0))
      }
      .zIndex(2)
      .overlay {
        if !initialLoadComplete {
          VStack {
            ProgressView()
              .controlSize(.large)
          }
          .frame(maxWidth: .infinity)
        }
      }
      .refreshable {
        DispatchQueue.main.async {
          withAnimation(.easeOut(duration: 0.1)) {
            topBarOpacity = 0.0
          }
          initialLoadComplete = true
        }
        
        model.disconnectTracker()
        await updateServers()
        
        DispatchQueue.main.async {
          withAnimation(.easeOut(duration: 1.0).delay(0.75)) {
            topBarOpacity = 1.0
          }
        }
      }
      
      
    }
    .fullScreenCover(isPresented: Binding(get: { return (connectDismissed && serverVisible) }, set: { _ in }), onDismiss: {
      model.disconnect()
    }) {
      ServerView()
    }
    .onChange(of: model.status) {
      serverVisible = (model.status == .loggedIn)
    }
    .background(Color(uiColor: UIColor.systemGroupedBackground))
    .frame(maxWidth: .infinity)
    .task {
      await updateServers()
      initialLoadComplete = true
    }
    .onOpenURL(perform: { url in
      guard url.scheme == "hotline" else {
        return
      }
      
      if let address = url.host() {
        let login = url.user(percentEncoded: false) ?? ""
        let password = url.password(percentEncoded: false) ?? ""
        let port = url.port ?? Server.defaultPort
        
        Task {
          model.disconnect()
          let _ = await model.login(server: Server(name: address, description: nil, address: address, port: port, users: 0), login: login, password: password, username: "bolt", iconID: 128)
        }
        
        // TODO: Find a better way to show login status when trying to connect outside of the Tracker server list. Perhaps this opens the connect sheet prefilled.
      }
    })
  }
}

#Preview {
  TrackerView()
    .environment(Hotline(trackerClient: HotlineTrackerClient(), client: HotlineClient()))
}
