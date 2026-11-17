import SwiftUI
import SceneKit
import Metal

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
  /// What pressing on the logo does.
  enum Interaction {
    /// A click spins the logo. Pressing and moving drags the window, like the rest of the banner.
    case clickToSpin
    /// Dragging turns the logo by hand, and once let go it coasts back into its regular spin. A
    /// click spins it, the same as in the banner.
    case dragToSpin
  }

  var interaction: Interaction = .clickToSpin
  /// How much closer in to frame the H. 1 is the banner's own framing.
  var zoom: CGFloat = 1

  func makeNSView(context: Context) -> NSView {
    switch self.interaction {
    case .clickToSpin:
      // Played from frames drawn once, since the banner shows it for as long as there's no server banner.
      PlayedBannerLogoView(zoom: self.zoom)
    case .dragToSpin:
      // Drawn as it turns, so it can follow the pointer.
      BannerLogoView(zoom: self.zoom)
    }
  }

  func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The H drawn by SceneKit as it turns, so dragging can turn it by hand. Once let go it coasts back
/// into its regular spin, and a click spins it, the same as in the banner.
final class BannerLogoView: SCNView, SCNSceneRendererDelegate {
  /// One full turn, in seconds.
  nonisolated static let spinDuration: TimeInterval = 12
  /// Turned slightly to show its left side, the way the old banner artwork drew the H.
  nonisolated static let restingAngle: CGFloat = -20 * .pi / 180
  /// How far dragging turns the logo, in radians for each point the pointer moves.
  private static let dragRadiansPerPoint: Double = 0.01
  /// The fastest it can be flung, in radians a second. Nearly two and a half turns a second.
  private static let fastestFling: Double = 15
  private static let spinKey = "spin"

  private var spinNode: SCNNode?

  init(zoom: CGFloat = 1) {
    super.init(frame: .zero, options: nil)
    self.backgroundColor = .clear
    self.antialiasingMode = .multisampling4X
    // A slow spin looks just as smooth at 30 fps, at well under half the cost of 60.
    self.preferredFramesPerSecond = 30
    self.setAccessibilityElement(false)

    guard let (scene, spinNode, camera) = Self.makeScene(zoom: zoom) else {
      return
    }
    self.scene = scene
    self.pointOfView = camera
    self.spinNode = spinNode
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
    self.spin(from: BannerLogoTurn.quickSpeed)
  }

  /// Turns at a speed, in radians a second, that eases back into the regular spin. Backwards too.
  private func spin(from speed: Double) {
    guard let spinNode = self.spinNode, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      self.preferredFramesPerSecond = 30
      return
    }

    let turn = BannerLogoTurn(begin: 0, angle: 0, speed: speed)

    // Turned a step at a time from wherever it is, so taking over from another spin doesn't jump,
    // and the steady spin can pick up right where this ends.
    var turned = 0.0
    let boost = SCNAction.customAction(duration: BannerLogoTurn.easing) { node, elapsed in
      let total = turn.angle(at: Double(elapsed))
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

  // Turned from the first click, even in a window that isn't in front.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override var mouseDownCanMoveWindow: Bool {
    false
  }

  override func mouseDown(with event: NSEvent) {
    guard let window = self.window else {
      return
    }
    self.turnByHand(from: event, in: window)
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

  // Only render while its window is actually on screen.
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
    // while hidden. Pausing the node stops it too, and the last frame stays up for when the window
    // comes back.
    let visible = self.window?.occlusionState.contains(.visible) == true
    self.spinNode?.isPaused = !visible
    self.isPlaying = visible
  }

