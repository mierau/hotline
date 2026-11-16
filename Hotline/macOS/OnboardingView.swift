import SwiftUI

struct OnboardingView: View {
  @Environment(\.dismissWindow) private var dismissWindow
  @Environment(\.openWindow) private var openWindow

  @State private var step: Int = 0
  @State private var username: String = Prefs.shared.username == "unnamed" ? "" : Prefs.shared.username
  @State private var selectedIconID: Int = Prefs.shared.userIconID
  @State private var hoveredIconID: Int = -1
  @State private var showUsernameAlert: Bool = false
  @State private var canScrollUp: Bool = false
  @State private var canScrollDown: Bool = true
  @State private var scrolledToIcon: Bool = false

  private let totalSteps = 3

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

      Group {
        switch self.step {
        case 0:
          self.welcomeStep
            .transition(.asymmetric(
              insertion: .move(edge: .trailing).combined(with: .opacity),
              removal: .move(edge: .leading).combined(with: .opacity)
            ))
        case 1:
          self.serversStep
            .transition(.asymmetric(
              insertion: .move(edge: .trailing).combined(with: .opacity),
              removal: .move(edge: .leading).combined(with: .opacity)
            ))
        case 2:
          self.identityStep
            .transition(.asymmetric(
              insertion: .move(edge: .trailing).combined(with: .opacity),
              removal: .move(edge: .leading).combined(with: .opacity)
            ))
        default:
          EmptyView()
        }
      }
      .id(self.step)

      Spacer()

