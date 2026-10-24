# Xadrez no Ouvido

**Chess move hints whispered in your ear while you play on a real board.** Stockfish picks the move, and your phone says it (in Portuguese) through Ray-Ban Meta glasses or any Bluetooth earbuds.

🇧🇷 [Leia em português](README.pt-BR.md)

> Made for fun games with friends. Using it in tournaments, rated games or online play is cheating and will get you banned.

<!-- Screenshot or GIF of the web app goes here, e.g. ![Web app on iPhone](docs/screenshot.png) -->

## Try it in 2 minutes

1. Pair your earbuds or Ray-Ban Meta with your phone.
2. Open **https://maraba23.github.io/MetaAiChess/app/** in the phone's browser (Safari on iPhone).
3. Pick your color and strength, then tap **Começar e testar o áudio**. You should hear "Pronto" in your ear.
4. When your opponent moves, tap their piece and then its destination square. The best reply is spoken in your ear and shown on the board.

That's the whole web version. It's free, needs no install, and has been tested on an iPhone with Ray-Ban Meta glasses.

## Two ways to use it

| | Web app (`app/`) | iPhone app (`ios/`) |
|---|---|---|
| How the opponent's move gets in | You tap it on the phone | The glasses camera sees it |
| Audio out | Any Bluetooth earbuds or glasses | Ray-Ban Meta glasses |
| What you need | A browser | A Mac with Xcode, an iPhone, Ray-Ban Meta, and Claude to read the board |
| Cost | Free | Free with your Claude subscription (via the Mac), or about US$1–3 per game with the Claude API |
| Status | ✅ Tested on iPhone + Ray-Ban Meta | ⚠️ Written but **never compiled**; expect build fixes |

## How it works

```
                  ┌──────────────── iPhone ─────────────────┐
 Ray-Ban Meta ──► │ camera frames ─► MoveWatcher            │
  (camera)        │                    │ "which legal move  │
                  │                    │  does this show?"  │
                  │                    ▼                    │
                  │   ┌── Mac: board_server.py ─► claude -p │  (free, your subscription)
                  │   └── or Claude API                     │  (paid, API key)
                  │                    │ "e7e5"             │
                  │                    ▼                    │
                  │ app/index.html: board + Stockfish 10    │
                  │                    │ "Cavalo de gê 1    │
                  │                    ▼  para éfe 3"       │
 Ray-Ban Meta ◄── │ speech                                  │
  (speakers)      └─────────────────────────────────────────┘
```

- **The board, the rules and the engine are the same code everywhere.** `app/index.html` runs Stockfish 10 (compiled to JavaScript) in a Web Worker and uses chess.js for legal moves. The iPhone app loads this same page in a WebView.
- **Reading the board means picking one move from a list.** The reader never has to work out the whole position. It gets the photo, the expected position and the list of legal moves, then answers with one of those moves or "none". This makes it much more reliable.
- **A move needs two matching reads in a row.** That way your opponent's hand passing over the board doesn't count as a move.
- **Tapping always works.** If the camera misreads, you tap the move on the board and keep playing.

## Running each part

### Web app

`app/index.html` needs to be served over HTTP. Opening it as a file won't work, because browsers block Web Workers from `file://`.

```sh
cd app && python3 -m http.server 8000
# open http://<your-computer-ip>:8000 on the phone
```

To host it yourself, fork the repo and enable **Settings › Pages › Branch: main**.

### iPhone app

You need:
- A Mac with **Xcode 26.4+**
- An iPhone on **iOS 17.2+**
- Ray-Ban Meta glasses paired in the **Meta AI** app
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

Steps:
1. In the Meta AI app, turn on **Developer Mode**: Settings › App Info, tap the version number 5 times.
2. Build the app:
   ```sh
   brew install xcodegen
   cd ios && xcodegen generate && open XadrezNoOuvido.xcodeproj
   ```