  /// The H standing upright in a node that turns it, lit, and a camera framing it, `zoom` times closer.
  nonisolated static func makeScene(zoom: CGFloat = 1) -> (scene: SCNScene, spinNode: SCNNode, camera: SCNNode)? {
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
    // A narrower view from the same spot crops in on the H without changing its perspective.
    if zoom != 1, let lens = camera.camera {
      let halfAngle = lens.fieldOfView / 2 * .pi / 180
      lens.fieldOfView = 2 * atan(tan(halfAngle) / zoom) * 180 / .pi
    }

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

// MARK: - Banner Logo, Played

/// How the banner's H turns from a moment on: from an angle, at a speed that eases into its steady
/// turn, once every 12 seconds.
struct BannerLogoTurn {
  /// Radians a second.
  static let steadySpeed = 2 * Double.pi / BannerLogoView.spinDuration
  /// A click's spin: two and a half turns a second.
  static let quickSpeed = 2.5 * 2 * Double.pi
  /// How long a faster or slower turn takes to settle into the steady one, by when less than 1% of
  /// the difference in speed is left.
  static let easing: TimeInterval = 5

  /// When it begins, in the time of the layer it plays in.
  var begin: CFTimeInterval
  /// Radians past the resting angle.
  var angle: Double
  /// Radians a second, at the beginning.
  var speed: Double

  var isSteady: Bool { self.speed == Self.steadySpeed }

  /// The difference from the steady speed falls away exponentially, a second at a time, so it
  /// settles into the steady turn without a jolt.
  func angle(at time: CFTimeInterval) -> Double {
    let elapsed = max(0, time - self.begin)
    return self.angle + Self.steadySpeed * elapsed + (self.speed - Self.steadySpeed) * (1 - exp(-min(elapsed, Self.easing)))
  }
}

/// The banner's H, turning as `BannerLogoView` turns it, from frames SceneKit draws once, a degree
/// apart, which the window server plays.
///
/// Drawn by SceneKit 30 times a second, for as long as the banner showed it, the H took about 4%
/// CPU and over 100 MB. Played by Core Animation, the app does nothing from one frame to the next,
/// and the frames take 5 MB. A click spins it quickly, with the frame nearest its angle for each
/// 60th of a second.
final class PlayedBannerLogoView: NSView {
  private let zoom: CGFloat
  private let framesLayer = CALayer()
  private var frames: BannerLogoFrames?
  /// The frames being drawn, and for what.
  private var drawing: (key: BannerLogoFrames.Key, task: Task<Void, Never>)?
  private var turn = BannerLogoTurn(begin: 0, angle: 0, speed: BannerLogoTurn.steadySpeed)
  /// The frames last drawn, for an H shown again with the same ones, while any H still shows them.
  private static weak var lastFrames: BannerLogoFrames?

  init(zoom: CGFloat = 1) {
    self.zoom = zoom
    super.init(frame: .zero)
    self.wantsLayer = true
    // Placed and played without animations of its own.
    self.framesLayer.actions = ["bounds": NSNull(), "position": NSNull(), "contents": NSNull()]
    self.framesLayer.contentsGravity = .resize
    self.layer?.addSublayer(self.framesLayer)
    self.setAccessibilityElement(false)
    // Fades in once its frames are drawn, rather than popping in.
    self.alphaValue = 0
  }

  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    self.needsLayout = true
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    // On a screen with another scale or other colors, the frames are drawn again for it.
    self.needsLayout = true
  }

  override func layout() {
    super.layout()
    self.drawFrames()
  }

  // MARK: Frames

  /// What the frames are drawn for: where it's shown now.
  private var key: BannerLogoFrames.Key? {
    guard let window = self.window, self.bounds.width > 0, self.bounds.height > 0 else {
      return nil
    }
    return BannerLogoFrames.Key(
      size: self.bounds.size,
      scale: window.backingScaleFactor,
      zoom: self.zoom,
      colorSpace: window.colorSpace?.cgColorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!,
      // Without motion, just the H at rest.
      count: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 360
    )
  }

  /// Draws the frames off the main thread, unless they're drawn already, then plays them.
  private func drawFrames() {
    guard let key = self.key, key != self.frames?.key, key != self.drawing?.key else {
      return
    }
    self.drawing?.task.cancel()
    self.drawing = nil
    if let frames = Self.lastFrames, frames.key == key {
      self.play(frames)
      return
    }
    let task = Task { [weak self] in
      let frames = await Task.detached(priority: .userInitiated) { BannerLogoFrames(key) }.value
      guard let self, !Task.isCancelled else {
        return
      }
      self.drawing = nil
      guard let frames else {
        return
      }
      Self.lastFrames = frames
      self.play(frames)
    }
    self.drawing = (key, task)
  }

  private func play(_ frames: BannerLogoFrames) {
    let now = self.layerTime
    // Frames drawn again go on from where the H is. The first start at rest.
    let angle = self.frames == nil ? 0 : self.turn.angle(at: now)
    self.frames = frames
    self.framesLayer.frame = frames.frame
    self.framesLayer.contentsScale = frames.key.scale
    self.start(BannerLogoTurn(begin: now, angle: angle, speed: BannerLogoTurn.steadySpeed))
    if self.alphaValue == 0 {
      NSAnimationContext.runAnimationGroup { context in
        context.duration = 0.3
        self.animator().alphaValue = 1
      }
    }
  }

  // MARK: Turning

  private var layerTime: CFTimeInterval {
    self.framesLayer.convertTime(CACurrentMediaTime(), from: nil)
  }

  /// Plays a turn from its beginning: a frame a degree, 30 a second, as SceneKit drew it, and after
  /// a click, the frame for each 60th of a second until it's settled.
  private func start(_ turn: BannerLogoTurn) {
    guard let frames = self.frames else {
      return
    }
    self.turn = turn
    self.framesLayer.removeAllAnimations()
    self.framesLayer.contents = frames.image(at: turn.angle)
    guard frames.images.count > 1 else {
      return
    }

    var steadyBegin = turn.begin
    if !turn.isSteady {
      let count = Int(BannerLogoTurn.easing * 60)
      let images = (0..<count).map { frames.image(at: turn.angle(at: turn.begin + Double($0) / 60)) }
      let spin = Self.animation(images, duration: BannerLogoTurn.easing)
      spin.beginTime = turn.begin
      // Kept on its last frame until the steady turn takes over. Taken away when it ends, the
      // frame the click started from could show for a moment in between.
      spin.fillMode = .forwards
      spin.isRemovedOnCompletion = false
      self.framesLayer.add(spin, forKey: "spin")
      steadyBegin += BannerLogoTurn.easing
    }
    // Then on with the steady turn, from wherever that left it.
    let first = frames.index(at: turn.angle(at: steadyBegin))
    let steady = Self.animation(Array(frames.images[first...] + frames.images[..<first]), duration: BannerLogoView.spinDuration)
    steady.beginTime = steadyBegin
    steady.repeatCount = .infinity
    self.framesLayer.add(steady, forKey: "turn")
  }

  /// Each image for the same share of the time.
  private static func animation(_ images: [CGImage], duration: CFTimeInterval) -> CAKeyframeAnimation {
    let animation = CAKeyframeAnimation(keyPath: "contents")
    animation.values = images
    animation.keyTimes = (0...images.count).map { NSNumber(value: Double($0) / Double(images.count)) }
    animation.calculationMode = .discrete
    animation.duration = duration
    return animation
  }

  /// A few quick turns that ease back into the steady one.
  private func spinQuickly() {
    guard (self.frames?.images.count ?? 0) > 1, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
      return
    }
    let now = self.layerTime
    self.start(BannerLogoTurn(begin: now, angle: self.turn.angle(at: now), speed: BannerLogoTurn.quickSpeed))
  }

