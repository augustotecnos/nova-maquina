#!/usr/bin/env python3
"""
Remove o fundo das imagens passadas como argumento e grava
"<nome>-sem-fundo.png" ao lado de cada original.

Carrega o modelo uma unica vez para a lista inteira: a primeira imagem custa
uns segundos a mais, as seguintes saem bem mais rapido.

Chamado pela extensao do Nautilus, mas funciona sozinho no terminal:
    worker-remover-fundo.py foto1.jpg foto2.jpg
"""

import os
import subprocess
import sys

# Modelos alternativos, todos baixados sob demanda para ~/.rembg:
#   u2net              padrao, 176 MB, equilibrado
#   isnet-general-use  bordas melhores em objetos, 176 MB
#   u2net_human_seg    especifico para pessoas
#   birefnet-general   qualidade maior, bem mais lento em CPU
MODELO = os.environ.get("REMBG_MODELO", "u2net")

APP = "Remover fundo"


def avisar(titulo, corpo, urgencia="normal", tag="remover-fundo"):
    try:
        subprocess.run(
            ["notify-send", "-a", APP, "-u", urgencia,
             "-h", "string:x-canonical-private-synchronous:" + tag,
             "-i", "image-x-generic", titulo, corpo],
            check=False,
        )
    except FileNotFoundError:
        print(f"{titulo}: {corpo}", file=sys.stderr)


def destino(origem):
    """<pasta>/<nome>-sem-fundo.png, sem sobrescrever nada."""
    base, _ = os.path.splitext(origem)
    alvo = base + "-sem-fundo.png"
    n = 2
    while os.path.exists(alvo):
        alvo = f"{base}-sem-fundo-{n}.png"
        n += 1
    return alvo


def main(caminhos):
    if not caminhos:
        return 0

    total = len(caminhos)
    plural = "imagem" if total == 1 else "imagens"
    avisar("Removendo fundo", f"{total} {plural}. A primeira demora mais.")

    try:
        from PIL import Image
        from rembg import new_session, remove
        sessao = new_session(MODELO)
    except Exception as e:
        avisar("Falhou ao iniciar", str(e), "critical")
        return 1

    feitos, erros = [], []
    for caminho in caminhos:
        try:
            with Image.open(caminho) as img:
                saida = remove(img.convert("RGBA"), session=sessao)
            alvo = destino(caminho)
            saida.save(alvo)
            feitos.append(os.path.basename(alvo))
        except Exception as e:
            erros.append(f"{os.path.basename(caminho)}: {e}")

    if erros and not feitos:
        avisar("Não deu certo", "\n".join(erros[:3]), "critical")
        return 1
    if erros:
        avisar("Pronto, com falhas",
               f"{len(feitos)} de {total} salvas.\nFalhou: " + "; ".join(erros[:2]))
        return 1

    if total == 1:
        avisar("Pronto", f"Salvo como {feitos[0]}")
    else:
        avisar("Pronto", f"{total} imagens salvas na mesma pasta")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
