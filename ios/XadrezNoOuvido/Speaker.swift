import AVFoundation

/// Speaks in Portuguese. With the glasses connected, iOS routes playback to their open-ear speakers.
@MainActor
final class Speaker {
  private let synthesizer = AVSpeechSynthesizer()
  private let voice = AVSpeechSynthesisVoice(language: "pt-BR")

  func speak(_ text: String) {
    // .playback also ignores the silent switch, unlike speech in Safari
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio)
    try? session.setActive(true)
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    synthesizer.speak(utterance)
  }
}
