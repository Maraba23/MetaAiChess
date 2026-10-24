import Observation
import SwiftUI
import WebKit

/// What the web app reports after every render.
struct BoardState: Decodable, Equatable {
  struct LegalMove: Decodable, Equatable {
    let uci: String
    let san: String
  }
  let waitingForFriend: Bool
  let fen: String
  let myColor: String
  let legal: [LegalMove]
}

/// Hosts the shared web app (../app/index.html) and talks to it.
/// The board, Stockfish and the spoken phrasing all live in JavaScript; Swift adds the glasses camera and native speech.
@Observable
@MainActor
final class ChessBridge: NSObject, WKScriptMessageHandler {
  private(set) var state: BoardState?
  @ObservationIgnored let webView: WKWebView
  @ObservationIgnored let speaker = Speaker()

  override init() {
    let contentController = WKUserContentController()
    let config = WKWebViewConfiguration()
    config.userContentController = contentController
    config.allowsInlineMediaPlayback = true
    webView = WKWebView(frame: .zero, configuration: config)
    super.init()

    contentController.add(WeakMessageHandler(self), name: "native")
    // chess.js runs as-is; Stockfish is handed over as a string and started as a blob Worker by index.html
    if let chess = Self.bundleText("chess.min", "js") {
      contentController.addUserScript(WKUserScript(source: chess, injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    if let stockfish = Self.bundleText("stockfish", "js"),
      let literal = try? JSONSerialization.data(withJSONObject: stockfish, options: .fragmentsAllowed),
      let literalText = String(data: literal, encoding: .utf8)
    {
      contentController.addUserScript(
        WKUserScript(source: "window.__SF_SRC = \(literalText);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
    }
    if #available(iOS 16.4, *) { webView.isInspectable = true }
    load()
  }

  func load() {
    guard let page = Self.bundleText("index", "html") else { return }
    // index.html is written as a page body (the artifact host adds the skeleton), so wrap it here
    let html = """
      <!doctype html><html lang="pt-BR"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
      <style>:root{padding-top:env(safe-area-inset-top);padding-bottom:env(safe-area-inset-bottom)}[hidden]{display:none!important}</style>
      </head><body>\(page)</body></html>
      """
    // A real https origin keeps localStorage working, so a game survives an app restart
    webView.loadHTMLString(html, baseURL: URL(string: "https://xadrez-no-ouvido.app/"))
  }

  /// Plays the friend's move on the board; the web app then asks Stockfish and speaks the answer.
  func applyFriendMove(_ uci: String) {
    guard uci.range(of: "^[a-h][1-8][a-h][1-8][qrbn]?$", options: .regularExpression) != nil else { return }
    webView.evaluateJavaScript("applyFriendMove('\(uci)')", completionHandler: nil)
  }

  nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
    guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
    let data = try? JSONSerialization.data(withJSONObject: body)
    let text = body["text"] as? String
    MainActor.assumeIsolated {
      switch type {
      case "speak":
        if let text { speaker.speak(text) }
      case "state":
        if let data, let decoded = try? JSONDecoder().decode(BoardState.self, from: data) {
          state = decoded
        }
      default:
        break
      }
    }
  }

  private static func bundleText(_ name: String, _ ext: String) -> String? {
    guard let url = Bundle.main.url(forResource: name, withExtension: ext) else {
      NSLog("[XadrezNoOuvido] Missing bundle resource \(name).\(ext)")
      return nil
    }
    return try? String(contentsOf: url, encoding: .utf8)
  }
}

/// WKUserContentController retains its handlers; this breaks the cycle with ChessBridge.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
  weak var target: WKScriptMessageHandler?
  init(_ target: WKScriptMessageHandler) { self.target = target }
  func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
    target?.userContentController(controller, didReceive: message)
  }
}

struct ChessWebView: UIViewRepresentable {
  let bridge: ChessBridge
  func makeUIView(context: Context) -> WKWebView { bridge.webView }
  func updateUIView(_ uiView: WKWebView, context: Context) {}
}
