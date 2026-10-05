import SwiftUI
import SceneKit

class LogoSceneController {
  var spinNode: SCNNode?
  private var decelerationTimer: Timer?
  private static let spinKey = "autoSpin"

  func beginDrag() {
    self.decelerationTimer?.invalidate()
    self.spinNode?.removeAction(forKey: Self.spinKey)
  }

  func drag(deltaX: CGFloat) {
    self.spinNode?.eulerAngles.y += CGFloat(deltaX * 0.01)
  }

  func endDrag(velocity: CGFloat) {
    var clampedVelocity = max(-1500, min(1500, velocity))
    let autoSpinVelocity: CGFloat = (.pi * 2) / (8.0 * 0.01)
    let blendRate: CGFloat = 0.06
    let interval: TimeInterval = 1.0 / 60.0

    self.decelerationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
      guard let self = self, let spinNode = self.spinNode else {
        timer.invalidate()
        return
      }

      clampedVelocity += (autoSpinVelocity - clampedVelocity) * blendRate
      spinNode.eulerAngles.y += CGFloat(clampedVelocity * CGFloat(interval) * 0.01)

      if abs(clampedVelocity - autoSpinVelocity) < 1.0 {
        timer.invalidate()
        self.startAutoSpin()
      }
    }
  }

  func startAutoSpin() {
    let spin = SCNAction.repeatForever(
      SCNAction.rotateBy(x: 0, y: .pi * 2, z: 0, duration: 8)
    )
    self.spinNode?.runAction(spin, forKey: Self.spinKey)
  }

  func startWithFastSpin() {
    let autoSpinVelocity: CGFloat = (.pi * 2) / (8.0 * 0.01)
    let initialVelocity: CGFloat = autoSpinVelocity * 4.0
    let blendRate: CGFloat = 0.04
    let interval: TimeInterval = 1.0 / 60.0

    var currentVelocity = initialVelocity

    self.decelerationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] timer in
      guard let self = self, let spinNode = self.spinNode else {
        timer.invalidate()
        return
      }

      currentVelocity += (autoSpinVelocity - currentVelocity) * blendRate
      spinNode.eulerAngles.y += CGFloat(currentVelocity * CGFloat(interval) * 0.01)

      if abs(currentVelocity - autoSpinVelocity) < 1.0 {
        timer.invalidate()
        self.startAutoSpin()
      }
    }
  }
}

struct NonDraggableArea: NSViewRepresentable {
  func makeNSView(context: Context) -> NSView {
    let view = NonDraggableNSView()
    view.wantsLayer = true
    view.layer?.backgroundColor = .clear
    return view
  }
  func updateNSView(_ nsView: NSView, context: Context) {}
}

class NonDraggableNSView: NSView {
  override var mouseDownCanMoveWindow: Bool { false }
}

struct SpinningLogoView: NSViewRepresentable {
  let controller: LogoSceneController

