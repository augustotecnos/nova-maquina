#!/usr/bin/env bash
#
# Máquina nova, do zero ao pronto — Ubuntu 26.04 com GNOME sobre Wayland.
#
# Instala os pacotes, os aplicativos Flatpak e Snap, as ferramentas próprias
# (ocr-tela, colar-avancado, ditado por voz, edição de foto com IA), as
# extensões do GNOME e as preferências da área de trabalho.
#
# Uso:
#   ./instalar.sh                    faz tudo
#   ./instalar.sh --simular          mostra o que faria, sem tocar em nada
#   ./instalar.sh --listar           lista as etapas
#   ./instalar.sh --so ditado,fotos  roda só essas etapas
#   ./instalar.sh --sem jogos        pula uma etapa
#
# É seguro rodar de novo: cada etapa confere antes de fazer.

set -uo pipefail

VERSAO="1.0.0"
AQUI="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJETOS="${PROJETOS:-$HOME/Projetos}"
LOG="${LOG:-$HOME/.cache/nova-maquina.log}"

SIMULAR=0
COM_IOPAINT=0
COM_EXPERIMENTOS=0
SEM_JOGOS=0
SEM_OPCIONAIS=0
SO=""
SEM=""

ETAPAS=(sistema repos apt flatpak snap grupos ferramentas ditado fotos nautilus extensoes video nuvem prefs resumo)

declare -A DESCRICAO=(
  [sistema]="checagens do ambiente e atualização dos índices do apt"
  [repos]="repositórios de terceiros (Chrome, Edge, VS Code, Docker, PPAs, Flathub)"
  [apt]="pacotes do apt, por grupo"
  [flatpak]="aplicativos Flatpak do Flathub"
  [snap]="aplicativos Snap"
  [grupos]="grupos do usuário e regra do uinput (para digitar sozinho)"
  [ferramentas]="ocr-tela, colar-avancado e o CLI do claude"
  [ditado]="ditado por voz offline em Super+H (faster-whisper)"
  [fotos]="remover fundo e apagar objeto por IA, no menu do Nautilus"
  [nautilus]="extensões do gerenciador de arquivos"
  [extensoes]="extensões do GNOME Shell"
  [video]="sandbox do Chromium, XWayland em GPU antiga e decodificação de vídeo"
  [nuvem]="OneDrive: cliente de sincronização e atalho para a montagem do GNOME"
  [prefs]="preferências da área de trabalho e atalhos"
  [resumo]="o que ainda depende de você"
)

# ------------------------------------------------------------------ aparência

if [ -t 1 ]; then
  AZUL=$'\033[1;34m'; VERDE=$'\033[1;32m'; AMARELO=$'\033[1;33m'
  VERMELHO=$'\033[1;31m'; FRACO=$'\033[2m'; FORTE=$'\033[1m'; ZERA=$'\033[0m'
else
  AZUL=""; VERDE=""; AMARELO=""; VERMELHO=""; FRACO=""; FORTE=""; ZERA=""
fi

titulo() { printf '\n%s╺━ %s ━╸%s\n' "$AZUL$FORTE" "$1" "$ZERA"; }
passo()  { printf '%s==>%s %s\n' "$AZUL" "$ZERA" "$1"; }
ok()     { printf '%s  ✓%s %s\n' "$VERDE" "$ZERA" "$1"; }
pula()   { printf '%s  ·%s %s\n' "$FRACO" "$ZERA" "$1"; }
aviso()  { printf '%s  !%s %s\n' "$AMARELO" "$ZERA" "$1"; }
falha()  { printf '%s  ✗%s %s\n' "$VERMELHO" "$ZERA" "$1"; }

# As etapas rodam sob "| tee", ou seja, em subshell — variável de array não
# sobreviveria. As anotações vão para um arquivo temporário.
ARQ_PENDENCIAS="$(mktemp -t nova-maquina-pendencias.XXXXXX)"
trap 'rm -f "$ARQ_PENDENCIAS"' EXIT
anotar() { printf '%s\n' "$1" >> "$ARQ_PENDENCIAS"; }

# ----------------------------------------------------------------- utilidades

executar() {
  if [ "$SIMULAR" = 1 ]; then
    printf '%s     $ %s%s\n' "$FRACO" "$*" "$ZERA"
    return 0
  fi
  "$@"
}

executar_sh() {   # para o que precisa de cano, redirecionamento ou expansão
  if [ "$SIMULAR" = 1 ]; then
    printf '%s     $ %s%s\n' "$FRACO" "$1" "$ZERA"
    return 0
  fi
  bash -c "$1"
}

tem_comando() { command -v "$1" >/dev/null 2>&1; }
tem_pacote()  { dpkg -s "$1" >/dev/null 2>&1; }

