import UIKit

/// The answer to "which of the opponent's legal moves does this photo show?"
struct MoveAnswer: Decodable {
  let move: String   // a UCI string from the legal list, or "none"
  let confidence: String   // "high" or "low"
}

extension UIImage {
  /// Glasses photos can be several megapixels; Claude scales anything past ~1568 px down anyway, so don't send more.
  func boardJPEG(maxSide: CGFloat = 1568) -> Data? {
    let longest = max(size.width, size.height)
    guard longest > maxSide else { return jpegData(compressionQuality: 0.8) }
    let scale = maxSide / longest
    let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    let format = UIGraphicsImageRendererFormat.default()
    format.scale = 1
    let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in draw(in: CGRect(origin: .zero, size: target)) }
    return resized.jpegData(compressionQuality: 0.8)
  }
}

/// Something that can read the opponent's move from a glasses frame: the Mac server or the Claude API.
protocol MoveReader {
  func detectMove(in image: UIImage, state: BoardState) async throws -> MoveAnswer
}

enum MoveReaderFactory {
  @MainActor
  static func make(_ settings: AppSettings) -> MoveReader {
    switch settings.backend {
    case .mac: return MacVision(serverURL: settings.macURL, token: settings.macToken)
    case .claudeAPI: return ClaudeVision(apiKey: settings.apiKey, model: settings.model)
    }
  }
}

/// Sends the frame to mac/board_server.py on your Mac, which asks Claude Code (your subscription) and answers.
struct MacVision: MoveReader {
  enum Failure: LocalizedError {
    case missingURL, unreachable, badToken, server(Int, String), unreadable
    var errorDescription: String? {
      switch self {
      case .missingURL: return "Coloque o endereço do Mac nos ajustes."
      case .unreachable: return "Não consegui falar com o Mac. Ele está ligado e com o servidor rodando?"
      case .badToken: return "O código do Mac está errado. Confira nos ajustes."
      case .server(let code, let body): return "Erro \(code) no Mac: \(body)"
      case .unreadable: return "Não entendi a resposta do Mac."
      }
    }
  }

  let serverURL: String
  let token: String

  func detectMove(in image: UIImage, state: BoardState) async throws -> MoveAnswer {
    guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), base.host != nil else {
      throw Failure.missingURL
    }
    guard let jpeg = image.boardJPEG() else { throw Failure.unreadable }
    let body: [String: Any] = [
      "image_jpeg_base64": jpeg.base64EncodedString(),
      "fen": state.fen,
      "my_color": state.myColor,
      "legal": state.legal.map { ["uci": $0.uci, "san": $0.san] },
    ]
    var request = URLRequest(url: base.appendingPathComponent("move"))
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw Failure.unreachable
    }
    switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
    case 200: break
    case 401: throw Failure.badToken
    case let code: throw Failure.server(code, String(data: data.prefix(300), encoding: .utf8) ?? "")
    }
    guard let answer = try? JSONDecoder().decode(MoveAnswer.self, from: data) else { throw Failure.unreadable }
    return answer
  }

  /// Quick check used by the settings screen
  static func ping(serverURL: String, token: String) async -> String {
    guard let base = URL(string: serverURL.trimmingCharacters(in: .whitespaces)), base.host != nil else {
      return "Endereço inválido"
    }
    var request = URLRequest(url: base.appendingPathComponent("health"))
    request.timeoutInterval = 5
    request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    do {
      let (_, response) = try await URLSession.shared.data(for: request)
      switch (response as? HTTPURLResponse)?.statusCode {
      case 200: return "Conectado ao Mac ✓"
      case 401: return "Mac encontrado, mas o código está errado"
      case let code: return "Mac respondeu com erro \(code ?? 0)"
      }
    } catch {
      return "Mac não encontrado nesse endereço"
    }
  }
}
