#!/usr/bin/env python3
"""Reads the opponent's chess move from a glasses photo using Claude Code on this Mac.

The iPhone app posts a frame plus the expected position and legal moves; this server runs
`claude -p` (your own Claude subscription, no API key) and answers which legal move the photo shows.

Run:  python3 board_server.py            (then type the address and code it prints into the iPhone app)
Only the Python standard library is needed.
"""

import argparse
import base64
import json
import os
import re
import secrets
import socket
import subprocess
import sys
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

TOKEN_FILE = Path.home() / ".xadrez-no-ouvido-token"

SYSTEM_PROMPT = (
    "You read physical chessboards from photos taken by smart glasses worn by one of the players. "
    "You reason briefly, then give the answer alone on the last line."
)


def load_token():
    """Same code across restarts, so the iPhone only needs it once."""
    if TOKEN_FILE.exists():
        return TOKEN_FILE.read_text().strip()
    token = secrets.token_hex(3)
    TOKEN_FILE.write_text(token)
    return token


def lan_ip():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("10.255.255.255", 1))  # no packet is sent; this just picks the outgoing interface
            return s.getsockname()[0]
    except OSError:
        return "127.0.0.1"


def build_prompt(fen, my_color, legal):
    mine, theirs = ("White", "Black") if my_color == "w" else ("Black", "White")
    legal_list = ", ".join("{} ({})".format(m["san"], m["uci"]) for m in legal)
    return (
        "The person wearing the camera plays {mine}, so the {mine} pieces are the ones closest to the camera.\n"
        "Expected position on the physical board right now (FEN): {fen}\n"
        "It is {theirs}'s turn. {theirs}'s legal moves: {legal_list}.\n\n"
        "Compare the photo with that position. If {theirs} has completed exactly one of these moves "
        "(the piece is released on its new square, no hand over the board), answer with that move's UCI string "
        "followed by HIGH or LOW, for example: e7e5 HIGH\n"
        "Before answering, check each candidate move against the photo: the move's starting square must now be "
        "EMPTY, and the piece on its destination square must have the right shape (knight, pawn, bishop...). "
        "Several moves can end on the same square, so the empty starting square decides between them.\n"
        "Answer HIGH when that starting square is clearly empty and a matching piece stands on the destination, "
        "even if the photo is taken at an angle. Answer LOW only if a piece or square is hidden or blurred.\n"
        "Otherwise answer exactly: NONE (no move made yet, a hand still on a piece, the board cut off, blurry or "
        "mostly hidden, or you can't tell which move it was).\n"
        "Think briefly, then put the answer alone on the last line."
    ).format(mine=mine, theirs=theirs, fen=fen, legal_list=legal_list)


def ask_claude(image_b64, prompt, model, timeout):
    """One headless Claude Code turn: image in over stream-json, no tools, plain text out."""
    message = {
        "type": "user",
        "message": {
            "role": "user",
            "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": image_b64}},
                {"type": "text", "text": prompt},
            ],
        },
        "parent_tool_use_id": None,
    }
    cmd = [
        "claude", "-p",
        "--model", model,
        "--safe-mode",
        "--tools", "",
        "--max-turns", "1",
        "--no-session-persistence",
        "--effort", "low",  # with the empty-starting-square check, low is as accurate as medium and twice as fast
        "--system-prompt", SYSTEM_PROMPT,
        # Images only go in over stream-json, and stream-json input requires stream-json output
        "--input-format", "stream-json",
        "--output-format", "stream-json",
        "--verbose",
    ]
    # With ANTHROPIC_API_KEY set, `claude -p` bills the API instead of your subscription
    env = {k: v for k, v in os.environ.items() if k != "ANTHROPIC_API_KEY"}
    proc = subprocess.run(
        cmd, input=json.dumps(message) + "\n", capture_output=True, text=True, timeout=timeout, env=env
    )
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout).strip()[:300] or "claude exited with code {}".format(proc.returncode))
    # One JSON event per line; the answer is in the final "result" event
    for line in reversed(proc.stdout.strip().splitlines()):
        try:
            data = json.loads(line)
        except ValueError:
            continue
        if isinstance(data, dict) and data.get("type") == "result":
            if data.get("is_error"):
                raise RuntimeError(str(data.get("result"))[:300])
            return str(data["result"])
    raise RuntimeError("unexpected claude output: " + proc.stdout[:300])


