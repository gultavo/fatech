import importlib.util
import math
from pathlib import Path
import tempfile
import unittest

from gerar_mapas import enquadramento, gerar, nome_seguro, validar_entrada


def entrada(registros):
    return {"crs": "EPSG:4326", "ocorrencias": registros}


def registro(identificador="A", **campos):
    return {"id": identificador, "longitude": -52.2, "latitude": -27.2, **campos}


class Validacoes(unittest.TestCase):
    def test_coordenada_valida(self):
        validos, erros = validar_entrada(entrada([registro()]))
        self.assertEqual(len(validos), 1)
        self.assertEqual(erros, [])

    def test_crs_desconhecido(self):
        with self.assertRaises(ValueError):
            validar_entrada({"crs": "EPSG:3857", "ocorrencias": [registro()]})

    def test_sem_coordenada(self):
        validos, erros = validar_entrada(entrada([registro(latitude=None)]))
        self.assertFalse(validos)
        self.assertEqual(len(erros), 1)

    def test_fora_do_intervalo(self):
        for campo in (math.nan, math.inf, True, 95):
            with self.subTest(campo=campo):
                validos, erros = validar_entrada(entrada([registro(latitude=campo)]))
                self.assertFalse(validos)
                self.assertEqual(len(erros), 1)

    def test_duplicados_rejeita_ambos(self):
        validos, erros = validar_entrada(entrada([registro(), registro()]))
        self.assertFalse(validos)
        self.assertEqual(len(erros), 2)

    def test_id_vazio(self):
        validos, erros = validar_entrada(entrada([registro("")]))
        self.assertFalse(validos)
        self.assertEqual(len(erros), 1)

    def test_vertices_insuficientes(self):
        validos, erros = validar_entrada(entrada([registro(vertices=[[-52, -27], [-52, -27]])]))
        self.assertFalse(validos)
        self.assertEqual(len(erros), 1)

    def test_enquadramento_ponto_unico(self):
        self.assertEqual(enquadramento((10, 20, 10, 20), 50), (-40, -30, 60, 70))

    def test_enquadramento_preserva_limites(self):
        limites = enquadramento((10, 20, 100, 40), 25)
        self.assertEqual(limites, (-15, -40, 125, 100))

    def test_margem_invalida(self):
        for margem in (0, -1, math.inf):
            with self.assertRaises(ValueError):
                enquadramento((0, 0, 1, 1), margem)

    def test_nome_sem_caminho(self):
        nome = nome_seguro("../../CON/ocorrência")
        self.assertNotIn("/", nome)
        self.assertNotIn("..", nome)
        self.assertTrue(nome.endswith(".png"))

    def test_nomes_distintos_apos_sanitizacao(self):
        self.assertNotEqual(nome_seguro("A/B"), nome_seguro("A B"))


TEM_BIBLIOTECAS = all(importlib.util.find_spec(m) for m in ("geopandas", "shapely", "matplotlib"))


@unittest.skipUnless(TEM_BIBLIOTECAS, "Dependências geográficas não instaladas")
class Integracao(unittest.TestCase):
    def test_gera_arquivos_e_nao_sobrescreve(self):
        with tempfile.TemporaryDirectory() as pasta:
            dados = entrada([registro(), registro("ERRO", latitude=None)])
            saida, resumo = gerar(dados, pasta)
            self.assertEqual(resumo["gerados"], 1)
            self.assertEqual(resumo["rejeitados"], 1)
            for nome in ("mapa_geral.png", "indice.json", "ocorrencias.geojson", "rejeitados.json", nome_seguro("A")):
                self.assertTrue((saida / nome).is_file())
            outra, _ = gerar(dados, pasta)
            self.assertNotEqual(saida, outra)

    def test_poligono_invalido_nao_e_corrigido_silenciosamente(self):
        cruzado = [[-52.20, -27.20], [-52.19, -27.19], [-52.20, -27.19], [-52.19, -27.20]]
        with tempfile.TemporaryDirectory() as pasta:
            _, resumo = gerar(entrada([registro(), registro("B", vertices=cruzado)]), pasta)
            self.assertEqual(resumo["gerados"], 1)
            self.assertEqual(resumo["rejeitados"], 1)

    def test_poligono_valido_exportado(self):
        vertices = [[-52.201, -27.201], [-52.199, -27.201], [-52.2, -27.199]]
        with tempfile.TemporaryDirectory() as pasta:
            saida, _ = gerar(entrada([registro(vertices=vertices)]), pasta)
            self.assertTrue((saida / "areas_informadas.geojson").exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