3. In Xcode, set your signing team and a unique bundle id, then run the app on the iPhone.
4. In the app: **Conectar óculos**, then **Ligar câmera do óculos**, then turn on **Ler lances pelo óculos**.

It uses Meta's [Wearables Device Access Toolkit](https://github.com/facebook/meta-wearables-dat-ios) 1.0.1, which is still a developer preview. Apps that use it can't be published to the App Store yet. Full guide (Portuguese): [ios/README.md](ios/README.md).

### Mac board reader (free)

```sh
python3 mac/board_server.py   # prints an address and a code
```

Type the address and code into the iPhone app (gear icon › **Mac (grátis)**).

The server runs the official `claude` CLI headless with **no tools**, so it can only look at the image and answer. It uses **your own** Claude subscription, and each read counts toward your usage limits. You need Claude Code installed and logged in, and Python 3 (standard library only).

To use it away from your home Wi-Fi, connect the phone and the Mac with [Tailscale](https://tailscale.com). Full guide (Portuguese): [mac/README.md](mac/README.md).

## What's tested and what isn't

| Part | Status |
|---|---|
| Web app, Stockfish, speech through Ray-Ban Meta on iPhone | ✅ Tested |
| `claude -p` reading a board image (`e7e5 HIGH` / `NONE`, ~3 s) | ✅ Tested on Windows, with **rendered** boards, not real photos |
| iPhone app (Meta SDK, camera, WebView bridge) | ⚠️ Never compiled; written on Windows from Meta's samples |
| Board reading from real glasses photos (angle, shadows) | ❓ Unknown until someone tries it |
| iPhone reaching the Mac while the glasses camera streams | ❓ Unknown: the camera may take over the phone's Wi-Fi (Tailscale should work around it) |

## Troubleshooting

- **No sound in the web app.** Turn off the iPhone's silent mode, then tap **Começar** again: iOS only allows speech after a tap. If you opened the link inside another app, try Safari.
- **The voice sounds English or robotic.** On iPhone, go to Settings › Accessibility › Spoken Content › Voices and download a Portuguese (Brazil) voice.
- **"Pensando…" never ends.** The engine didn't load. Make sure the page is served over HTTP, not opened from a file.
- **The iPhone app can't see the glasses.** Turn on Developer Mode in Meta AI (see above). Only one developer app can be connected at a time.
- **"Mac não encontrado".** The phone and the Mac must be on the same network, or both on Tailscale. Also check that `board_server.py` is running.
- **The Mac server says you hit a limit.** Your Claude subscription's usage window is used up. Wait for it to reset, or tap the moves by hand.

## Ideas for contributors

- **Read the board on the device**, with no AI: compare which squares changed (for example with Apple's Vision homography after a one-time 4-corner calibration).
- **Use a local vision model** (Ollama) on the Mac as another free reader.
- **Keep one `claude` process alive** using stream-json input, so reads skip the start-up cost.
- **Add an English voice and move phrasing** (moves are currently spoken in Portuguese only).
- **Add a Display mode** for Meta Ray-Ban Display glasses, to show the move on the lens.

## Project layout

```
app/
  index.html        board, rules, Stockfish worker, spoken phrasing (shared by everything)
  stockfish.js      Stockfish 10, asm.js build
  chess.min.js      chess.js 0.10.3
  licenses/         third-party licenses
ios/
  project.yml       XcodeGen spec
  Config/           Info.plist, entitlements
  XadrezNoOuvido/   SwiftUI app: glasses session, camera, move readers, speech
mac/
  board_server.py   HTTP server that reads moves with Claude Code
```

## License

**GPL-3.0** (see [LICENSE](LICENSE)), because the project ships Stockfish.

- [Stockfish](https://github.com/official-stockfish/Stockfish), JS build by [niklasf/stockfish.js](https://github.com/niklasf/stockfish.js): GPL-3.0
- [chess.js](https://github.com/jhlywa/chess.js): BSD-2-Clause
- The Meta Wearables Device Access Toolkit isn't included in this repo. Xcode downloads it, and it has Meta's own license.