pedir_sudo() {
  [ "$SIMULAR" = 1 ] && return 0
  sudo -v || { falha "sem sudo não dá para seguir"; exit 1; }
  # mantém vivo enquanto o script roda
  ( while true; do sudo -n true; sleep 50; kill -0 "$$" 2>/dev/null || exit; done ) 2>/dev/null &
}

ler_lista() {     # imprime a lista sem comentários nem linhas vazias
  sed -e 's/#.*//' -e '/^[[:space:]]*$/d' "$1"
}

instalar_apt() {  # instalar_apt <arquivo-de-lista> <rótulo>
  local arquivo="$1" rotulo="$2" faltando=()
  [ -f "$arquivo" ] || { aviso "lista ausente: $arquivo"; return 0; }
  local p
  while read -r p; do
    tem_pacote "$p" || faltando+=("$p")
  done < <(ler_lista "$arquivo")

  if [ ${#faltando[@]} -eq 0 ]; then
    pula "$rotulo: tudo já instalado"
    return 0
  fi
  passo "$rotulo: ${#faltando[@]} pacote(s) — ${faltando[*]}"
  executar sudo apt-get install -y "${faltando[@]}" \
    || aviso "$rotulo: algo não instalou; veja o log e siga"
}

baixar_chave() {  # baixar_chave <url> <destino.gpg>
  local url="$1" destino="$2"
  [ -f "$destino" ] && { pula "chave já existe: $(basename "$destino")"; return 0; }
  executar_sh "curl -fsSL '$url' | sudo gpg --dearmor -o '$destino'" \
    && executar sudo chmod a+r "$destino"
}

fonte_apt() {     # fonte_apt <arquivo.list> <linha deb> <trecho que identifica a fonte>
  local arquivo="/etc/apt/sources.list.d/$1" linha="$2" marca="$3"
  # Procura pelo trecho identificador, não pela linha inteira: a mesma fonte
  # pode já estar no formato antigo (.list) ou no deb822 (.sources), e com a
  # URL escrita de outro jeito. Só conta arquivo ativo — um .list.disabled não.
  if grep -rqsF "$marca" --include='*.list' --include='*.sources' \
       /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null; then
    pula "fonte já existe: $marca"
    return 0
  fi
  executar_sh "echo '$linha' | sudo tee '$arquivo' >/dev/null"
}

# --------------------------------------------------------------------- etapas

etapa_sistema() {
  titulo "Ambiente"
  local id_sistema versao
  id_sistema="$(. /etc/os-release && echo "$ID")"
  versao="$(. /etc/os-release && echo "$VERSION_ID")"
  [ "$id_sistema" = "ubuntu" ] || aviso "feito para Ubuntu; aqui é '$id_sistema' — os pacotes podem divergir"
  passo "Ubuntu $versao ($(lsb_release -cs 2>/dev/null))"

  [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || aviso "a sessão não é Wayland (${XDG_SESSION_TYPE:-?}); as ferramentas próprias supõem Wayland"
  case "${XDG_CURRENT_DESKTOP:-}" in
    *GNOME*) ;;
    *) aviso "área de trabalho '${XDG_CURRENT_DESKTOP:-?}' não é GNOME; extensões e atalhos não vão se aplicar" ;;
  esac

  passo "Atualizando os índices do apt"
  executar sudo apt-get update
}

etapa_repos() {
  titulo "Repositórios de terceiros"
  local arq="amd64"

  passo "Google Chrome"
  baixar_chave "https://dl.google.com/linux/linux_signing_key.pub" "/usr/share/keyrings/google-chrome.gpg"
  fonte_apt "google-chrome.list" \
            "deb [arch=$arq signed-by=/usr/share/keyrings/google-chrome.gpg] https://dl.google.com/linux/chrome/deb/ stable main" \
            "dl.google.com/linux/chrome"

  passo "Microsoft (Edge e VS Code)"
  baixar_chave "https://packages.microsoft.com/keys/microsoft.asc" "/usr/share/keyrings/microsoft.gpg"
  fonte_apt "microsoft-edge.list" \
            "deb [arch=$arq signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" \
            "packages.microsoft.com/repos/edge"
  fonte_apt "vscode.list" \
            "deb [arch=$arq signed-by=/usr/share/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/code stable main" \
            "packages.microsoft.com/repos/code"

  passo "Docker"
  local codinome; codinome="$(lsb_release -cs)"
  if curl -fsI "https://download.docker.com/linux/ubuntu/dists/$codinome/Release" >/dev/null 2>&1; then
    executar sudo install -m 0755 -d /etc/apt/keyrings
    baixar_chave "https://download.docker.com/linux/ubuntu/gpg" "/etc/apt/keyrings/docker.gpg"
    fonte_apt "docker.list" \
              "deb [arch=$arq signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $codinome stable" \
              "download.docker.com"
  else
    aviso "o Docker ainda não publicou repositório para '$codinome' — usando o docker.io do Ubuntu"
    executar sudo apt-get install -y docker.io
    anotar "Docker veio do Ubuntu (docker.io); troque pelo repositório oficial quando ele suportar $codinome"
  fi

  passo "PPAs (Ulauncher e Grub Customizer)"
  for ppa in ppa:agornostal/ulauncher ppa:danielrichter2007/grub-customizer; do
    if grep -rqs "${ppa#ppa:}" /etc/apt/sources.list.d/ 2>/dev/null; then
      pula "PPA já existe: $ppa"
    else
      executar sudo add-apt-repository -y "$ppa"
    fi
  done

  passo "Flathub"
  executar flatpak remote-add --if-not-exists --user flathub https://dl.flathub.org/repo/flathub.flatpakrepo

  if [ "$SEM_OPCIONAIS" = 0 ]; then
    passo "Tailscale (opcional)"
    if tem_comando tailscale; then
      pula "tailscale já instalado"
    else
      executar_sh "curl -fsSL https://tailscale.com/install.sh | sh"
      anotar "Tailscale: entrar com 'sudo tailscale up'"
    fi
  fi

  passo "Relendo os índices"
  executar sudo apt-get update
}

etapa_apt() {
  titulo "Pacotes do apt"
  instalar_apt "$AQUI/listas/apt-base.txt"          "Base"
  instalar_apt "$AQUI/listas/apt-idioma.txt"        "Português do Brasil"
  instalar_apt "$AQUI/listas/apt-desktop.txt"       "Aplicativos"
  instalar_apt "$AQUI/listas/apt-midia.txt"         "Mídia"
  instalar_apt "$AQUI/listas/apt-dev.txt"           "Desenvolvimento"
  instalar_apt "$AQUI/listas/apt-ferramentas.txt"   "Apoio às ferramentas próprias"
  instalar_apt "$AQUI/listas/apt-virtualizacao.txt" "Virtualização"
  [ "$COM_EXPERIMENTOS" = 1 ] && instalar_apt "$AQUI/listas/apt-experimentos.txt" "Experimentos"
  return 0
}

etapa_flatpak() {
  titulo "Flatpak"
  tem_comando flatpak || { aviso "flatpak não está instalado; rode a etapa apt antes"; return 0; }
  local instalados; instalados="$(flatpak list --app --columns=application 2>/dev/null || true)"
  local app
  while read -r app; do
    if grep -qx "$app" <<<"$instalados"; then pula "$app"; else
      passo "$app"; executar flatpak install -y --user flathub "$app" || aviso "$app não instalou"
    fi
  done < <(ler_lista "$AQUI/listas/flatpak.txt")

  if [ "$SEM_JOGOS" = 0 ]; then
    while read -r app; do
      if grep -qx "$app" <<<"$instalados"; then pula "$app"; else
        passo "$app"; executar flatpak install -y --user flathub "$app" || aviso "$app não instalou"
      fi
    done < <(ler_lista "$AQUI/listas/flatpak-jogos.txt")
  else
    pula "jogos pulados (--sem jogos)"
  fi
}

etapa_snap() {
  titulo "Snap"
  tem_comando snap || { aviso "snap não disponível"; return 0; }
  local app
  while read -r app; do
    if snap list "$app" >/dev/null 2>&1; then pula "$app"; else
      passo "$app"; executar sudo snap install "$app" || aviso "$app não instalou"
    fi
  done < <(ler_lista "$AQUI/listas/snap.txt")
}

etapa_grupos() {
  titulo "Grupos e permissões de entrada"
  local g
  for g in input docker kvm libvirt; do
    if getent group "$g" >/dev/null 2>&1; then
      if id -nG "$USER" | tr ' ' '\n' | grep -qx "$g"; then
        pula "já está no grupo $g"
      else
        passo "acrescentando ao grupo $g"
        executar sudo usermod -aG "$g" "$USER"
        anotar "grupo '$g' só passa a valer depois de sair e entrar na sessão"
      fi
    fi
  done

  passo "Regra do udev para o /dev/uinput"
  if [ -f /etc/udev/rules.d/80-uinput.rules ]; then
    pula "regra já existe"
  else
    executar sudo install -Dm644 "$AQUI/arquivos/udev/80-uinput.rules" /etc/udev/rules.d/80-uinput.rules
    executar sudo udevadm control --reload-rules
    executar_sh "sudo udevadm trigger --name-match=uinput || true"
    executar_sh "sudo modprobe uinput || true"
  fi

  passo "Serviço do ydotool (digitação de reserva, sessão local)"
  executar_sh "systemctl --user enable --now ydotool.service 2>/dev/null || true"
}

etapa_ferramentas() {
  titulo "Ferramentas próprias"
  executar mkdir -p "$PROJETOS"

  local repo
  for repo in ocr-tela colar-avancado; do
    if [ -d "$PROJETOS/$repo/.git" ]; then
      passo "$repo: já clonado, atualizando"
      executar_sh "git -C '$PROJETOS/$repo' pull --ff-only || true"
    else
      passo "$repo: clonando"
      executar git clone "https://github.com/augustotecnos/$repo.git" "$PROJETOS/$repo" \
        || { aviso "não consegui clonar $repo"; continue; }
    fi
    passo "$repo: instalando"
    executar_sh "cd '$PROJETOS/$repo' && ./install.sh" || aviso "$repo: instalação incompleta"
  done

  passo "CLI do claude (usado pelas ações de IA do colar-avancado)"
  if tem_comando claude; then
    pula "claude já instalado"
  else
    executar_sh "curl -fsSL https://claude.ai/install.sh | bash"
    anotar "Claude Code: rode 'claude' uma vez e faça login"
  fi
}

etapa_ditado() {
  titulo "Ditado por voz (Super+H)"
  local base="$HOME/.local/share/ditado"
  executar mkdir -p "$base"

  if [ -x "$base/venv/bin/python" ]; then
    pula "ambiente Python já existe"
  else
    passo "criando o ambiente Python"
    executar python3 -m venv "$base/venv"
    executar_sh "'$base/venv/bin/pip' install --upgrade pip -q"
    passo "instalando faster-whisper (uns 200 MB de rodas)"
    executar_sh "'$base/venv/bin/pip' install -q -r '$AQUI/arquivos/ditado/requirements.txt'"
  fi

  passo "instalando o daemon, o comando e o serviço"
  executar install -Dm644 "$AQUI/arquivos/ditado/server.py" "$base/server.py"
  executar install -Dm755 "$AQUI/arquivos/ditado/ditado"    "$HOME/.local/bin/ditado"
  executar install -Dm644 "$AQUI/arquivos/ditado/ditado.service" \
                          "$HOME/.config/systemd/user/ditado.service"
  executar_sh "systemctl --user daemon-reload"
  executar_sh "systemctl --user enable ditado.service >/dev/null 2>&1 || true"
  anotar "Ditado: o modelo (~460 MB) é baixado no primeiro uso; o atalho Super+H vem na etapa prefs"
}

etapa_fotos() {
  titulo "Edição de foto com IA (CPU)"
  local base="$HOME/.local/opt/fotos-ia"
  executar mkdir -p "$base"

  if [ -x "$base/rembg-venv/bin/rembg" ]; then
    pula "rembg já instalado"
  else
    passo "rembg + onnxruntime (só CPU)"
    executar python3 -m venv "$base/rembg-venv"
    executar_sh "'$base/rembg-venv/bin/pip' install -q --upgrade pip"
    # o extra [cli] sozinho NÃO traz motor de inferência: tem de ser [cpu,cli]
    executar_sh "'$base/rembg-venv/bin/pip' install -q 'rembg[cpu,cli]'"
    anotar "rembg: use sempre o modelo u2net (-m u2net); o default virou um modelo de 1 GB com licença não-comercial"
  fi
  executar install -Dm755 "$AQUI/arquivos/fotos-ia/worker-remover-fundo.py" "$base/worker-remover-fundo.py"

  if [ "$COM_IOPAINT" = 1 ]; then
    if [ -x "$base/iopaint-venv/bin/iopaint" ]; then
      pula "iopaint já instalado"
    else
      passo "IOPaint (apagar objeto) — 1,6 GB, Python 3.11 isolado"
      tem_comando uv || executar_sh "curl -LsSf https://astral.sh/uv/install.sh | sh"
      executar_sh "'$HOME/.local/bin/uv' python install 3.11"
      executar_sh "'$HOME/.local/bin/uv' venv --python 3.11 '$base/iopaint-venv'"
      # torch precisa vir do índice de CPU, senão baixa 2,5 GB de CUDA inútil aqui
      executar_sh "'$base/iopaint-venv/bin/pip' install -q torch torchvision --index-url https://download.pytorch.org/whl/cpu"
      executar_sh "'$base/iopaint-venv/bin/pip' install -q iopaint"
      executar install -Dm755 "$AQUI/arquivos/fotos-ia/abrir-iopaint.sh" "$base/abrir-iopaint.sh"
    fi
  else
    pula "IOPaint pulado (use --com-iopaint; são 1,6 GB)"
  fi
}

etapa_nautilus() {
  titulo "Menu do Nautilus"
  tem_pacote python3-nautilus || aviso "python3-nautilus ausente: as extensões não vão carregar"
  local destino="$HOME/.local/share/nautilus-python/extensions"
  executar mkdir -p "$destino"
  local f
  for f in "$AQUI"/arquivos/nautilus/*.py; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
      remover-fundo.py|apagar-objeto.py)
        if [ ! -d "$HOME/.local/opt/fotos-ia" ] && [ "$SIMULAR" = 0 ]; then
          pula "$(basename "$f"): depende da etapa fotos"
          continue
        fi ;;
    esac
    passo "$(basename "$f")"
    executar install -Dm644 "$f" "$destino/$(basename "$f")"
  done
  executar_sh "nautilus -q >/dev/null 2>&1 || true"
}

etapa_extensoes() {
  titulo "Extensões do GNOME Shell"
  tem_comando gnome-extensions || { aviso "gnome-extensions não encontrado"; return 0; }
  local versao_shell; versao_shell="$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)"
  [ -n "$versao_shell" ] || versao_shell="50"

  local uuid
  for uuid in gsconnect@andyholmes.github.io draw-on-gnome@daveprowse.github.io gjsosk@vishram1123.com; do
    if [ -d "$HOME/.local/share/gnome-shell/extensions/$uuid" ] || \
       [ -d "/usr/share/gnome-shell/extensions/$uuid" ]; then
      pula "$uuid já instalada"
    else
      passo "$uuid"
      local info url zip
      info="$(curl -fsSL "https://extensions.gnome.org/extension-info/?uuid=$uuid&shell_version=$versao_shell" 2>/dev/null || true)"
      url="$(printf '%s' "$info" | python3 -c 'import sys,json;
try: print(json.load(sys.stdin).get("download_url",""))
except Exception: print("")' 2>/dev/null)"
      if [ -z "$url" ]; then
        aviso "$uuid: sem versão para o GNOME $versao_shell em extensions.gnome.org"
        anotar "Extensão $uuid: instalar à mão pelo app Extension Manager"
        continue
      fi
      zip="$(mktemp --suffix=.zip)"
      executar_sh "curl -fsSL -o '$zip' 'https://extensions.gnome.org$url'"
      executar gnome-extensions install --force "$zip"
      executar rm -f "$zip"
    fi
    executar python3 "$AQUI/arquivos/habilitar-extensao.py" "$uuid"
  done
  anotar "Extensões do GNOME só carregam depois de sair e entrar na sessão (no Wayland não há Alt+F2 → r)"
}

etapa_video() {
  titulo "Vídeo e aceleração"

  # ---------------------------------------------------- sandbox do Chromium
  # O Ubuntu 24+ liga kernel.apparmor_restrict_unprivileged_userns=1. O
  # postinst de vários pacotes Electron testa apenas "unshare --user true",
  # que passa, conclui que namespaces bastam e deixa o chrome-sandbox sem
  # SUID. Mas a sandbox precisa mapear root dentro do namespace, e isso é
  # negado — o processo de GPU não sobe e o app morre na partida com
  # "GPU process isn't usable. Goodbye.".
  #
  # Não tem relação com a placa de vídeo: acontece igual em máquina nova.
  # O pacote do Chrome não sofre porque já instala o helper com SUID.
  if unshare --user --map-root-user true 2>/dev/null; then
    pula "user namespaces completos; sandbox por setuid desnecessária"
  else
    local s achou=0
    for s in /opt/*/chrome-sandbox; do
      [ -e "$s" ] || continue
      achou=1
      if [ -u "$s" ]; then
        pula "$(basename "$(dirname "$s")"): chrome-sandbox já tem SUID"
      else
        if [ "$SIMULAR" = 1 ] || sudo -n true 2>/dev/null; then
          passo "SUID no chrome-sandbox de $(basename "$(dirname "$s")")"
          executar sudo chmod 4755 "$s"
        else
          # Não abortar por causa disto: numa execução completa o sudo já foi
          # pedido lá no começo; em "--so video" isolado, vira recado.
          aviso "sem sudo agora; rode: sudo chmod 4755 $s"
          anotar "sudo chmod 4755 $s"
        fi
      fi
    done
    if [ "$achou" = 0 ]; then
      pula "nenhum chrome-sandbox em /opt"
    else
      anotar "chrome-sandbox: atualizar o pacote desfaz o SUID. Se um app Electron parar de abrir, rode ./instalar.sh --so video"
    fi
  fi

  # ------------------------------------------- XWayland em GPU pré-GCN
  # Em placas TeraScale (driver de kernel "radeon", anterior ao GCN) o
  # Electron em Wayland nativo fica lento; no XWayland responde bem. Em
  # placa moderna vale o contrário, então isto é condicionado ao driver:
  # máquina nova usa amdgpu, i915, xe, nvidia ou nouveau e não entra aqui.
  local pci_k; pci_k="$(lspci -k 2>/dev/null || true)"
  if [[ "$pci_k" == *"Kernel driver in use: radeon"$'\n'* ]]; then
    local origem destino achou=0
    for origem in /usr/share/applications/ai.opencode.desktop.desktop \
                  /usr/share/applications/opencode-desktop.desktop; do
      [ -f "$origem" ] || continue
      achou=1
      destino="$HOME/.local/share/applications/$(basename "$origem")"
      if grep -q -- "--ozone-platform=x11" "$destino" 2>/dev/null; then
        pula "$(basename "$destino") já força XWayland"
      else
        passo "XWayland em $(basename "$origem")"
        executar mkdir -p "$(dirname "$destino")"
        # insere a flag logo após o binário, preservando o resto da linha
        executar_sh "sed -E 's|^Exec=([^ ]+)|Exec=\\1 --ozone-platform=x11|' '$origem' > '$destino'"
      fi
    done
    if [ "$achou" = 0 ]; then
      pula "OpenCode não instalado"
    else
      executar_sh "update-desktop-database '$HOME/.local/share/applications' 2>/dev/null || true"
      anotar "o menu do GNOME só lê o .desktop novo depois de sair e entrar na sessão"
    fi
  else
    pula "GPU moderna; Wayland nativo é o caminho melhor"
  fi

  # ------------------------------------ decodificação de vídeo por hardware
  # auto-safe deixa o mpv escolher a API (vaapi, nvdec, vulkan...) conforme
  # a máquina. Não fixar uma API aqui: o que serve numa placa quebra noutra.
  local mpvconf="$HOME/.config/mpv/mpv.conf"
  if grep -qE '^[[:space:]]*hwdec[[:space:]]*=' "$mpvconf" 2>/dev/null; then
    pula "mpv já define hwdec"
  else
    passo "mpv: hwdec=auto-safe"
    executar mkdir -p "$(dirname "$mpvconf")"
    executar_sh "printf '%s\\n' '# Decodificacao por hardware; auto-safe escolhe a API conforme a maquina.' 'hwdec=auto-safe' >> '$mpvconf'"
  fi

  # O Haruna usa libmpv mas NÃO lê o mpv.conf — precisa da própria chave, e
  # ela só vale no grupo [Playback].
  local haruna="$HOME/.config/haruna/haruna.conf"
  if [ ! -f "$haruna" ]; then
    pula "Haruna ainda não rodou (cria a config no primeiro uso)"
  elif pgrep -x haruna >/dev/null 2>&1; then
    aviso "Haruna aberto: feche e rode ./instalar.sh --so video (ele reescreve a config ao sair)"
  elif [ "$(python3 -c "
import configparser, sys
c = configparser.ConfigParser(); c.optionxform = str
try: c.read(sys.argv[1], encoding='utf-8')
except Exception: print('nao'); raise SystemExit
print('sim' if c.has_option('Playback','HWDecoding') and c.get('Playback','HWDecoding').lower()=='true' else 'nao')
" "$haruna" 2>/dev/null)" = sim ]; then
    pula "Haruna já usa decodificação por hardware"
  else
    passo "Haruna: HWDecoding=true"
    executar_sh "python3 - '$haruna' <<'FIM'
import configparser, sys
c = configparser.ConfigParser(); c.optionxform = str
c.read(sys.argv[1], encoding='utf-8')
if not c.has_section('Playback'): c.add_section('Playback')
c.set('Playback', 'HWDecoding', 'true')
with open(sys.argv[1], 'w', encoding='utf-8') as f: c.write(f, space_around_delimiters=False)
FIM"
  fi
}

etapa_nuvem() {
  titulo "OneDrive"

  # São dois caminhos que se completam, e vale saber a diferença:
  #   ~/OneDrive        cópia local de verdade, sincronizada pelo daemon
  #   ~/OneDrive-nuvem  montagem do GNOME: mostra a nuvem, não baixa nada

  # ------------------------------------------- cliente de sincronização
  if tem_pacote onedrive; then
    pula "cliente onedrive já instalado"
  else
    passo "instalando o cliente onedrive (abraunegg)"
    executar sudo apt-get install -y onedrive || aviso "onedrive não instalou"
  fi

  local cfg="$HOME/.config/onedrive"
  executar mkdir -p "$cfg"
  if [ -f "$cfg/config" ]; then
    pula "configuração do onedrive já existe"
  else
    passo "escrevendo a configuração"
    executar install -Dm644 "$AQUI/arquivos/onedrive/config" "$cfg/config"
    # O cliente vem com 8 threads fixas e reclama em voz alta quando a máquina
    # tem menos núcleos que isso. Usa o menor entre os núcleos reais e 8.
    local nucleos; nucleos=$(nproc 2>/dev/null || echo 4)
    [ "$nucleos" -gt 8 ] && nucleos=8
    executar_sh "printf '\nthreads = \"%s\"\n' '$nucleos' >> '$cfg/config'"
  fi
  executar install -Dm644 "$AQUI/arquivos/onedrive/sync_list.exemplo" \
                          "$cfg/sync_list.exemplo"

  # O serviço só pode subir depois de autenticado: sem token ele falha, e o
  # unit tem Restart=on-failure com RestartSec=3. O pacote já o deixa habilitado
  # em escopo global (/etc/systemd/user/default.target.wants/), e um
  # "systemctl --user disable" NÃO desfaz isso — o próprio systemd avisa que a
  # unidade continuará subindo. Mascarar é o único freio no escopo do usuário.
  if [ -f "$cfg/refresh_token" ]; then
    passo "ligando o serviço de sincronização"
    executar_sh "systemctl --user unmask onedrive.service >/dev/null 2>&1 || true"
    executar_sh "systemctl --user enable --now onedrive.service >/dev/null 2>&1 || true"
  else
    passo "segurando o serviço até a autenticação"
    executar_sh "systemctl --user mask onedrive.service >/dev/null 2>&1 || true"
    anotar "OneDrive: rode 'onedrive' para autenticar; depois 'systemctl --user unmask onedrive && systemctl --user enable --now onedrive'"
  fi

  # ------------------------------------------- atalho para a montagem do GNOME
  local contas="$HOME/.config/goa-1.0/accounts.conf" ident="" raiz="" drive="" uri=""
  [ -f "$contas" ] && ident=$(grep -A3 '^Provider=ms_graph' "$contas" \
                              | sed -n 's/^Identity=//p' | head -1)
  if [ -z "$ident" ]; then
    anotar "OneDrive: adicione a conta em Configurações → Contas Online → Microsoft 365 e rode './instalar.sh --so nuvem' de novo para criar o atalho"
    return 0
  fi
  passo "conta do GNOME encontrada: $ident"

  local base="/run/user/$(id -u)/gvfs"
  ls -d "$base"/onedrive:host=* >/dev/null 2>&1 \
    || executar_sh "gio mount 'onedrive://$ident/' >/dev/null 2>&1 || true"
  raiz=$(ls -d "$base"/onedrive:host=* 2>/dev/null | head -1)

  if [ -z "$raiz" ]; then
    aviso "não consegui montar agora; o marcador do Nautilus monta no primeiro clique"
  else
    # A raiz da montagem não lista arquivos: lista os drives da conta, e o
    # drive pessoal vem com um nome interno (Bundles_<id>). Os arquivos estão
    # dentro dele — por isso o link aponta um nível abaixo.
    drive=$(find "$raiz" -mindepth 1 -maxdepth 1 -type d -name 'Bundles_*' \
                 -printf '%f\n' 2>/dev/null | head -1)
    passo "atalho ~/OneDrive-nuvem → ${drive:-raiz da conta}"
    executar ln -sfn "$raiz${drive:+/$drive}" "$HOME/OneDrive-nuvem"
  fi

  local bm="$HOME/.config/gtk-3.0/bookmarks"
  uri="onedrive://$ident/$drive"
  if [ -f "$bm" ] && grep -qF "$uri" "$bm"; then
    pula "marcador do Nautilus já existe"
  else
    passo "marcador OneDrive na barra lateral do Nautilus"
    executar mkdir -p "$(dirname "$bm")"
    executar_sh "printf '%s OneDrive\\n' '$uri' >> '$bm'"
  fi

  # Sem isto o link só funciona depois que alguém abre o OneDrive no Nautilus:
  # a montagem gvfs não sobrevive ao fim da sessão.
  local auto="$HOME/.config/autostart/onedrive-montar.desktop"
  if [ -f "$auto" ]; then
    pula "montagem automática já configurada"
  else
    passo "montar o OneDrive ao entrar na sessão"
    executar mkdir -p "$(dirname "$auto")"
    executar_sh "cat > '$auto' <<DESKTOP
[Desktop Entry]
Type=Application
Name=Montar o OneDrive
Comment=Monta a conta Microsoft 365 para o atalho ~/OneDrive-nuvem funcionar
Exec=gio mount onedrive://$ident/
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=10
NoDisplay=true
DESKTOP"
  fi
}

etapa_prefs() {
  titulo "Preferências e atalhos"
  local origem="$AQUI/dconf/preferencias.ini"
  [ -f "$origem" ] || { aviso "preferencias.ini ausente"; return 0; }
  passo "aplicando o dconf"
  if [ "$SIMULAR" = 1 ]; then
    printf '%s     $ sed s|@HOME@|%s|g %s | dconf load /%s\n' "$FRACO" "$HOME" "$origem" "$ZERA"
  else
    sed "s|@HOME@|$HOME|g" "$origem" | dconf load / && ok "preferências aplicadas"
  fi
  anotar "Atalhos: Super+H ditado · Super+Shift+T OCR · Super+Shift+V Colar Avançado · Ctrl+Super+V texto simples · Ctrl+Espaço Ulauncher"
}

etapa_resumo() {
  titulo "O que ainda depende de você"
  cat <<'FIM'
  Coisas que nenhum script resolve sozinho:

  1. Sair e entrar na sessão. Os grupos novos (input, docker) e as extensões
     do GNOME só valem em sessão nova. No Wayland não existe Alt+F2 → r.
  2. GSConnect: parear o celular e, depois de pareado, ligar as duas chaves do
     clipboard — elas vêm desligadas de fábrica:
       BASE=/org/gnome/shell/extensions/gsconnect
       IDS=$(dconf read $BASE/devices | tr -d "[]' " | tr ',' '\n' | grep -v '^$')
       for id in $IDS; do
         dconf write $BASE/device/$id/plugin/clipboard/send-content    true
         dconf write $BASE/device/$id/plugin/clipboard/receive-content true
       done
  3. Colar Avançado: no primeiro uso o GNOME pede permissão de "Área de
     trabalho remota". Aceite uma vez; a permissão fica guardada.
  4. Claude Code: rodar 'claude' e fazer login (as ações de IA dependem disso).
  5. Contas: Chrome, Edge, Brave, Spotify, Telegram, Discord, Steam.
  6. Tailscale: 'sudo tailscale up', se instalado.
  7. OneDrive: a conta Microsoft entra à mão em Configurações → Contas
     Online → Microsoft 365 (o OAuth abre o navegador). Para a pasta local,
     rode 'onedrive' uma vez, autorize, e solte o serviço com
     'systemctl --user unmask onedrive && systemctl --user enable --now onedrive'
     (a etapa nuvem o deixa mascarado justamente até esse momento).
  8. Ditado: o modelo do Whisper (~460 MB) baixa no primeiro uso; fale algo e
     espere alguns segundos a mais nessa primeira vez.
FIM
  if [ -s "$ARQ_PENDENCIAS" ]; then
    printf '\n%s  Anotado durante a execução:%s\n' "$FORTE" "$ZERA"
    sort -u "$ARQ_PENDENCIAS" | while read -r p; do printf '   • %s\n' "$p"; done
  fi
  printf '\n  Registro completo em %s\n' "$LOG"
}

# ------------------------------------------------------------ linha de comando

ajuda() {
  sed -n '3,20p' "$0" | sed 's/^# \{0,1\}//'
  printf '\nOpções:\n'
  printf '  -n, --simular         mostra os comandos sem executar\n'
  printf '  -l, --listar          lista as etapas e sai\n'
  printf '      --so a,b          roda apenas essas etapas\n'
  printf '      --sem a,b         pula essas etapas\n'
  printf '      --sem-jogos       não instala Steam, Lutris e Heroic\n'
  printf '      --sem-opcionais   não instala Tailscale\n'
  printf '      --com-iopaint     instala o IOPaint (1,6 GB)\n'
  printf '      --com-experimentos  instala os teclados virtuais antigos e o flameshot\n'
  printf '  -h, --help            esta ajuda\n'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -n|--simular) SIMULAR=1 ;;
    -l|--listar)
      printf 'Etapas, na ordem:\n'
      for e in "${ETAPAS[@]}"; do printf '  %-12s %s\n' "$e" "${DESCRICAO[$e]}"; done
      exit 0 ;;
    --so)  SO="${2:-}"; shift ;;
    --sem) SEM="${2:-}"; shift ;;
    --sem-jogos) SEM_JOGOS=1 ;;
    --sem-opcionais) SEM_OPCIONAIS=1 ;;
    --com-iopaint) COM_IOPAINT=1 ;;
    --com-experimentos) COM_EXPERIMENTOS=1 ;;
    -h|--help) ajuda; exit 0 ;;
    *) printf 'Opção desconhecida: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