  // MARK: Clicks

  // The panel never becomes key, so take the first click instead of ignoring it.
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    guard let window = self.window else {
      return
    }
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
  }
}

/// One turn of the banner's H, drawn by SceneKit as `BannerLogoView` draws it, a frame for each
/// degree from its resting angle, cropped to where the H reaches.
final class BannerLogoFrames: @unchecked Sendable {
  struct Key: Equatable, @unchecked Sendable {
    /// The view's size, in points.
    var size: CGSize
    var scale: CGFloat
    var zoom: CGFloat
    /// The window's colors, so Core Animation needn't convert the frames on the main thread.
    var colorSpace: CGColorSpace
    /// How many in a turn.
    var count: Int
  }

  let key: Key
  /// A frame for each step of a turn, from the resting angle.
  let images: [CGImage]
  /// Where the frames go in the view, in points.
  let frame: CGRect

  func index(at angle: Double) -> Int {
    let index = Int((angle / (2 * .pi) * Double(self.images.count)).rounded()) % self.images.count
    return index < 0 ? index + self.images.count : index
  }

  func image(at angle: Double) -> CGImage {
    self.images[self.index(at: angle)]
  }

  /// Draws the frames. Slow, so off the main thread.
  init?(_ key: Key) {
    let width = Int((key.size.width * key.scale).rounded())
    let height = Int((key.size.height * key.scale).rounded())
    guard width > 0, height > 0, key.count > 0,
          // SceneKit and Metal let go of what they drew with as soon as the pool's drained.
          let pixels = autoreleasepool(invoking: { Self.draw(key, width: width, height: height) }) else {
      return nil
    }
    let bytesPerRow = width * 4
    let frameBytes = bytesPerRow * height

    // Around everywhere the H reaches as it turns, so the frames take no more memory than they need.
    let bytes = pixels.contents().assumingMemoryBound(to: UInt8.self)
    var left = width, right = 0, top = height, bottom = 0
    for index in 0..<key.count {
      for y in 0..<height {
        let row = index * frameBytes + y * bytesPerRow
        guard let first = (0..<width).first(where: { bytes[row + $0 * 4 + 3] != 0 }) else {
          continue
        }
        let last = (0..<width).last(where: { bytes[row + $0 * 4 + 3] != 0 }) ?? first
        left = min(left, first)
        right = max(right, last + 1)
        top = min(top, y)
        bottom = max(bottom, y + 1)
      }
    }
    guard left < right, top < bottom else {
      return nil
    }

    // Cropped to it, in the window's colors.
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let colorSpace = key.colorSpace.model == .rgb ? key.colorSpace : sRGB
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
    var images: [CGImage] = []
    images.reserveCapacity(key.count)
    for index in 0..<key.count {
      guard let provider = CGDataProvider(dataInfo: nil, data: bytes + index * frameBytes, size: frameBytes, releaseData: { _, _, _ in }),
            let drawn = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: sRGB,
                                bitmapInfo: CGBitmapInfo(rawValue: bitmapInfo), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
            let context = CGContext(data: nil, width: right - left, height: bottom - top, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: bitmapInfo) else {
        return nil
      }
      // A context's origin is at its bottom.
      context.draw(drawn, in: CGRect(x: -left, y: bottom - height, width: width, height: height))
      guard let image = context.makeImage() else {
        return nil
      }
      images.append(image)
    }
    withExtendedLifetime(pixels) {}

    self.key = key
    self.images = images
    self.frame = CGRect(x: CGFloat(left) / key.scale, y: CGFloat(height - bottom) / key.scale,
                        width: CGFloat(right - left) / key.scale, height: CGFloat(bottom - top) / key.scale)
  }

