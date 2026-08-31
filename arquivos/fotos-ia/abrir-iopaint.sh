#!/usr/bin/env bash
# Sobe o IOPaint (remocao de objetos com o modelo LaMa, em CPU) e abre no navegador.
#
#   abrir-iopaint.sh                -> abre a pasta ~/Imagens
#   abrir-iopaint.sh /cam/foto.jpg  -> abre a pasta onde a foto esta
#
# Os resultados vao para ~/Imagens/IOPaint. O original nunca e sobrescrito.

set -u
BASE="$HOME/.local/opt/fotos-ia"
BIN="$BASE/iopaint-venv/bin/iopaint"
PORTA=8422
SAIDA="$HOME/Imagens/IOPaint"
LOG="$BASE/iopaint.log"

alvo="${1:-$HOME/Imagens}"
if [ -f "$alvo" ]; then entrada="$(dirname "$alvo")"; else entrada="$alvo"; fi
[ -d "$entrada" ] || entrada="$HOME/Imagens"
mkdir -p "$SAIDA" "$entrada"

aviso() {
  notify-send -a "Apagar objetos" -u "${3:-normal}" \
    -h string:x-canonical-private-synchronous:iopaint \
    -i image-x-generic "$1" "$2" 2>/dev/null
}

# Ja esta no ar? So abre o navegador.
if ss -ltn 2>/dev/null | grep -q ":$PORTA "; then
  xdg-open "http://127.0.0.1:$PORTA" >/dev/null 2>&1 &
  exit 0
fi

aviso "Iniciando" "Carregando o modelo. Uns 10 segundos."
nohup "$BIN" start --model=lama --device=cpu \
      --host=127.0.0.1 --port="$PORTA" \
      --input "$entrada" --output-dir "$SAIDA" \
      >"$LOG" 2>&1 &

for _ in $(seq 1 40); do
  if ss -ltn 2>/dev/null | grep -q ":$PORTA "; then
    xdg-open "http://127.0.0.1:$PORTA" >/dev/null 2>&1 &
    aviso "Pronto" "Resultados vão para ~/Imagens/IOPaint"
    exit 0
  fi
  sleep 2
done

aviso "Não subiu" "Veja o log em $LOG" critical
exit 1