quer_etapa() {
  local e="$1"
  if [ -n "$SO" ]; then [[ ",$SO," == *",$e,"* ]] || return 1; fi
  if [ -n "$SEM" ]; then [[ ",$SEM," == *",$e,"* ]] && return 1; fi
  return 0
}

# ------------------------------------------------------------------- execução

mkdir -p "$(dirname "$LOG")"
{
  printf '\n===== %s — nova-maquina %s%s =====\n' "$(date '+%F %T')" "$VERSAO" \
         "$([ "$SIMULAR" = 1 ] && echo ' (simulação)')"
} >> "$LOG"

printf '%sMáquina nova%s — nova-maquina %s%s\n' "$FORTE" "$ZERA" "$VERSAO" \
       "$([ "$SIMULAR" = 1 ] && echo "  ${AMARELO}[simulação: nada será alterado]${ZERA}")"

# Só pede senha se alguma etapa escolhida realmente mexer no sistema.
PRECISA_ROOT=(sistema repos apt snap grupos video nuvem)
precisa_sudo=0
for etapa in "${PRECISA_ROOT[@]}"; do
  quer_etapa "$etapa" && precisa_sudo=1
done
if [ "$SIMULAR" = 0 ] && [ "$precisa_sudo" = 1 ]; then
  pedir_sudo
elif [ "$SIMULAR" = 0 ]; then
  printf '%s(nenhuma etapa escolhida precisa de sudo)%s\n' "$FRACO" "$ZERA"
fi

for etapa in "${ETAPAS[@]}"; do
  quer_etapa "$etapa" || { printf '%s· pulando %s%s\n' "$FRACO" "$etapa" "$ZERA"; continue; }
  "etapa_$etapa" 2>&1 | tee -a "$LOG"
done

printf '\n%sPronto.%s\n' "$VERDE$FORTE" "$ZERA"
