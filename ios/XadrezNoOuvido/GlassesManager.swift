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
  var errorMessage: String?

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
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []

  init(wearables: WearablesInterface?) {
    self.wearables = wearables
    guard let wearables else {
      registrationState = .unavailable
      deviceSelector = nil
      return
    }
    self.deviceSelector = AutoDeviceSelector(wearables: wearables)
    self.registrationState = wearables.registrationState
    tasks.append(Task { [weak self] in
      for await state in wearables.registrationStateStream() {
        self?.registrationState = state
      }
    })
    tasks.append(Task { [weak self] in
      guard let selector = self?.deviceSelector else { return }
      for await deviceId in selector.activeDeviceStream() {
        self?.hasDevice = deviceId != nil
      }
    })
  }

  func connect() {
    guard let wearables, registrationState != .registering else { return }
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
  func startCamera() {
    guard let wearables, let deviceSelector, session == nil else { return }
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

  func stopCamera() {
    camera?.stop()
    session?.stop()
  }

  private func handleSessionState(_ state: DeviceSessionState) {
    sessionState = state
    switch state {
    case .started:
      Task { await beginStreamIfAllowed() }
    case .stopped:
      clearStream()
      cleanupSession()
    default:
      break
    }
  }

  private func beginStreamIfAllowed() async {
    guard let wearables, let session, session.state == .started, camera == nil else { return }
    do {
      if try await wearables.checkPermissionStatus(.camera) != .granted {
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

    // Raw frames convert straight to UIImage. A few frames per second is plenty: we only need a still every few seconds.
    let config = StreamConfiguration(
      videoCodec: VideoCodec.raw,
      resolution: StreamingResolution.high,
      frameRate: 7
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
          self?.streamState = state
          if state == .stopped { self?.clearStream() }
        }
      }.store(in: streamTokens)
      stream.videoFramePublisher.listen { [weak self] frame in
        guard let image = frame.makeUIImage() else { return }
        Task { @MainActor in
          self?.latestFrame = image
          self?.latestFrameDate = Date()
        }
      }.store(in: streamTokens)
      stream.errorPublisher.listen { [weak self] error in
        Task { @MainActor in self?.errorMessage = error.localizedDescription }
      }.store(in: streamTokens)
      streamState = .starting
      stream.start()
    } catch {
      camera = nil
      errorMessage = error.localizedDescription
    }
  }

  private func clearStream() {
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
