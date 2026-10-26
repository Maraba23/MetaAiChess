import UIKit

/// Asks Claude which of the opponent's legal moves the photo shows, if any.
/// Raw HTTP to the Messages API (there is no official Anthropic Swift SDK).
struct ClaudeVision: MoveReader {
  enum Failure: LocalizedError {
    case missingKey, badKey, rateLimited, http(Int, String), unreadable
    var errorDescription: String? {
      switch self {
      case .missingKey: return "Coloque sua chave da API do Claude nos ajustes."
      case .badKey: return "A chave da API do Claude foi recusada. Confira nos ajustes."
      case .rateLimited: return "Limite da API atingido. Tentando de novo em instantes."
      case .http(let code, let body): return "Erro \(code) da API do Claude: \(body)"
      case .unreadable: return "Não entendi a resposta do Claude."
      }
    }
  }

  let apiKey: String
  let model: String

  func detectMove(in image: UIImage, state: BoardState) async throws -> MoveAnswer {
    guard !apiKey.isEmpty else { throw Failure.missingKey }
    guard let jpeg = Self.jpeg(image) else { throw Failure.unreadable }

    let mine = state.myColor == "w" ? "White" : "Black"
    let theirs = state.myColor == "w" ? "Black" : "White"
    let legalList = state.legal.map { "\($0.san) (\($0.uci))" }.joined(separator: ", ")
    let prompt = """
      The person wearing the camera plays \(mine), so the \(mine) pieces are the ones closest to the camera.
      Expected position on the physical board right now (FEN): \(state.fen)
      It is \(theirs)'s turn. \(theirs)'s legal moves: \(legalList).

      Compare the photo with that position. If \(theirs) has completed exactly one of these moves \
      (the piece is released on its new square, no hand over the board), answer with that move's UCI string. \
      Otherwise answer "none": no move made yet, a hand still on a piece, the board cut off, blurry or mostly hidden, \
      or you can't tell which move it was.
      Use confidence "high" only when you can clearly see both the square the piece left and the square it landed on.
      """

    var body: [String: Any] = [
      "model": model,
      "max_tokens": 4000,
      "system": "You read physical chessboards from photos taken by smart glasses worn by one of the players.",
      "output_config": [
        "effort": "low",
        "format": [
          "type": "json_schema",
          "schema": [
            "type": "object",
            "properties": [
              "move": ["type": "string", "enum": state.legal.map(\.uci) + ["none"]],
              "confidence": ["type": "string", "enum": ["high", "low"]],
            ],
            "required": ["move", "confidence"],
            "additionalProperties": false,
          ] as [String: Any],
        ] as [String: Any],
      ] as [String: Any],
      "messages": [
        [
          "role": "user",
          "content": [
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()]],
            ["type": "text", "text": prompt],
          ],
        ] as [String: Any]
      ],
    ]

    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "content-type")
    // Haiku has no server-side refusal fallback, so only send it for the other models
    if !model.hasPrefix("claude-haiku") {
      body["fallbacks"] = "default"
      request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (data, response) = try await URLSession.shared.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    switch status {
    case 200: break
    case 401: throw Failure.badKey
    case 429, 529: throw Failure.rateLimited
    default: throw Failure.http(status, String(data: data.prefix(300), encoding: .utf8) ?? "")
    }

    struct Response: Decodable {
      struct Block: Decodable {
        let type: String
        let text: String?
      }
      let content: [Block]
      let stop_reason: String?
    }
    let decoded = try JSONDecoder().decode(Response.self, from: data)
    // A declined request has no usable content; treat it as "no move seen"
    if decoded.stop_reason == "refusal" { return MoveAnswer(move: "none", confidence: "low") }
    guard let text = decoded.content.first(where: { $0.type == "text" })?.text,
      let answer = try? JSONDecoder().decode(MoveAnswer.self, from: Data(text.utf8))
    else { throw Failure.unreadable }
    return answer
  }

  private static func jpeg(_ image: UIImage) -> Data? {
    image.boardJPEG()
  }
}
