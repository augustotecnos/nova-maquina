# Máquina nova

A script that takes a freshly installed Ubuntu to a ready workstation:
packages, applications, my own tools, GNOME extensions and keyboard shortcuts.
Built for **Ubuntu 26.04 with GNOME on Wayland**.

[Português](README.md) · **English**

```bash
git clone https://github.com/augustotecnos/nova-maquina.git
cd nova-maquina
./instalar.sh --simular      # prints everything it would do, touching nothing
./instalar.sh                # does it
```

No network on the new machine? Copy the whole folder on a USB stick — the
script does not need to live in a git repository.

Safe to run again: every stage checks before acting.

> The script, its stages and its flags are in Portuguese, since it rebuilds a
> Brazilian desktop. This page documents them as they are, so the commands you
> read here are the commands you type.

## Stages

| Stage | What it does |
|---|---|
| `sistema` | checks Ubuntu/GNOME/Wayland and refreshes the apt indexes |
| `repos` | Chrome, Edge, VS Code, Docker, the Ulauncher and Grub Customizer PPAs, Flathub, Tailscale |
| `apt` | the packages, in groups (`listas/apt-*.txt`) |
| `flatpak` | applications from Flathub |
| `snap` | OnlyOffice and Zotero |
| `grupos` | the `input`, `docker`, `kvm` and `libvirt` groups, plus the `uinput` rule |
| `ferramentas` | clones and installs [ocr-tela](https://github.com/augustotecnos/ocr-tela) and [colar-avancado](https://github.com/augustotecnos/colar-avancado), plus the `claude` CLI |
| `ditado` | offline voice dictation on `Super+H` (faster-whisper on CPU) |
| `fotos` | background removal with `rembg`; object removal with IOPaint (optional) |
| `nautilus` | "Copy path", "Remove background" and "Erase object" in the file manager menu |
| `extensoes` | GSConnect, Draw on GNOME and GJS OSK |
| `prefs` | dark theme, shortcuts, and freeing up `Super+H` |
| `resumo` | the list of what still depends on you |

Run only part of it, or skip:

```bash
./instalar.sh --so ditado,fotos     # only these stages
./instalar.sh --sem jogos,snap      # every stage except these
```

## Options

| Option | Effect |
|---|---|
| `-n`, `--simular` | prints each command instead of running it |
| `-l`, `--listar` | lists the stages |
| `--so a,b` / `--sem a,b` | picks or skips stages |
| `--sem-jogos` | does not install Steam, Lutris and Heroic |
| `--sem-opcionais` | does not install Tailscale |
| `--com-iopaint` | installs IOPaint (1.6 GB, isolated Python 3.11) |
| `--com-experimentos` | installs what sits in `apt-experimentos.txt` |

The `sudo` password is only asked for when a chosen stage actually touches the
system — `--so prefs`, for instance, runs without asking for anything.

## What it deliberately does not install

`listas/apt-experimentos.txt` keeps what was tried on this machine and left
behind, each with the reason in a comment: `onboard`, `maliit` and
`matchbox-keyboard` are X11-era virtual keyboards that come up crippled on
Wayland (the **GJS OSK** extension replaced them); `flameshot` cannot register
a global shortcut on Wayland; `esearch` was dropped in favour of `ocr-tela`.
Install them with `--com-experimentos` if you want to reassess.

## What no script can solve

1. **Logging out and back in.** New groups and GNOME extensions only take
   effect in a new session — on Wayland there is no `Alt+F2` → `r`.
2. **Pairing the phone in GSConnect** and then turning on the two clipboard
   keys, which ship disabled (the command is printed by the `resumo` stage).
3. **Accepting once** the "Remote desktop" dialog on the first use of Colar
   Avançado — that is what stores the portal permission.
4. **Signing in** to `claude`, to Tailscale and to the application accounts.
5. The **Whisper model** (~460 MB) downloads on the first dictation.

## Maintenance

When this machine changes, recapture whatever can be recaptured on its own:

```bash
./atualizar-listas.sh
```

It replaces the Flatpak and Snap lists and the files that only exist here (the
dictation daemon, the Nautilus extensions, the photo scripts) outright, and
writes `listas/apt-detectado.txt` and `dconf/preferencias-atual.ini` for you to
compare — those two need curation, because the raw apt list carries dozens of
base packages and the dconf dump carries machine-specific entries.

## Layout

```
instalar.sh                    the script
atualizar-listas.sh            recaptures from this machine
listas/                        packages, by group, with comments
dconf/preferencias.ini         preferences and shortcuts (@HOME@ is substituted at apply time)
arquivos/ditado/               daemon, command, service and pinned dependencies
arquivos/nautilus/             Python extensions for the file manager
arquivos/fotos-ia/             the rembg worker and the IOPaint launcher
arquivos/udev/                 rule that opens /dev/uinput to the input group
arquivos/habilitar-extensao.py appends a UUID to the enabled-extensions key
```

Each run is logged to `~/.cache/nova-maquina.log`.

## This is one specific machine's setup

Published as a reference, not as a product: the lists are **my** application
choices and the shortcuts are mine. If you are going to reuse it, edit the
files under `listas/` and `dconf/preferencias.ini` before running — or run it
with `--simular` first and see whether you agree with all of it.

What may be worth having regardless of the lists: the stage structure with a
simulation mode, the apt repository detection that is not fooled by `.sources`
files or by a `.list.disabled`, and the three traps documented at the top of
their functions.

## License

MIT. See [LICENSE](LICENSE).
