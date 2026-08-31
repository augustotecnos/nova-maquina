"""
Apagar objeto — abre a foto no IOPaint, para remover objetos e pessoas
reconstruindo o fundo (equivalente ao "apagar generativo" do Windows).

Ao contrario do "Remover fundo", este precisa de interacao: voce pinta por
cima do que quer sumir. Por isso abre uma interface no navegador em vez de
processar direto.

Depende de ~/.local/opt/fotos-ia/abrir-iopaint.sh
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

LANCADOR = os.path.expanduser("~/.local/opt/fotos-ia/abrir-iopaint.sh")

FORMATOS = {
    "image/jpeg", "image/png", "image/webp", "image/tiff",
    "image/bmp", "image/avif", "image/heif",
}


class ApagarObjeto(GObject.GObject, Nautilus.MenuProvider):

    def _caminho(self, arquivo):
        if arquivo.is_directory() or arquivo.get_mime_type() not in FORMATOS:
            return None
        caminho = Gio.File.new_for_uri(arquivo.get_uri()).get_path()
        return caminho if caminho and os.path.isfile(caminho) else None

    def _acao(self, _menu, caminho):
        subprocess.Popen(
            [LANCADOR, caminho],
            start_new_session=True,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    def get_file_items(self, arquivos):
        # So faz sentido com uma imagem de cada vez: o proximo passo e pintar
        # a mascara a mao.
        if len(arquivos) != 1 or not os.access(LANCADOR, os.X_OK):
            return []

        caminho = self._caminho(arquivos[0])
        if not caminho:
            return []

        item = Nautilus.MenuItem(
            name="ApagarObjeto::acao",
            label="Apagar objeto…",
            tip="Abre no IOPaint para você pintar o que deve sumir",
        )
        item.connect("activate", self._acao, caminho)
        return [item]
