#!/usr/bin/env bash
# Recaptura desta máquina o que dá para recapturar sozinho.
#
# O que é substituído direto: listas de Flatpak e Snap, e os arquivos que só
# existem aqui (daemon do ditado, extensões do Nautilus, scripts de foto).
# O que fica só para conferência, porque exige curadoria: os pacotes do apt e
# as preferências do dconf — saem em arquivos "-atual" para você comparar.
set -euo pipefail

AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$AQUI"
say() { printf '\033[1;34m==>\033[0m %s\n' "$1"; }

say "Flatpak"
{ echo "# Aplicativos Flatpak, do Flathub."
  flatpak list --app --columns=application,origin | awk '$2=="flathub"{print $1}' | sort
} > /tmp/flatpak-novo.txt
grep -vE "^(com.valvesoftware.Steam|net.lutris.Lutris|com.heroicgameslauncher.hgl)$" \
     /tmp/flatpak-novo.txt > listas/flatpak.txt

say "Snap (só os que não vêm com o Ubuntu)"
{ echo "# Snaps instalados à mão (o Firefox e o Thunderbird já vêm com o Ubuntu)."
  snap list | awk 'NR>1{print $1}' | grep -vE "^(bare|core[0-9]*|cups|desktop-security-center|firefox|firmware-updater|gnome-[0-9]|gtk-common-themes|mesa-|prompting-client|snap-store|snapd|snapd-desktop-integration|thunderbird)" | sort
} > listas/snap.txt

say "Arquivos próprios"
cp -f ~/.local/share/ditado/server.py                      arquivos/ditado/
cp -f ~/.local/bin/ditado                                  arquivos/ditado/
cp -f ~/.config/systemd/user/ditado.service                arquivos/ditado/
~/.local/share/ditado/venv/bin/pip list --format=freeze 2>/dev/null \
  | grep -iE "^(faster-whisper|ctranslate2|av|onnxruntime|tokenizers)=" > arquivos/ditado/requirements.txt
cp -f ~/.local/share/nautilus-python/extensions/{copiar-caminho,remover-fundo,apagar-objeto}.py arquivos/nautilus/ 2>/dev/null || true
cp -f ~/.local/opt/fotos-ia/{worker-remover-fundo.py,abrir-iopaint.sh} arquivos/fotos-ia/ 2>/dev/null || true

say "Pacotes do apt instalados à mão (para conferência)"
comm -23 <(apt-mark showmanual | LC_ALL=C sort -u) \
         <(gzip -dc /var/log/installer/initial-status.gz 2>/dev/null | sed -n "s/^Package: //p" | LC_ALL=C sort -u) \
  > listas/apt-detectado.txt

say "Preferências atuais do dconf (para conferência)"
{ dconf dump /org/gnome/desktop/interface/ | sed '1s|^\[/\]|[org/gnome/desktop/interface]|'
  echo
  dconf dump /org/gnome/settings-daemon/plugins/media-keys/ | sed '1s|^\[/\]|[org/gnome/settings-daemon/plugins/media-keys]|'
} | sed "s|$HOME|@HOME@|g" > dconf/preferencias-atual.ini

printf '\n\033[1;32m✓\033[0m Atualizado. Compare o que exige curadoria:\n'
printf '   diff listas/apt-detectado.txt <(cat listas/apt-*.txt | sed -e "s/#.*//" -e "/^$/d" | sort)\n'
printf '   diff dconf/preferencias.ini dconf/preferencias-atual.ini\n'
