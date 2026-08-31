#!/usr/bin/env python3
"""Daemon de ditado: mantem o modelo Whisper carregado e transcreve via socket unix."""
import os, socket, sys
from faster_whisper import WhisperModel

RT    = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
SOCK  = os.path.join(RT, "ditado.sock")
MODEL = os.environ.get("DITADO_MODEL", "small")
LANG  = os.environ.get("DITADO_LANG", "pt")
PROMPT = os.environ.get("DITADO_PROMPT",
    "Transcricao em portugues do Brasil, com pontuacao e acentuacao corretas.")

print(f"carregando modelo {MODEL}...", flush=True)
model = WhisperModel(MODEL, device="cpu", compute_type="int8",
                     cpu_threads=max(1, (os.cpu_count() or 2) - 1))

if os.path.exists(SOCK):
    os.unlink(SOCK)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(SOCK)
os.chmod(SOCK, 0o600)
srv.listen(4)
print("pronto", flush=True)

while True:
    conn, _ = srv.accept()
    try:
        wav = conn.recv(4096).decode().strip()
        segs, _ = model.transcribe(
            wav, language=LANG, beam_size=1, vad_filter=True,
            condition_on_previous_text=False, initial_prompt=PROMPT,
        )
        text = " ".join(s.text.strip() for s in segs).strip()
        conn.sendall(text.encode())
    except Exception as e:
        print(f"erro: {e}", file=sys.stderr, flush=True)
        try: conn.sendall(b"")
        except Exception: pass
    finally:
        conn.close()
