"""
Remover fundo — item de menu do Nautilus, equivalente ao recurso do Fotos
do Windows 11.

Aparece so em arquivos de imagem. Dispara o worker em segundo plano, que
carrega o modelo uma vez para toda a selecao e avisa por notificacao quando
termina. O resultado vai para a mesma pasta, como "<nome>-sem-fundo.png".

Depende de:
  ~/.local/opt/fotos-ia/rembg-venv          (ambiente com o rembg)
  ~/.local/opt/fotos-ia/worker-remover-fundo.py
"""

import os
import subprocess

import gi

for _v in ("4.1", "4.0"):
    try:
        gi.require_version("Nautilus", _v)
        break
    except ValueError:
        continue

from gi.repository import Gio, GObject, Nautilus  # noqa: E402

BASE = os.path.expanduser("~/.local/opt/fotos-ia")
PYTHON = os.path.join(BASE, "rembg-venv", "bin", "python")
WORKER = os.path.join(BASE, "worker-remover-fundo.py")

# Formatos que o Pillow abre e para os quais faz sentido recortar o fundo.
FORMATOS = {
    "image/jpeg", "image/png", "image/webp", "image/tiff",
    "image/bmp", "image/x-portable-pixmap", "image/avif", "image/heif",
}


def _caminho_local(arquivo):
    """So devolve caminho se o arquivo estiver no disco local."""
    caminho = Gio.File.new_for_uri(arquivo.get_uri()).get_path()
    if caminho and os.path.isfile(caminho):
        return caminho
    return None


class RemoverFundo(GObject.GObject, Nautilus.MenuProvider):

    def _disponivel(self):
        return os.access(PYTHON, os.X_OK) and os.path.isfile(WORKER)

    def _elegiveis(self, arquivos):
        saida = []
        for a in arquivos:
            if a.is_directory() or a.get_mime_type() not in FORMATOS:
                continue
            caminho = _caminho_local(a)
            if caminho:
                saida.append(caminho)
        return saida

    def _acao(self, _menu, caminhos):
        subprocess.Popen(
            [PYTHON, WORKER] + caminhos,
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def get_file_items(self, arquivos):
        if not self._disponivel():
            return []

        caminhos = self._elegiveis(arquivos)
        if not caminhos:
            return []

        if len(caminhos) == 1:
            rotulo = "Remover fundo"
            dica = "Salva um PNG transparente ao lado do original"
        else:
            rotulo = "Remover fundo de %d imagens" % len(caminhos)
            dica = "A primeira demora mais; as seguintes saem rápido"

        item = Nautilus.MenuItem(
            name="RemoverFundo::acao", label=rotulo, tip=dica
        )
        item.connect("activate", self._acao, caminhos)
        return [item]