  func makeNSView(context: Context) -> SCNView {
    let scnView = SCNView()
    scnView.backgroundColor = .clear
    scnView.allowsCameraControl = false
    scnView.autoenablesDefaultLighting = false
    scnView.antialiasingMode = .multisampling4X

    guard let url = Bundle.main.url(forResource: "Logo", withExtension: "obj"),
          let scene = try? SCNScene(url: url) else {
      return scnView
    }
    scene.background.contents = NSColor.clear
    scnView.scene = scene

    // Reparent model nodes into a container so we can fix orientation
    let containerNode = SCNNode()
    let modelNodes = scene.rootNode.childNodes.filter { $0.light == nil }
    for node in modelNodes {
      node.removeFromParentNode()
      containerNode.addChildNode(node)
    }
    // Stand the model upright (OBJ is flat on XZ plane)
    containerNode.eulerAngles.x = -.pi / 2

    let spinNode = SCNNode()
    spinNode.addChildNode(containerNode)
    scene.rootNode.addChildNode(spinNode)
    self.controller.spinNode = spinNode

    // Apply white material with custom shading
    containerNode.enumerateChildNodes { node, _ in
      if let geometry = node.geometry {
        let material = SCNMaterial()
        material.diffuse.contents = NSColor.white
        material.lightingModel = .constant
        material.shaderModifiers = [
          .fragment: """
            vec3 viewDir = normalize(scn_frame.inverseViewTransform[3].xyz - _surface.position);
            vec3 envRed = vec3(0.882, 0.0, 0.0);
            vec3 darkRed = vec3(0.03, 0.0, 0.0);

            // Directional light
            vec3 lightDir = normalize(vec3(0.0, 0.3, 1.0));
            float NdotL = max(dot(_surface.normal, lightDir), 0.0);
            float lighting = smoothstep(0.0, 0.8, NdotL);

            // Vertical gradient — subtle darkening toward the bottom
            float height = _surface.position.y;
            float verticalFade = smoothstep(-2.0, 2.0, height);
            lighting *= mix(0.92, 1.0, verticalFade);

            // Fresnel — plastic reflects strongly at glancing angles
            float fresnel = 1.0 - max(dot(_surface.normal, viewDir), 0.0);
            float fresnelSharp = pow(fresnel, 3.0);
            float fresnelSoft = pow(fresnel, 1.5);

            // Ambient red from environment — even lit areas pick up warmth
            vec3 ambient = envRed * 0.08;

            // Base: lit areas are tinted white, unlit areas are dark red
            vec3 baseColor = mix(darkRed, vec3(1.0), lighting) + ambient;

            // Tint lower areas with environment red
            float redTint = (1.0 - verticalFade) * 0.65;
            baseColor = mix(baseColor, envRed, redTint * lighting);

            // Environment red at edges (fresnel reflection)
            baseColor = mix(baseColor, envRed, fresnelSharp * 0.8);

            // Broad plastic sheen — soft diffuse highlight
            vec3 halfVec = normalize(lightDir + viewDir);
            float sheen = pow(max(dot(_surface.normal, halfVec), 0.0), 6.0);
            baseColor += vec3(1.0) * sheen * 0.15;

            // Subtle specular — not too shiny
            float spec = pow(max(dot(_surface.normal, halfVec), 0.0), 50.0);
            baseColor += vec3(1.0) * spec * 0.25;

            // Soft rim light — plastic catches environment at edges
            baseColor += envRed * fresnelSoft * 0.1;

            _output.color.rgb = baseColor;
          """
        ]
        geometry.materials = [material]
      }
    }

    // Start with a fast spin that decelerates to natural speed
    self.controller.startWithFastSpin()

    // Camera — pulled back to avoid clipping
    let cameraNode = SCNNode()
    cameraNode.camera = SCNCamera()
    cameraNode.camera!.fieldOfView = 65
    cameraNode.position = SCNVector3(0, 0, 6)
    cameraNode.look(at: SCNVector3Zero)
    scene.rootNode.addChildNode(cameraNode)
    scnView.pointOfView = cameraNode

    // Directional light from camera direction
    let directionalLight = SCNNode()
    directionalLight.light = SCNLight()
    directionalLight.light!.type = .directional
    directionalLight.light!.intensity = 1000
    directionalLight.light!.color = NSColor.white
    directionalLight.eulerAngles = SCNVector3(0, 0, 0)
    scene.rootNode.addChildNode(directionalLight)

    return scnView
  }

  func updateNSView(_ nsView: SCNView, context: Context) {}
}

struct InteractiveSpinningLogo: View {
  @State var controller = LogoSceneController()
  @State private var lastDragX: CGFloat = 0
  @State private var lastDragTime: TimeInterval = 0
  @State private var dragVelocity: CGFloat = 0

  var height: CGFloat = 220

  var body: some View {
    SpinningLogoView(controller: self.controller)
      .frame(height: self.height)
      .overlay {
        NonDraggableArea()
      }
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            let now = ProcessInfo.processInfo.systemUptime
            let dt = now - self.lastDragTime
            if dt > 0 && self.lastDragTime > 0 {
              self.dragVelocity = (value.location.x - self.lastDragX) / CGFloat(dt)
            }
            let deltaX = value.location.x - self.lastDragX
            if self.lastDragX != 0 {
              self.controller.drag(deltaX: deltaX)
            } else {
              self.controller.beginDrag()
            }
            self.lastDragX = value.location.x
            self.lastDragTime = now
          }
          .onEnded { _ in
            self.controller.endDrag(velocity: self.dragVelocity)
            self.lastDragX = 0
            self.lastDragTime = 0
            self.dragVelocity = 0
          }
      )
  }
}

// MARK: - Banner Logo

/// The red Hotline H for the default banner, as a slowly spinning 3D model on a transparent background.
struct SpinningBannerLogo: NSViewRepresentable {
  var interaction: BannerLogoView.Interaction = .clickToSpin
  /// How much closer in to frame the H. 1 is the banner's own framing.
  var zoom: CGFloat = 1

  func makeNSView(context: Context) -> BannerLogoView {
    BannerLogoView(interaction: self.interaction, zoom: self.zoom)
  }

  func updateNSView(_ nsView: BannerLogoView, context: Context) {}
}

final class BannerLogoView: SCNView, SCNSceneRendererDelegate {
  /// What pressing on the logo does.
  enum Interaction {
    /// A click spins the logo. Pressing and moving drags the window, like the rest of the banner.
    case clickToSpin
    /// Dragging turns the logo by hand, and once let go it coasts back into its regular spin. A
    /// click spins it, the same as in the banner.
    case dragToSpin
  }

