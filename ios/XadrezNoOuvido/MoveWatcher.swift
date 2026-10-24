import Observation
import UIKit

/// While it's the friend's turn, looks at a glasses frame every few seconds and asks whether a move happened
/// (through the Mac server or the Claude API, per settings).
/// A move only goes on the board after two readings in a row agree, so a hand passing over the board doesn't count.
@Observable
@MainActor
final class MoveWatcher {
  private(set) var isOn = false
  private(set) var status = "Desligado"
  private(set) var lookCount = 0

  @ObservationIgnored private var loop: Task<Void, Never>?
  @ObservationIgnored private var candidate: (uci: String, hits: Int)?
  private let requiredHits = 2

  func start(glasses: GlassesManager, bridge: ChessBridge, settings: AppSettings) {
    loop?.cancel()
    isOn = true
    candidate = nil
    status = "Ligado"
    loop = Task { [weak self] in
      while !Task.isCancelled {
        guard let self else { return }
        await self.look(glasses: glasses, bridge: bridge, settings: settings)
        try? await Task.sleep(for: .seconds(settings.interval))
      }
    }
  }

  func stop() {
    loop?.cancel()
    loop = nil
    isOn = false
    candidate = nil
    status = "Desligado"
  }

  private func look(glasses: GlassesManager, bridge: ChessBridge, settings: AppSettings) async {
    guard let state = bridge.state, state.waitingForFriend, !state.legal.isEmpty else {
      candidate = nil
      status = "Esperando a vez do seu amigo"
      return
    }
    guard glasses.isStreaming, let frame = glasses.latestFrame,
      let frameDate = glasses.latestFrameDate, Date().timeIntervalSince(frameDate) < 3
    else {
      status = "Sem imagem do óculos"
      return
    }

    status = candidate == nil ? "Olhando o tabuleiro…" : "Confirmando o lance…"
    let reader = MoveReaderFactory.make(settings)
    do {
      let answer = try await reader.detectMove(in: frame, state: state)
      lookCount += 1
      // You may have typed the move by hand while Claude was looking
      guard bridge.state?.fen == state.fen else {
        candidate = nil
        return
      }
      guard answer.move != "none", answer.confidence == "high" else {
        candidate = nil
        status = "Nenhum lance ainda"
        return
      }
      let hits = candidate?.uci == answer.move ? (candidate?.hits ?? 0) + 1 : 1
      candidate = (answer.move, hits)
      let san = state.legal.first { $0.uci == answer.move }?.san ?? answer.move
      if hits >= requiredHits {
        candidate = nil
        status = "Seu amigo jogou \(san)"
        bridge.applyFriendMove(answer.move)
      } else {
        status = "Vi \(san), confirmando…"
      }
    } catch {
      status = error.localizedDescription
    }
  }
}
