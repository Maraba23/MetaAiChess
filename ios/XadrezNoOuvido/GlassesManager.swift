import MWDATCamera
import MWDATCore
import Observation
import UIKit

/// Connects to the Ray-Ban Meta through Meta AI and keeps the latest camera frame around.
/// Follows the flow of Meta's CameraAccess sample: register -> session -> camera permission -> stream.
@Observable
@MainActor
final class GlassesManager {
  var registrationState: RegistrationState
  var hasDevice = false
  var sessionState: DeviceSessionState = .idle
  var streamState: StreamState = .stopped
  var latestFrame: UIImage?
  var latestFrameDate: Date?
  var errorMessage: String? {
    didSet { if let errorMessage { log("error: \(errorMessage)") } }
  }

  /// False when the Meta SDK failed to configure (e.g. in the Simulator); tapping the board still works
  var isAvailable: Bool { wearables != nil }
  var isRegistered: Bool { registrationState == .registered }
  var isStreaming: Bool { streamState == .streaming }

  @ObservationIgnored private let wearables: WearablesInterface?
  @ObservationIgnored private let deviceSelector: AutoDeviceSelector?
  @ObservationIgnored private var session: DeviceSession?
  @ObservationIgnored private var camera: MWDATCamera.Camera?
  @ObservationIgnored private let sessionTokens = ListenerTokenBag()
  @ObservationIgnored private let streamTokens = ListenerTokenBag()
  @ObservationIgnored private let deviceTokens = ListenerTokenBag()
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []
  @ObservationIgnored private var retriesLeft = 0
  @ObservationIgnored private var retryPending = false
  @ObservationIgnored private var photoWaiter: CheckedContinuation<UIImage?, Never>?
  @ObservationIgnored private var photoRequest = 0

  init(wearables: WearablesInterface?) {
    self.wearables = wearables
    guard let wearables else {
      registrationState = .unavailable
      deviceSelector = nil
      return
    }
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    self.registrationState = wearables.registrationState
    log("registration: \(registrationState)")
    tasks.append(Task { [weak self] in
      for await state in wearables.registrationStateStream() {
        log("registration: \(state)")
        self?.registrationState = state
      }
    })
    tasks.append(Task { [weak self] in
      guard let selector = self?.deviceSelector else { return }
      for await deviceId in selector.activeDeviceStream() {
        log("active device: \(String(describing: deviceId))")
        self?.hasDevice = deviceId != nil
        self?.watchDeviceState(deviceId.flatMap { wearables.deviceForIdentifier($0) })
      }
    })
  }

  /// Link, compatibility, worn and hinge state explain why a stream sits in waitingForDevice
  private func watchDeviceState(_ device: Device?) {
    deviceTokens.clear()
    device?.addDeviceStateListener { [weak self] state in
      log("device state: \(state)")
      if state.compatibility == .deviceUpdateRequired {
        Task { @MainActor in self?.errorMessage = "O óculos precisa de atualização. Abra o app Meta AI e atualize o óculos." }
      }
    }.store(in: deviceTokens)
  }