      self.navigationArea
        .padding(.bottom, 24)
    }
    .frame(width: 420, height: 540)
    .background {
      Color.hotlineRed.ignoresSafeArea()
      RadialGradient(
        colors: [.black.opacity(0), .black.opacity(0.5)],
        center: .center,
        startRadius: 0,
        endRadius: 250
      )
      .blendMode(.softLight)
      .ignoresSafeArea()
    }
    .windowFullScreenBehavior(.disabled)
    .toolbar(removing: .title)
    .alert("Choose a Nickname", isPresented: self.$showUsernameAlert) {
      Button("OK", role: .cancel) {}
    } message: {
      Text("Please type-in a nickname for yourself before you continue.")
    }
    .background(
      WindowConfigurator { window in
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        if let btn = window.standardWindowButton(.closeButton) {
          btn.isHidden = true
        }
        if let btn = window.standardWindowButton(.zoomButton) {
          btn.isHidden = true
        }
        if let btn = window.standardWindowButton(.miniaturizeButton) {
          btn.isHidden = true
        }
      }
    )
  }

  // MARK: - Steps

  private var welcomeStep: some View {
    VStack(spacing: 0) {
      InteractiveSpinningLogo(height: 350)
        .frame(width: 200)
        .pointerStyle(.grabIdle)
    }
  }

  private var serversStep: some View {
    VStack(alignment: .leading, spacing: 16) {
      Image(systemName: "globe.americas.fill")
        .resizable()
        .scaledToFit()
        .frame(width: 48, height: 48)
        .foregroundStyle(.white.opacity(0.85))

      Text("What is Hotline?")
        .font(.system(size: 24))
        .fontWeight(.bold)
        .kerning(-0.5)
        .foregroundStyle(.white)

      Text("""
          Hotline is a network of internet communities run by individuals all over the world. Spaces where people chat, share files, and post thoughts together in newsgroups.
          
          These communities optionally make themselves discoverable through Hotline Trackers which are also independently operated.
          
          No company owns this. There is no business model. Simple and free. It's Hotline.
          """)
        .font(.system(size: 15))
        .foregroundStyle(.white.opacity(0.7))
        .multilineTextAlignment(.leading)
        .lineSpacing(3)
    }
    .padding(.horizontal, 48)
  }

  private var identityStep: some View {
    VStack(spacing: 16) {
      Text("Your Identity")
        .font(.system(size: 24))
        .fontWeight(.bold)
        .kerning(-0.5)
        .foregroundStyle(.white)

      Text("Choose a nickname and icon to represent\nyourself to others on Hotline.")
        .font(.system(size: 15))
        .foregroundStyle(.white.opacity(0.7))
        .multilineTextAlignment(.center)
        .lineSpacing(3)

      TextField("", text: self.$username, prompt: Text("Nickname").foregroundStyle(.white.opacity(0.3)))
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
          RoundedRectangle(cornerRadius: 8)
            .fill(.white.opacity(0.15))
        )
        .frame(maxWidth: 220)
        .multilineTextAlignment(.center)
        .padding(.top, 4)

      ScrollViewReader { proxy in
        ScrollView {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 40), spacing: 0)], spacing: 0) {
            ForEach(HotlineState.classicIconSet, id: \.self) { iconID in
              Image("Classic/\(iconID)")
                .resizable()
                .interpolation(.none)
                .scaledToFit()
                .frame(width: 32, height: 16)
                .frame(width: 32, height: 32)
                .padding(4)
                .background(
                  RoundedRectangle(cornerRadius: 5)
                    .fill(iconID == self.hoveredIconID ? .white.opacity(0.15) : .clear)
                )
                .overlay(
                  RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(iconID == self.selectedIconID ? .white : .clear, lineWidth: 2)
                )
                .contentShape(Rectangle())
                .id(iconID)
                .onTapGesture {
                  self.selectedIconID = iconID
                }
                .onHover { hovered in
                  if hovered {
                    self.hoveredIconID = iconID
                  }
                }
            }
          }
          .padding(.horizontal, 4)
        }
        .onAppear {
          if !self.scrolledToIcon {
            self.scrolledToIcon = true
            proxy.scrollTo(self.selectedIconID, anchor: .center)
          }
        }
      }
      .frame(maxWidth: 360, maxHeight: 230)
      .scrollContentBackground(.hidden)
      .onScrollGeometryChange(for: Bool.self) { geo in
        geo.contentOffset.y > geo.contentInsets.top + 1
      } action: { _, canUp in
        self.canScrollUp = canUp
      }
      .onScrollGeometryChange(for: Bool.self) { geo in
        let maxOffset = geo.contentSize.height - geo.containerSize.height + geo.contentInsets.top + geo.contentInsets.bottom
        return geo.contentOffset.y < maxOffset - 1
      } action: { _, canDown in
        self.canScrollDown = canDown
      }
      .overlay(alignment: .top) {
        Rectangle()
          .fill(.black.opacity(0.15))
          .frame(height: 1)
          .opacity(self.canScrollUp ? 1 : 0)
          .animation(.easeInOut(duration: 0.2), value: self.canScrollUp)
      }
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(.black.opacity(0.15))
          .frame(height: 1)
          .opacity(self.canScrollDown ? 1 : 0)
          .animation(.easeInOut(duration: 0.2), value: self.canScrollDown)
      }
    }
    .padding(.horizontal, 48)
  }

  // MARK: - Navigation

  private var buttonLabel: String {
    switch self.step {
    case 0: return "Get Started"
    case 1: return "Next"
    default: return "Done"
    }
  }

  private var navigationArea: some View {
      HStack {
        Spacer()
        
        Button {
          if self.step < self.totalSteps - 1 {
            withAnimation(.easeInOut(duration: 0.3)) {
              self.step += 1
            }
          } else {
            self.finishOnboarding()
          }
        } label: {
          Text(self.buttonLabel)
//            .fontWeight(.semibold)
//            .foregroundStyle(Color.hotlineRed)
            .padding(.vertical, 8)
            .padding(.horizontal, 28)
//            .background {
//              Capsule()
//                .fill(.white)
//            }
        }
//        .buttonStyle(.plain)
        .controlSize(.large)
        .buttonBorderShape(.capsule)
        .buttonStyle(.glassProminent)
        .tint(Color.white.opacity(0.7))
        
        Spacer()
      }
    
      .padding(.bottom, 24)
  }

  private var dotIndicators: some View {
    HStack(spacing: 8) {
      ForEach(0..<self.totalSteps, id: \.self) { index in
        Circle()
          .fill(.white.opacity(index == self.step ? 1.0 : 0.35))
          .frame(width: 7, height: 7)
      }
    }
  }

  // MARK: - Actions

  private func finishOnboarding() {
    let trimmed = self.username.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      self.showUsernameAlert = true
      return
    }

    Prefs.shared.username = trimmed
    Prefs.shared.userIconID = self.selectedIconID
    Prefs.shared.hasCompletedOnboarding = true
    Prefs.shared.showBannerToolbar = true

    self.openWindow(id: "servers")
    self.dismissWindow(id: "onboarding")
  }
}

#Preview {
  OnboardingView()
}