  /// Each frame, one after another, as SceneKit draws it into SCNView: premultiplied BGRA, in sRGB.
  private static func draw(_ key: Key, width: Int, height: Int) -> MTLBuffer? {
    guard let device = MTLCreateSystemDefaultDevice(),
          let queue = device.makeCommandQueue(),
          let (scene, spinNode, camera) = BannerLogoView.makeScene(zoom: key.zoom) else {
      return nil
    }
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = scene
    renderer.pointOfView = camera

    // As SCNView draws it: 4× multisampled, into sRGB.
    func texture(_ format: MTLPixelFormat, samples: Int) -> MTLTexture? {
      let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: width, height: height, mipmapped: false)
      descriptor.textureType = samples > 1 ? .type2DMultisample : .type2D
      descriptor.sampleCount = samples
      descriptor.usage = .renderTarget
      descriptor.storageMode = .private
      return device.makeTexture(descriptor: descriptor)
    }
    let bytesPerRow = width * 4
    let frameBytes = bytesPerRow * height
    guard let color = texture(.bgra8Unorm_srgb, samples: 4),
          let resolved = texture(.bgra8Unorm_srgb, samples: 1),
          let depth = texture(.depth32Float, samples: 4),
          let pixels = device.makeBuffer(length: frameBytes * key.count, options: .storageModeShared) else {
      return nil
    }
    let pass = MTLRenderPassDescriptor()
    pass.colorAttachments[0].texture = color
    pass.colorAttachments[0].resolveTexture = resolved
    pass.colorAttachments[0].loadAction = .clear
    pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
    pass.colorAttachments[0].storeAction = .multisampleResolve
    pass.depthAttachment.texture = depth
    pass.depthAttachment.loadAction = .clear
    pass.depthAttachment.clearDepth = renderer.usesReverseZ ? 0 : 1
    pass.depthAttachment.storeAction = .dontCare

    var last: MTLCommandBuffer?
    for index in 0..<key.count {
      SCNTransaction.begin()
      SCNTransaction.disableActions = true
      spinNode.eulerAngles.y = BannerLogoView.restingAngle + CGFloat(index) * 2 * .pi / CGFloat(key.count)
      SCNTransaction.commit()
      guard let commandBuffer = queue.makeCommandBuffer() else {
        return nil
      }
      renderer.render(atTime: 0, viewport: CGRect(x: 0, y: 0, width: width, height: height), commandBuffer: commandBuffer, passDescriptor: pass)
      guard let blit = commandBuffer.makeBlitCommandEncoder() else {
        return nil
      }
      blit.copy(from: resolved, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0), sourceSize: MTLSize(width: width, height: height, depth: 1),
                to: pixels, destinationOffset: index * frameBytes, destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: frameBytes)
      blit.endEncoding()
      commandBuffer.commit()
      last = commandBuffer
    }
    last?.waitUntilCompleted()
    guard last?.status == .completed else {
      return nil
    }
    return pixels
  }
}
