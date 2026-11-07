"""Testes do wrapper de escala e do vigia do JDownloader.

Rodar da raiz do repositório:  python3 -m unittest discover -s testes -v

O que depende do GNOME de verdade (sinal de troca de monitor, notificação com
botão) não está aqui — isso se confere trocando de monitor com o programa
aberto. Aqui fica a parte que dá para isolar: a conta da escala, a leitura do
processo e a marcação da janela.
"""

import importlib.machinery
import importlib.util
import json
import os
import stat
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
WRAPPER = RAIZ / "arquivos" / "jdownloader" / "jdownloader"
VIGIA = RAIZ / "arquivos" / "jdownloader" / "jdownloader-vigia"


def carregar_vigia():
    """Importa o vigia, que é um script sem extensão .py."""
    carregador = importlib.machinery.SourceFileLoader("jdownloader_vigia", str(VIGIA))
    spec = importlib.util.spec_from_loader("jdownloader_vigia", carregador)
    modulo = importlib.util.module_from_spec(spec)
    carregador.exec_module(modulo)
    return modulo


def executavel(pasta: Path, nome: str, corpo: str) -> Path:
    arquivo = pasta / nome
    arquivo.write_text("#!/bin/sh\n" + corpo + "\n")
    arquivo.chmod(arquivo.stat().st_mode | stat.S_IXUSR)
    return arquivo


class EscalaDoWrapper(unittest.TestCase):
    """`jdownloader --escala` imprime a escala que o monitor atual pede."""

    def escala(self, xrdb_saida: str, texto: str = "1.0") -> str:
        with tempfile.TemporaryDirectory() as tmp:
            falsos = Path(tmp)
            # xrdb e gsettings falsos: o resto do PATH continua o de verdade.
            executavel(falsos, "xrdb", f"printf '%s' '{xrdb_saida}'")
            executavel(falsos, "gsettings", f"echo '{texto}'")
            env = dict(os.environ, PATH=f"{falsos}:{os.environ['PATH']}")
            env.pop("J2D_UISCALE", None)
            r = subprocess.run([str(WRAPPER), "--escala"], env=env,
                               capture_output=True, text=True, timeout=10)
            self.assertEqual(r.returncode, 0, r.stderr)
            return r.stdout.strip()

    def test_tv_a_125_por_cento_pede_2(self):
        self.assertEqual(self.escala("Xft.dpi:\t192\n"), "2")

    def test_monitor_a_100_por_cento_pede_1(self):
        self.assertEqual(self.escala("Xft.dpi:\t96\n"), "1")

    def test_escala_de_texto_nao_conta_como_escala_de_janela(self):
        self.assertEqual(self.escala("Xft.dpi:\t240\n", texto="1.25"), "2")

    def test_sem_xft_dpi_cai_para_1(self):
        self.assertEqual(self.escala(""), "1")

    def test_ignora_j2d_uiscale_herdado(self):
        # O vigia pergunta "o que o monitor pede", não "o que já está setado".
        with tempfile.TemporaryDirectory() as tmp:
            falsos = Path(tmp)
            executavel(falsos, "xrdb", "printf 'Xft.dpi:\\t96\\n'")
            executavel(falsos, "gsettings", "echo 1.0")
            env = dict(os.environ, PATH=f"{falsos}:{os.environ['PATH']}", J2D_UISCALE="2")
            r = subprocess.run([str(WRAPPER), "--escala"], env=env,
                               capture_output=True, text=True, timeout=10)
            self.assertEqual(r.stdout.strip(), "1")


class LeituraDoProcesso(unittest.TestCase):
    """O vigia acha o JDownloader aberto e lê a escala com que ele partiu."""

    @classmethod
    def setUpClass(cls):
        cls.vigia = carregar_vigia()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.pasta = Path(self.tmp.name)
        self.processos = []

    def tearDown(self):
        for p in self.processos:
            p.kill()
            p.wait()
            p.stdin.close()
        self.tmp.cleanup()

    def iniciar(self, nome_do_executavel, args, env_extra=None):
        # "read" segura o shell parado sem trocar de binário: um "exec sleep"
        # mudaria o nome do processo (comm) de "java" para "sleep".
        exe = executavel(self.pasta, nome_do_executavel, "read _")
        env = dict(os.environ)
        env.pop("J2D_UISCALE", None)
        env.update(env_extra or {})
        p = subprocess.Popen([str(exe), *args], env=env, stdin=subprocess.PIPE)
        self.processos.append(p)
        time.sleep(0.2)
        return p

    def test_acha_java_rodando_o_jdownloader_jar(self):
        p = self.iniciar("java", ["-jar", "/x/JDownloader 2.0/JDownloader.jar"])
        self.assertIn(p.pid, self.vigia.pids_do_jd())

    def test_acha_tambem_o_reinicio_apos_atualizar(self):
        p = self.iniciar("java", ["-jar", "JDownloader.jar", "-afterupdate"])
        self.assertIn(p.pid, self.vigia.pids_do_jd())

    def test_ignora_outro_programa_que_cita_o_jar(self):
        p = self.iniciar("editor", ["/x/JDownloader.jar"])
        self.assertNotIn(p.pid, self.vigia.pids_do_jd())

    def test_le_a_escala_do_ambiente_do_processo(self):
        p = self.iniciar("java", ["-jar", "JDownloader.jar"], {"J2D_UISCALE": "2"})
        self.assertEqual(self.vigia.escala_do_processo(p.pid), 2)

    def test_sem_a_variavel_o_java_partiu_em_1(self):
        p = self.iniciar("java", ["-jar", "JDownloader.jar"])
        self.assertEqual(self.vigia.escala_do_processo(p.pid), 1)


class Decisao(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.vigia = carregar_vigia()

    def test_escalas_diferentes_pedem_reabrir(self):
        self.assertTrue(self.vigia.precisa_reabrir(atual=2, esperada=1))

    def test_mesma_escala_nao_pede(self):
        self.assertFalse(self.vigia.precisa_reabrir(atual=1, esperada=1))

    def test_botao_reabrir_reabre(self):
        self.assertTrue(self.vigia.acao_reabre("reabrir"))

    def test_clique_no_corpo_do_aviso_tambem_reabre(self):
        # Sem ação "default", o GNOME trata esse clique como "abrir o app" e
        # descarta o aviso sem avisar o vigia — foi o que aconteceu no 1º teste.
        self.assertTrue(self.vigia.acao_reabre("default"))
        self.assertIn("default", self.vigia.ACOES_DO_AVISO[::2])

    def test_outra_acao_nao_reabre(self):
        self.assertFalse(self.vigia.acao_reabre("outra"))


class JanelaMaximizada(unittest.TestCase):
    """Ao reabrir, a janela volta maximizada em vez do tamanho salvo na escala errada."""

    @classmethod
    def setUpClass(cls):
        cls.vigia = carregar_vigia()

    def test_marca_maximizada_e_preserva_o_resto(self):
        with tempfile.TemporaryDirectory() as tmp:
            arq = Path(tmp) / "lastframestatus.json"
            arq.write_text('{"extendedState":"NORMAL","height":415,"width":686,"visible":true}')
            self.vigia.marcar_maximizado(arq)
            dados = json.loads(arq.read_text())
            self.assertEqual(dados["extendedState"], "MAXIMIZED_BOTH")
            self.assertEqual(dados["height"], 415)
            self.assertEqual(dados["width"], 686)
            self.assertIs(dados["visible"], True)

    def test_arquivo_ausente_nao_quebra(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.vigia.marcar_maximizado(Path(tmp) / "nao-existe.json")


if __name__ == "__main__":
    unittest.main()
