#!/usr/bin/env python3
"""Acrescenta uma extensão à lista de habilitadas do GNOME Shell.

O 'gnome-extensions enable' falha enquanto o shell não releu o disco — ele
responde que a extensão não existe. Escrever direto na chave funciona, e passa
a valer na próxima sessão.
"""
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio  # noqa: E402


def main(uuid):
    s = Gio.Settings.new("org.gnome.shell")
    atuais = list(s.get_strv("enabled-extensions"))
    if uuid in atuais:
        print(f"  · já habilitada: {uuid}")
        return 0
    s.set_strv("enabled-extensions", atuais + [uuid])
    Gio.Settings.sync()
    print(f"  ✓ habilitada: {uuid}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("uso: habilitar-extensao.py <uuid>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
