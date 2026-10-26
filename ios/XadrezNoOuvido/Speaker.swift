import AVFoundation

/// Speaks in Portuguese. With the glasses connected, iOS routes playback to their open-ear speakers.
@MainActor
final class Speaker {
  private let synthesizer = AVSpeechSynthesizer()
  private let voice = AVSpeechSynthesisVoice(language: "pt-BR")

  func speak(_ text: String) {
    // .playback also ignores the silent switch, unlike speech in Safari. Same setup as Meta's A2DP example.
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default, options: [])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      NSLog("[XadrezNoOuvido] audio session error: \(error)")
    }
    // Shows whether speech goes to the glasses (BluetoothA2DPOutput) or somewhere else
    let outputs = session.currentRoute.outputs.map { "\($0.portType.rawValue) \($0.portName)" }
    NSLog("[XadrezNoOuvido] speak \"\(text)\" -> \(outputs)")
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    synthesizer.speak(utterance)
  }
}