def parse_answer(text, legal_ucis):
    """Accept only a move from the legal list; anything else counts as no move."""
    # The reasoning before it may name moves it ruled out, so only the last line is the answer
    lines = [line for line in text.strip().splitlines() if line.strip()]
    answer = lines[-1] if lines else ""
    for token in re.findall(r"\b([a-h][1-8][a-h][1-8][qrbn]?)\b", answer.lower()):
        if token in legal_ucis:
            confidence = "high" if re.search(r"\bhigh\b", answer, re.IGNORECASE) else "low"
            return {"move": token, "confidence": confidence}
    return {"move": "none", "confidence": "low"}


class Handler(BaseHTTPRequestHandler):
    server_version = "XadrezNoOuvido/1.0"

    def _send(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _authorized(self):
        return secrets.compare_digest(self.headers.get("Authorization", ""), "Bearer " + self.server.token)

    def do_GET(self):
        if self.path != "/health":
            return self._send(404, {"error": "not found"})
        if not self._authorized():
            return self._send(401, {"error": "wrong code"})
        self._send(200, {"ok": True, "model": self.server.model})

    def do_POST(self):
        if self.path != "/move":
            return self._send(404, {"error": "not found"})
        if not self._authorized():
            return self._send(401, {"error": "wrong code"})
        try:
            length = int(self.headers.get("Content-Length", "0"))
            req = json.loads(self.rfile.read(length))
            image_b64 = req["image_jpeg_base64"]
            legal = req["legal"]
            fen = req["fen"]
            my_color = req.get("my_color", "w")
        except (ValueError, KeyError, TypeError):
            return self._send(400, {"error": "bad request"})
        if not legal:
            return self._send(200, {"move": "none", "confidence": "low"})

        if self.server.save_dir:
            stamp = datetime.now().strftime("%H%M%S_%f")
            (self.server.save_dir / "frame_{}.jpg".format(stamp)).write_bytes(base64.b64decode(image_b64))
            # The position the app expected, so a frame can be replayed against the same prompt
            (self.server.save_dir / "frame_{}.json".format(stamp)).write_text(
                json.dumps({"fen": fen, "my_color": my_color, "legal": legal}))

        started = time.time()
        try:
            text = ask_claude(image_b64, build_prompt(fen, my_color, legal), self.server.model, self.server.timeout)
        except subprocess.TimeoutExpired:
            return self._send(504, {"error": "Claude Code demorou demais"})
        except (RuntimeError, OSError) as exc:
            log("erro: {}".format(exc))
            return self._send(502, {"error": str(exc)[:300]})
        answer = parse_answer(text, {m["uci"] for m in legal})
        last_line = text.strip().splitlines()[-1] if text.strip() else ""
        log("{:.1f}s  {} {}  (resposta: {!r})".format(time.time() - started, answer["move"], answer["confidence"], last_line[:80]))
        self._send(200, answer)

    def log_message(self, fmt, *args):
        pass  # keep the terminal for the per-move lines above


def log(line):
    print("[{}] {}".format(datetime.now().strftime("%H:%M:%S"), line), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--model", default="opus", help="Claude Code model alias: opus (reads glasses photos best), sonnet, haiku (faster)")
    parser.add_argument("--timeout", type=int, default=60, help="seconds to wait for each Claude Code call")
    parser.add_argument("--save-frames", metavar="DIR", help="save every received frame here, to check what the glasses see")
    args = parser.parse_args()

    if subprocess.run(["which", "claude"], capture_output=True).returncode != 0:
        sys.exit("Não achei o comando `claude`. Instale o Claude Code e faça login antes.")
    if os.environ.get("ANTHROPIC_API_KEY"):
        print("Aviso: ANTHROPIC_API_KEY está definida. O servidor ignora ela para usar sua assinatura.")

    server = ThreadingHTTPServer(("0.0.0.0", args.port), Handler)
    server.token = load_token()
    server.model = args.model
    server.timeout = args.timeout
    server.save_dir = Path(args.save_frames) if args.save_frames else None
    if server.save_dir:
        server.save_dir.mkdir(parents=True, exist_ok=True)

    print()
    print("  Xadrez no Ouvido · servidor do Mac")
    print("  No iPhone, em Ajustes › Leitura pelo Mac, coloque:")
    print("    Endereço: http://{}:{}".format(lan_ip(), args.port))
    print("    Código:   {}".format(server.token))
    print("  Modelo: {}   (Ctrl+C para parar)".format(args.model))
    print()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
