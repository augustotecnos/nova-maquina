# Máquina nova

Um script para sair do Ubuntu recém-instalado até a máquina de trabalho pronta:
pacotes, aplicativos, as ferramentas próprias, as extensões do GNOME e os
atalhos de teclado. Feito para **Ubuntu 26.04 com GNOME sobre Wayland**.

```bash
git clone https://github.com/augustotecnos/nova-maquina.git
cd nova-maquina
./instalar.sh --simular      # mostra tudo que faria, sem tocar em nada
./instalar.sh                # faz
```

Sem rede na máquina nova? Copie a pasta inteira por pendrive: o script não
depende de estar num repositório git.

É seguro rodar de novo: cada etapa confere antes de agir.

## Etapas

| Etapa | O que faz |
|---|---|
| `sistema` | confere Ubuntu/GNOME/Wayland e atualiza os índices do apt |
| `repos` | Chrome, Edge, VS Code, Docker, PPAs do Ulauncher e do Grub Customizer, Flathub, Tailscale |
| `apt` | os pacotes, em grupos (`listas/apt-*.txt`) |
| `flatpak` | aplicativos do Flathub |
| `snap` | OnlyOffice e Zotero |
| `grupos` | grupos `input`, `docker`, `kvm`, `libvirt` e a regra do `uinput` |
| `ferramentas` | clona e instala o [ocr-tela](https://github.com/augustotecnos/ocr-tela) e o [colar-avancado](https://github.com/augustotecnos/colar-avancado), mais o CLI do `claude` |
| `ditado` | ditado por voz offline em `Super+H` (faster-whisper em CPU) |
| `fotos` | remover fundo com `rembg`; apagar objeto com IOPaint (opcional) |
| `nautilus` | "Copiar caminho", "Remover fundo" e "Apagar objeto" no menu do gerenciador de arquivos |
| `extensoes` | GSConnect, Draw on GNOME e GJS OSK |
| `prefs` | tema escuro, atalhos e a liberação do `Super+H` |
| `resumo` | a lista do que ainda depende de você |

Rodar só uma parte, ou pular:

```bash
./instalar.sh --so ditado,fotos
./instalar.sh --sem jogos,snap
```

## Opções

| Opção | Efeito |
|---|---|
| `-n`, `--simular` | imprime cada comando em vez de executar |
| `-l`, `--listar` | mostra as etapas |
| `--so a,b` / `--sem a,b` | escolhe ou pula etapas |
| `--sem-jogos` | não instala Steam, Lutris e Heroic |
| `--sem-opcionais` | não instala o Tailscale |
| `--com-iopaint` | instala o IOPaint (1,6 GB, Python 3.11 isolado) |
| `--com-experimentos` | instala o que está em `apt-experimentos.txt` |

A senha do `sudo` só é pedida se alguma etapa escolhida mexer no sistema —
`--so prefs`, por exemplo, roda sem pedir nada.

## O que ele deliberadamente não instala

`listas/apt-experimentos.txt` guarda o que já foi testado nesta máquina e
ficou para trás, com o motivo em comentário: `onboard`, `maliit` e
`matchbox-keyboard` são teclados virtuais da era X11 que no Wayland sobem
degradados (a extensão **GJS OSK** os substituiu); o `flameshot` não registra
atalho global no Wayland; o `esearch` foi descartado em favor do `ocr-tela`.
Instale com `--com-experimentos` se quiser reavaliar.

## O que nenhum script resolve

1. **Sair e entrar na sessão.** Grupos novos e extensões do GNOME só valem em
   sessão nova — no Wayland não existe `Alt+F2` → `r`.
2. **Parear o celular no GSConnect** e, depois, ligar as duas chaves de
   clipboard, que vêm desligadas de fábrica (o comando está no `resumo`).
3. **Aceitar uma vez** o diálogo "Área de trabalho remota" no primeiro uso do
   Colar Avançado — é o que guarda a permissão do portal.
4. **Fazer login** no `claude`, no Tailscale e nas contas dos aplicativos.
5. O **modelo do Whisper** (~460 MB) baixa no primeiro ditado.

## Manutenção

Quando esta máquina mudar, recapture o que dá para recapturar sozinho:

```bash
./atualizar-listas.sh
```

Ele substitui direto as listas de Flatpak e Snap e os arquivos que só existem
aqui (o daemon do ditado, as extensões do Nautilus, os scripts de foto), e
gera `listas/apt-detectado.txt` e `dconf/preferencias-atual.ini` para você
comparar — essas duas exigem curadoria, porque a lista crua do apt vem com
dezenas de pacotes de base e o dump do dconf vem com coisas específicas da
máquina.

## Estrutura

```
instalar.sh                    o script
atualizar-listas.sh            recaptura desta máquina
listas/                        pacotes, por grupo, com comentários
dconf/preferencias.ini         preferências e atalhos (@HOME@ é trocado na hora)
arquivos/ditado/               daemon, comando, serviço e dependências fixadas
arquivos/nautilus/             extensões em Python do gerenciador de arquivos
arquivos/fotos-ia/             worker do rembg e o lançador do IOPaint
arquivos/udev/                 regra que libera o /dev/uinput ao grupo input
arquivos/habilitar-extensao.py acrescenta um UUID à lista de extensões ativas
```

O registro de cada execução fica em `~/.cache/nova-maquina.log`.

## Isto é a configuração de uma máquina específica

Publicado como referência, não como produto: as listas são as **minhas**
escolhas de aplicativos, e os atalhos são os meus. Se for aproveitar, edite os
arquivos de `listas/` e o `dconf/preferencias.ini` antes de rodar — ou rode com
`--simular` primeiro e veja se concorda com tudo.

O que talvez valha para qualquer um, independentemente das listas: a estrutura
de etapas com simulação, a detecção de repositório apt que não se engana com
`.sources` nem com `.list.disabled`, e as três armadilhas anotadas no topo de
cada função.

## Licença

MIT. Veja [LICENSE](LICENSE).