  /// One full turn, in seconds.
  private static let spinDuration: TimeInterval = 12
  /// Turned slightly to show its left side, the way the old banner artwork drew the H.
  private static let restingAngle: CGFloat = -20 * .pi / 180
  /// How far dragging turns the logo, in radians for each point the pointer moves.
  private static let dragRadiansPerPoint: Double = 0.01
  /// The fastest it can be flung, in radians a second. Nearly two and a half turns a second.
  private static let fastestFling: Double = 15
  private static let spinKey = "spin"

  private let interaction: Interaction
  private var spinNode: SCNNode?

  init(interaction: Interaction = .clickToSpin, zoom: CGFloat = 1) {
    self.interaction = interaction
    super.init(frame: .zero, options: nil)
    self.backgroundColor = .clear
    self.antialiasingMode = .multisampling4X
    // A slow spin looks just as smooth at 30 fps, at well under half the cost of 60.
    self.preferredFramesPerSecond = 30
    self.setAccessibilityElement(false)

    guard let (scene, spinNode, camera) = Self.makeScene() else {
      return
    }
    self.scene = scene
    self.pointOfView = camera
    self.spinNode = spinNode
    // A narrower view from the same spot crops in on the H without changing its perspective.
    if zoom != 1, let lens = camera.camera {
      let halfAngle = lens.fieldOfView / 2 * .pi / 180
      lens.fieldOfView = 2 * atan(tan(halfAngle) / zoom) * 180 / .pi
    }
    spinNode.eulerAngles.y = Self.restingAngle

    if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
      self.startSteadySpin()
    }

    // SceneKit takes a moment to draw its first frame (up to about 160 ms in a fresh launch), so
    // start invisible and fade in once it has, rather than popping in.
    self.alphaValue = 0
    self.delegate = self
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  // MARK: Fading In

