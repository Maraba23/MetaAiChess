import MWDATCore
import SwiftUI

@main
struct XadrezNoOuvidoApp: App {
  @State private var glasses: GlassesManager
  @State private var bridge = ChessBridge()
  @State private var settings = AppSettings()
  @State private var watcher = MoveWatcher()

  init() {
    // Touching Wearables.shared after a failed configure() crashes, so the board must work without it
    var wearables: WearablesInterface?
    do {
      try Wearables.configure()
      wearables = Wearables.shared
    } catch {
      NSLog("[XadrezNoOuvido] Failed to configure Wearables SDK: \(error)")
    }
    _glasses = State(wrappedValue: GlassesManager(wearables: wearables))
  }

  var body: some Scene {
    WindowGroup {
      ContentView(glasses: glasses, bridge: bridge, settings: settings, watcher: watcher)
        // Meta AI calls back here after registration and permission prompts
        .onOpenURL { url in
          guard
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.queryItems?.contains(where: { $0.name == "metaWearablesAction" }) == true,
            glasses.isAvailable
          else { return }
          Task {
            do {
              _ = try await Wearables.shared.handleUrl(url)
            } catch {
              glasses.errorMessage = error.localizedDescription
            }
          }
        }
    }
  }
}
