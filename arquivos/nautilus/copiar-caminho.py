"""
Copiar caminho — item de menu do Nautilus equivalente ao "Copiar como caminho"
do Windows 11.

Acrescenta ao menu de contexto:
  - "Copiar caminho"          ao clicar sobre arquivos ou pastas selecionados
  - "Copiar caminho da pasta" ao clicar no espaco vazio de uma pasta

Varios itens selecionados viram uma linha por caminho.

Instalacao: este arquivo em ~/.local/share/nautilus-python/extensions/
            e o pacote python3-nautilus presente. Depois, `nautilus -q`.
"""

import shlex
import shutil
import subprocess

import gi

# O nome da versao do GIR mudou entre releases do Nautilus; aceita as duas.
for _v in ("4.1", "4.0"):
    try:
        gi.require_version("Nautilus", _v)
        break
    except ValueError:
        continue

gi.require_version("Gdk", "4.0")

from gi.repository import Gdk, Gio, GObject, Nautilus  # noqa: E402

# ---------------------------------------------------------------------------
# Ajuste aqui como o caminho e colocado na area de transferencia:
#
#   "auto"   -> so poe aspas quando o caminho tem espaco ou caractere especial
#               (colar no terminal sempre funciona)
#   "nunca"  -> sempre o caminho cru, sem aspas
#               (colar em caixa de dialogo sempre funciona)
#   "sempre" -> sempre entre aspas, igual ao Windows 11
# ---------------------------------------------------------------------------
ASPAS = "auto"


def _formatar(caminho):
    if ASPAS == "sempre":
        return '"' + caminho.replace('"', '\\"') + '"'
    if ASPAS == "auto":
        # shlex.quote devolve o texto intacto quando nao ha nada a escapar
        return shlex.quote(caminho)
    return caminho


def _caminho_de(arquivo):
    """Caminho local do arquivo; para locais remotos (sftp, mtp) devolve a URI."""
    uri = arquivo.get_uri()
    caminho = Gio.File.new_for_uri(uri).get_path()
    return caminho if caminho else uri


def _copiar(texto):
    """Poe o texto na area de transferencia, com plano B se o GTK falhar."""
    try:
        display = Gdk.Display.get_default()
        if display is not None:
            valor = GObject.Value(str, texto)
            display.get_clipboard().set_content(
                Gdk.ContentProvider.new_for_value(valor)
            )
            return True
    except Exception:
        pass

    for cmd in (["wl-copy"], ["xclip", "-selection", "clipboard"], ["xsel", "-ib"]):
        if shutil.which(cmd[0]):
            try:
                subprocess.run(cmd, input=texto.encode("utf-8"), check=True)
                return True
            except Exception:
                continue
    return False


class CopiarCaminho(GObject.GObject, Nautilus.MenuProvider):

    def _acao(self, _menu, arquivos):
        _copiar("\n".join(_formatar(_caminho_de(a)) for a in arquivos))

    def get_file_items(self, arquivos):
        if not arquivos:
            return []

        if len(arquivos) == 1:
            rotulo = "Copiar caminho"
            dica = _caminho_de(arquivos[0])
        else:
            rotulo = "Copiar %d caminhos" % len(arquivos)
            dica = "Um caminho por linha"

        item = Nautilus.MenuItem(
            name="CopiarCaminho::arquivos", label=rotulo, tip=dica
        )
        item.connect("activate", self._acao, arquivos)
        return [item]

    def get_background_items(self, pasta):
        if pasta is None:
            return []

        item = Nautilus.MenuItem(
            name="CopiarCaminho::pasta",
            label="Copiar caminho da pasta",
            tip=_caminho_de(pasta),
        )
        item.connect("activate", self._acao, [pasta])
        return [item]