  // Called on SceneKit's rendering thread after every frame, until the first one fades in.
  nonisolated func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
    DispatchQueue.main.async { [weak self] in
      guard let self, self.delegate != nil else {
        return
      }
      self.delegate = nil
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.3
        self.animator().alphaValue = 1
      }
    }
  }

  // MARK: Spinning

  private static var steadySpin: SCNAction {
    .repeatForever(.rotateBy(x: 0, y: .pi * 2, z: 0, duration: Self.spinDuration))
  }

  private func startSteadySpin() {
    self.spinNode?.runAction(Self.steadySpin, forKey: Self.spinKey)
  }

  /// A few quick turns that ease back into the regular spin.
  private func spinQuickly() {
    self.spin(from: 2.5 * 2 * .pi)
  }

  /// Turns at a speed, in radians a second, that eases back into the regular spin. Backwards too.
  private func spin(from speed: Double) {
    guard let spinNode = self.spinNode, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      self.preferredFramesPerSecond = 30
      return
    }

    // Let the difference from the regular speed fall away exponentially, so it settles into the
    // regular spin without a jolt. After 5 seconds less than 1% of it is left.
    let steadySpeed = 2 * Double.pi / Self.spinDuration
    let falloff = 1.0
    let duration = 5 * falloff
    func angle(at time: Double) -> Double {
      steadySpeed * time + (speed - steadySpeed) * falloff * (1 - exp(-time / falloff))
    }

    // Turned a step at a time from wherever it is, so taking over from another spin doesn't jump,
    // and the steady spin can pick up right where this ends.
    var turned = 0.0
    let boost = SCNAction.customAction(duration: duration) { node, elapsed in
      let total = angle(at: Double(elapsed))
      node.eulerAngles.y += CGFloat(total - turned)
      turned = total
    }

    let backToSlowerFrameRate = SCNAction.run { [weak self] _ in
      DispatchQueue.main.async { [weak self] in
        self?.preferredFramesPerSecond = 30
      }
    }

    // Smooth while it's fast. The steady spin follows inside SceneKit, so there's no hitch between
    // them, and a click during the boost replaces the whole sequence.
    self.preferredFramesPerSecond = 60
    spinNode.runAction(.sequence([boost, backToSlowerFrameRate, Self.steadySpin]), forKey: Self.spinKey)
  }

  // MARK: Clicks

  // The panel never becomes key, so take the first click instead of ignoring it.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override var mouseDownCanMoveWindow: Bool {
    self.interaction == .dragToSpin ? false : super.mouseDownCanMoveWindow
  }

  override func mouseDown(with event: NSEvent) {
    guard let window = self.window else {
      return
    }
    switch self.interaction {
    case .clickToSpin:
      // A click spins the logo. Pressing and moving drags the panel, like the rest of the banner.
      let start = event.locationInWindow
      while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
        if next.type == .leftMouseUp {
          self.spinQuickly()
          return
        }
        let location = next.locationInWindow
        if hypot(location.x - start.x, location.y - start.y) > 3 {
          window.performDrag(with: event)
          return
        }
      }
    case .dragToSpin:
      self.turnByHand(from: event, in: window)
    }
  }

  /// Turns the logo along with the pointer until the mouse comes up, then lets it coast at the speed
  /// it was let go. A click without a drag spins it quickly instead.
  private func turnByHand(from event: NSEvent, in window: NSWindow) {
    guard let spinNode = self.spinNode else {
      return
    }
    let start = event.locationInWindow
    var last = start
    var lastTime = event.timestamp
    var speed: Double = 0
    var turning = false
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
      if next.type == .leftMouseUp {
        // Held still before letting go, so it was let go at rest.
        if next.timestamp - lastTime > 0.1 {
          speed = 0
        }
        break
      }
      let location = next.locationInWindow
      if !turning {
        guard hypot(location.x - start.x, location.y - start.y) > 3 else {
          continue
        }
        turning = true
        spinNode.removeAction(forKey: Self.spinKey)
        self.preferredFramesPerSecond = 60
        NSCursor.closedHand.push()
      }
      let angle = Double(location.x - last.x) * Self.dragRadiansPerPoint
      spinNode.eulerAngles.y += CGFloat(angle)
      let elapsed = next.timestamp - lastTime
      if elapsed > 0 {
        // Smoothed a little, since the pointer doesn't move evenly from one event to the next.
        speed = 0.5 * speed + 0.5 * angle / elapsed
      }
      last = location
      lastTime = next.timestamp
    }

    guard turning else {
      self.spinQuickly()
      return
    }
    NSCursor.pop()
    self.spin(from: min(max(speed, -Self.fastestFling), Self.fastestFling))
  }

  // MARK: Visibility

  // Only render while the panel is actually on screen.
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
    if let window = self.window {
      NotificationCenter.default.addObserver(self, selector: #selector(self.occlusionChanged), name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }
    self.occlusionChanged()
  }

  @objc private func occlusionChanged() {
    // Pausing the view alone doesn't stop the spin's action, so SceneKit kept drawing (about 2.5% CPU)
    // while hidden. Pausing the node stops it too, and the last frame stays up for when the panel
    // comes back.
    let visible = self.window?.occlusionState.contains(.visible) == true
    self.spinNode?.isPaused = !visible
    self.isPlaying = visible
  }

  private static func makeScene() -> (scene: SCNScene, spinNode: SCNNode, camera: SCNNode)? {
    guard let url = Bundle.main.url(forResource: "Logo", withExtension: "obj"),
          let scene = try? SCNScene(url: url) else {
      return nil
    }
    scene.background.contents = NSColor.clear

    // Stand the model upright (the OBJ lies flat on the XZ plane) inside a node we can spin.
    let containerNode = SCNNode()
    for node in scene.rootNode.childNodes.filter({ $0.light == nil }) {
      node.removeFromParentNode()
      containerNode.addChildNode(node)
    }
    containerNode.eulerAngles.x = -.pi / 2
    let spinNode = SCNNode()
    spinNode.addChildNode(containerNode)
    scene.rootNode.addChildNode(spinNode)

    // The red of the old artwork's H, with a small glint that slides across the faces as it turns.
    let material = SCNMaterial()
    material.lightingModel = .blinn
    material.diffuse.contents = NSColor(srgbRed: 0.82, green: 0.0, blue: 0.004, alpha: 1)
    material.specular.contents = NSColor(white: 0.45, alpha: 1)
    material.shininess = 0.75
    containerNode.enumerateChildNodes { node, _ in
      node.geometry?.materials = [material]
    }

    // Framed so the H is about as tall as the one in the old artwork.
    let camera = SCNNode()
    camera.camera = SCNCamera()
    camera.camera!.fieldOfView = 28
    camera.position = SCNVector3(0, 0, 17)
    scene.rootNode.addChildNode(camera)

    // Key light up and to the right in front, so the left sides fall into shadow like the old artwork.
    let key = SCNNode()
    key.light = SCNLight()
    key.light!.type = .omni
    key.light!.intensity = 1150
    key.position = SCNVector3(4, 5, 9)
    scene.rootNode.addChildNode(key)

    // Dim fill, so faces turned away are deep red instead of black.
    let fill = SCNNode()
    fill.light = SCNLight()
    fill.light!.type = .ambient
    fill.light!.intensity = 100
    scene.rootNode.addChildNode(fill)

    // Faint rim light from behind on the left, so edges catch light as they come around.
    let rim = SCNNode()
    rim.light = SCNLight()
    rim.light!.type = .directional
    rim.light!.intensity = 300
    rim.eulerAngles = SCNVector3(-0.3, -2.4, 0)
    scene.rootNode.addChildNode(rim)

    return (scene, spinNode, camera)
  }
}
