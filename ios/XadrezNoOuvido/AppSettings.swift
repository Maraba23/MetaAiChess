import Foundation
import Observation
import Security

@Observable
@MainActor
final class AppSettings {
  enum Backend: String, CaseIterable {
    case mac   // mac/board_server.py running Claude Code on your subscription: free
    case claudeAPI   // pay-per-use Claude API key
  }

  static let models: [(id: String, label: String)] = [
    ("claude-opus-5-5", "Opus 5.5 · lê melhor o tabuleiro"),
    ("claude-haiku-5-5", "Haiku 5.5 · bem mais barato e rápido"),
  ]

  var backend: Backend {
    didSet { UserDefaults.standard.set(backend.rawValue, forKey: "backend") }
  }
  /// Address printed by board_server.py, e.g. http://192.168.0.12:8765
  var macURL: String {
    didSet { UserDefaults.standard.set(macURL, forKey: "macURL") }
  }
  /// Code printed by board_server.py, so nobody else on the network can use your Mac
  var macToken: String {
    didSet { UserDefaults.standard.set(macToken, forKey: "macToken") }
  }
  var apiKey: String {
    didSet { Keychain.save(apiKey) }
  }
  var model: String {
    didSet { UserDefaults.standard.set(model, forKey: "model") }
  }
  /// Seconds between looks at the board while waiting for the friend's move
  var interval: Double {
    didSet { UserDefaults.standard.set(interval, forKey: "interval") }
  }

  init() {
    let defaults = UserDefaults.standard
    backend = Backend(rawValue: defaults.string(forKey: "backend") ?? "") ?? .mac
    macURL = defaults.string(forKey: "macURL") ?? ""
    macToken = defaults.string(forKey: "macToken") ?? ""
    apiKey = Keychain.load() ?? ""
    model = UserDefaults.standard.string(forKey: "model") ?? "claude-opus-5-5"
    let saved = UserDefaults.standard.double(forKey: "interval")
    interval = saved > 0 ? saved : 3
  }
}

/// Keeps the API key out of UserDefaults.
private enum Keychain {
  private static let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "XadrezNoOuvido",
    kSecAttrAccount as String: "anthropic-api-key",
  ]

  static func save(_ value: String) {
    SecItemDelete(query as CFDictionary)
    guard !value.isEmpty else { return }
    var item = query
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(item as CFDictionary, nil)
  }

  static func load() -> String? {
    var lookup = query
    lookup[kSecReturnData as String] = true
    lookup[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(lookup as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }
}