  func connect() {
    guard let wearables, registrationState != .registering else { return }
    log("connect")
    Task {
      do {
        try await wearables.startRegistration()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  func disconnect() {
    stopCamera()
    guard let wearables else { return }
    Task {
      do {
        try await wearables.startUnregistration()
      } catch {
        errorMessage = error.localizedDescription
      }
    }
  }

  /// Starts a device session; the camera stream begins once the session reports `.started`.
  /// If the glasses never answer, the session is reopened once on its own before giving up.
  func startCamera() {
    guard session == nil else { return }
    retriesLeft = 1
    openSession()
  }

  private func openSession() {
    guard let wearables, let deviceSelector, session == nil else { return }
    log("start camera")
    do {
      let newSession = try wearables.createSession(deviceSelector: deviceSelector)
      session = newSession
      newSession.statePublisher.listen { [weak self] state in
        Task { @MainActor in self?.handleSessionState(state) }
      }.store(in: sessionTokens)
      newSession.errorPublisher.listen { [weak self] error in
        Task { @MainActor in self?.errorMessage = error.localizedDescription }
      }.store(in: sessionTokens)
      sessionState = .starting
      try newSession.start()
    } catch {
      errorMessage = error.localizedDescription
      cleanupSession()
    }
  }

  /// A full-quality still from the glasses while the stream runs. Stream frames are only 360x640,
  /// too blurry for Claude to tell which piece moved. Returns nil if no photo arrives within 15 s.
  func capturePhoto() async -> UIImage? {
    guard let camera, photoWaiter == nil else { return nil }
    photoRequest += 1
    let request = photoRequest
    return await withCheckedContinuation { continuation in
      photoWaiter = continuation
      guard camera.stream.capturePhoto(format: .jpeg) else {
        log("photo request refused")
        finishPhoto(nil)
        return
      }
      Task {
        try? await Task.sleep(for: .seconds(15))
        // Only time out this request, not a later one
        guard photoRequest == request, photoWaiter != nil else { return }
        log("photo timed out")
        finishPhoto(nil)
      }
    }
  }

  private func finishPhoto(_ image: UIImage?) {
    photoWaiter?.resume(returning: image)
    photoWaiter = nil
  }

  func stopCamera() {
    retriesLeft = 0
    retryPending = false
    camera?.stop()
    session?.stop()
  }

  private func handleSessionState(_ state: DeviceSessionState) {
    log("session: \(state)")
    sessionState = state
    switch state {
    case .started:
      // Meta's sample starts the stream with a separate tap, so the glasses get a moment after the session opens
      Task {
        try? await Task.sleep(for: .seconds(2))
        await beginStreamIfAllowed()
      }
    case .stopped:
      clearStream()
      cleanupSession()
      if retryPending {
        retryPending = false
        log("retrying camera")
        Task {
          try? await Task.sleep(for: .seconds(3))
          openSession()
        }
      }
    default:
      break
    }
  }

  private func beginStreamIfAllowed() async {
    guard let wearables, let session, session.state == .started, camera == nil else { return }
    do {
      let permission = try await wearables.checkPermissionStatus(.camera)
      log("camera permission: \(permission)")
      if permission != .granted {
        // Opens Meta AI so you can allow camera access for this app
        guard try await wearables.requestPermission(.camera) == .granted else {
          errorMessage = "O acesso à câmera do óculos foi negado no app Meta AI."
          return
        }
      }
    } catch {
      errorMessage = error.localizedDescription
      return
    }

    // Raw frames convert straight to UIImage. Same settings as Meta's documented raw example.
    let config = StreamConfiguration(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.low,
      frameRate: 24
    )
    do {
      guard let newCamera = try session.addCamera(config: config) else {
        errorMessage = "Não consegui abrir a câmera do óculos. Tente de novo."
        return
      }
      camera = newCamera
      let stream = newCamera.stream
      stream.statePublisher.listen { [weak self] state in
        Task { @MainActor in
          log("stream: \(state)")
          self?.streamState = state
          // Also end the session, so "Ligar câmera do óculos" comes back for another try
          if state == .stopped {
            self?.clearStream()
            self?.session?.stop()
          }
        }
      }.store(in: streamTokens)
      stream.videoFramePublisher.listen { [weak self] frame in
        guard let image = frame.makeUIImage() else { return }
        Task { @MainActor in
          self?.latestFrame = image
          self?.latestFrameDate = Date()
        }
      }.store(in: streamTokens)
      // Photos from the glasses' shutter button arrive here too; either is a fine look at the board
      stream.photoDataPublisher.listen { [weak self] photo in
        let image = UIImage(data: photo.data)
        Task { @MainActor in
          log("photo \(photo.data.count) bytes, \(image.map { "\(Int($0.size.width))x\(Int($0.size.height))" } ?? "unreadable")")
          self?.finishPhoto(image)
        }
      }.store(in: streamTokens)
      stream.errorPublisher.listen { [weak self] error in
        Task { @MainActor in
          switch error {
          case .deviceNotConnected, .timeout:
            guard let self else { return }
            if self.retriesLeft > 0 {
              // The stream stop that follows ends the session; .stopped then reopens it
              self.retriesLeft -= 1
              self.retryPending = true
            } else {
              self.errorMessage = "A câmera do óculos não respondeu. Feche o app Meta AI e este app, abra os dois de novo e tente outra vez."
            }
          default:
            self?.errorMessage = error.localizedDescription
          }
        }
      }.store(in: streamTokens)
      streamState = .starting
      stream.start()
    } catch {
      camera = nil
      errorMessage = error.localizedDescription
    }
  }

  private func clearStream() {
    finishPhoto(nil)
    streamTokens.clear()
    camera = nil
    streamState = .stopped
    latestFrame = nil
    latestFrameDate = nil
  }

  private func cleanupSession() {
    sessionTokens.clear()
    session = nil
    sessionState = .idle
  }
}

private func log(_ message: String) {
  NSLog("[XadrezNoOuvido] glasses \(message)")
}
