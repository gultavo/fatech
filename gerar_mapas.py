"""Protótipo local. Coordenadas de entrada: longitude/latitude em WGS84.

Não conecta ao LagoForm, não busca imagens e não infere áreas afetadas.
As dependências geográficas são importadas apenas na geração dos mapas.
"""

import argparse
from collections import Counter
import hashlib
import json
import math
from pathlib import Path
import re
import tempfile
import textwrap


def numero(valor):
    if isinstance(valor, bool):
        raise ValueError("coordenada não pode ser booleana")
    resultado = float(valor)
    if not math.isfinite(resultado):
        raise ValueError("coordenada precisa ser finita")
    return resultado


def coordenada(longitude, latitude):
    lon, lat = numero(longitude), numero(latitude)
    if not (-180 <= lon <= 180 and -80 < lat < 84):
        raise ValueError("coordenada fora do intervalo aceito neste protótipo UTM")
    return lon, lat


def validar_entrada(dados):
    """Separa registros utilizáveis e rejeitados sem corrigir posições por chute."""
    if not isinstance(dados, dict) or dados.get("crs") != "EPSG:4326":
        raise ValueError("Informe crs=EPSG:4326 e coordenadas WGS84. Não apenas renomeie outro CRS.")
    registros = dados.get("ocorrencias")
    if not isinstance(registros, list) or not registros:
        raise ValueError("ocorrencias precisa conter uma lista não vazia")
    ids = Counter(str(r.get("id", "")).strip() for r in registros if isinstance(r, dict))
    validos, rejeitados = [], []
    for indice, registro in enumerate(registros, start=1):
        try:
            if not isinstance(registro, dict):
                raise ValueError("registro não é um objeto")
            identificador = str(registro.get("id") or "").strip()
            if not identificador or len(identificador) > 80:
                raise ValueError("id obrigatório, com até 80 caracteres")
            if ids[identificador] > 1:
                raise ValueError("id duplicado; revise todas as ocorrências com esse id")
            lon, lat = coordenada(registro.get("longitude"), registro.get("latitude"))
            vertices = registro.get("vertices")
            if vertices is not None:
                if not isinstance(vertices, list):
                    raise ValueError("vertices precisa ser uma lista de pares [longitude, latitude]")
                pares = []
                for vertice in vertices:
                    if not isinstance(vertice, list) or len(vertice) != 2:
                        raise ValueError("cada vértice precisa conter [longitude, latitude]")
                    pares.append(coordenada(*vertice))
                if len(set(pares)) < 3:
                    raise ValueError("polígono precisa de pelo menos três vértices distintos")
                vertices = pares
            validos.append({
                "id": identificador, "longitude": lon, "latitude": lat,
                "descricao": str(registro.get("descricao", "")), "vertices": vertices,
            })
        except (ValueError, TypeError, OverflowError) as erro:
            rejeitados.append({"indice": indice, "registro": registro, "motivo": str(erro)})
    return validos, rejeitados


def nome_seguro(identificador):
    parte = re.sub(r"[^a-zA-Z0-9_-]+", "_", identificador)[:45].strip("_") or "registro"
    sufixo = hashlib.sha256(identificador.encode("utf-8")).hexdigest()[:12]
    return f"ro_{parte}_{sufixo}.png"


def enquadramento(limites, margem_m):
    """Retângulo quadrado para exibição, nunca limite de uma ocorrência."""
    xmin, ymin, xmax, ymax = map(float, limites)
    if not all(math.isfinite(v) for v in (xmin, ymin, xmax, ymax, margem_m)):
        raise ValueError("limites e margem precisam ser finitos")
    if margem_m <= 0 or xmin > xmax or ymin > ymax:
        raise ValueError("limites ou margem inválidos")
    centro_x, centro_y = (xmin + xmax) / 2, (ymin + ymax) / 2
    metade = max(xmax - xmin, ymax - ymin) / 2 + margem_m
    return centro_x - metade, centro_y - metade, centro_x + metade, centro_y + metade


def gerar(dados, destino, margem_m=250, base=None):
    if not math.isfinite(margem_m) or margem_m <= 0:
        raise ValueError("margem_m precisa ser positiva e finita")
    registros, rejeitados = validar_entrada(dados)
    try:
        import geopandas as gpd
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        from shapely.geometry import Point, Polygon, box
        from shapely.validation import explain_validity
    except ImportError as erro:
        raise RuntimeError("Instale as dependências: python -m pip install -r requirements.txt") from erro

    # Um ponto e uma área são objetos diferentes, vinculados pelo mesmo id.
    pontos, areas = [], []
    for registro in registros:
        poligono = None
        if registro["vertices"] is not None:
            poligono = Polygon(registro["vertices"])
            if poligono.is_empty or not poligono.is_valid or poligono.area == 0:
                rejeitados.append({"registro": registro, "motivo": "polígono inválido: " + explain_validity(poligono)})
                continue
        atributos = {k: v for k, v in registro.items() if k != "vertices"}
        pontos.append({**atributos, "geometry": Point(registro["longitude"], registro["latitude"])})
        if poligono is not None:
            areas.append({"id": registro["id"], "geometry": poligono})

    # Nova pasta por execução: não sobrescreve mapas anteriores.
    destino = Path(destino)
    destino.mkdir(parents=True, exist_ok=True)
    saida = Path(tempfile.mkdtemp(prefix="lote_", dir=destino))
    (saida / "rejeitados.json").write_text(json.dumps(rejeitados, ensure_ascii=False, indent=2), encoding="utf-8")
    if not pontos:
        raise ValueError(f"Nenhuma ocorrência válida. Consulte {saida / 'rejeitados.json'}")

    pontos_geo = gpd.GeoDataFrame(pontos, crs="EPSG:4326")
    areas_geo = gpd.GeoDataFrame(areas, geometry="geometry", crs="EPSG:4326") if areas else None
    geometrias = list(pontos_geo.geometry) + (list(areas_geo.geometry) if areas else [])
    conjunto = gpd.GeoSeries(geometrias, crs="EPSG:4326")
    limites_geo = conjunto.total_bounds
    if limites_geo[2] - limites_geo[0] > 1 or limites_geo[3] - limites_geo[1] > 1:
        raise ValueError("Lote geograficamente disperso (>1 grau). Separe por local e confira coordenadas invertidas.")
    crs_metrico = conjunto.estimate_utm_crs()
    pontos_m = pontos_geo.to_crs(crs_metrico)
    areas_m = areas_geo.to_crs(crs_metrico) if areas else None
    todas_m = conjunto.to_crs(crs_metrico)

    camada = None
    if base:
        arquivo_base = Path(base)
        if not arquivo_base.is_file():
            raise ValueError("A base deve ser um arquivo geográfico local existente")
        camada = gpd.read_file(arquivo_base)
        if camada.crs is None:
            raise ValueError("Base sem CRS. Defina o sistema correto antes de importar")
        if camada.empty or camada.geometry.isna().any() or not camada.is_valid.all():
            raise ValueError("Base vazia ou com geometrias inválidas")
        camada = camada.to_crs(crs_metrico)

    plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 9})
    fonte = str(dados.get("fonte", "Dados fornecidos pelo usuário"))
    ficticio = dados.get("ficticio") is True

    def desenhar(titulo, pontos_visiveis, areas_visiveis, limites, nome, detalhe=""):
        fig, ax = plt.subplots(figsize=(9, 10))
        fig.subplots_adjust(left=.14, right=.94, bottom=.22, top=.84)
        try:
            recorte = box(*limites)  # Apenas janela de visualização.
            if camada is not None:
                visivel = camada.loc[camada.intersects(recorte)]
                if not visivel.empty:
                    visivel.plot(ax=ax, color="#dbe6ed", edgecolor="#8697a6", linewidth=.7)
            if areas_visiveis is not None and not areas_visiveis.empty:
                areas_visiveis.plot(ax=ax, facecolor="#ffcf8a", edgecolor="#9d5700", alpha=.65)
            pontos_visiveis.plot(ax=ax, color="#cf3937", markersize=45, edgecolor="white", zorder=5)
            # Rótulos em massa ficam no índice para evitar sobreposição no mapa geral.
            if len(pontos_visiveis) == 1:
                linha = pontos_visiveis.iloc[0]
                ax.annotate(textwrap.shorten(linha.id, width=35, placeholder="…"),
                            (linha.geometry.x, linha.geometry.y), xytext=(7, 7),
                            textcoords="offset points", fontsize=9)
            ax.set_xlim(limites[0], limites[2])
            ax.set_ylim(limites[1], limites[3])
            ax.set_aspect("equal")
            ax.ticklabel_format(style="plain", useOffset=False)
            ax.grid(alpha=.22)
            ax.set_xlabel("Coordenada E (metros)")
            ax.set_ylabel("Coordenada N (metros)")
            ax.annotate("N de grade", xy=(.94, .94), xytext=(.94, .81),
                        xycoords="axes fraction", ha="center", fontsize=8,
                        arrowprops={"arrowstyle": "-|>", "color": "#203f4d"})
            # Escala gráfica em metros do CRS projetado (não escala numérica de impressão).
            largura = limites[2] - limites[0]
            alvo = largura / 4
            unidade = 10 ** math.floor(math.log10(alvo))
            barra = max(v * unidade for v in (1, 2, 5, 10) if v * unidade <= alvo)
            x, y = limites[0] + largura * .07, limites[1] + largura * .07
            ax.plot([x, x + barra], [y, y], color="#172f3a", linewidth=3)
            ax.text(x + barra / 2, y + largura * .02, f"{barra:g} m", ha="center", fontsize=8)
            fig.text(.14, .94, "FATECH  /  PROTÓTIPO DE MAPAS", fontsize=10, color="#256075")
            fig.text(.14, .90, textwrap.shorten(titulo, width=64, placeholder="…"), fontsize=17, weight="bold")
            notas = ["DEMONSTRAÇÃO COM DADOS FICTÍCIOS" if ficticio else "PRÉVIA PARA REVISÃO TÉCNICA",
                     f"CRS de exibição: {crs_metrico.to_string()}. Ponto vermelho: ocorrência.",
                     "Área laranja: vértices informados; nenhum limite é inferido." if areas else "Sem polígonos informados; pontos não representam áreas.",
                     "Base local fornecida pelo usuário." if camada is not None else "Sem imagem ou base geográfica de fundo. Não é mapa final de localização."]
            notas += textwrap.wrap("Fonte: " + fonte, width=98)[:2]
            if detalhe:
                notas += textwrap.wrap(detalhe, width=98)[:2]
            fig.text(.14, .04, "\n".join(notas), fontsize=8, color="#394752", linespacing=1.6)
            fig.savefig(saida / nome, dpi=150, facecolor="white")
        finally:
            plt.close(fig)

    desenhar("Visão geral das ocorrências", pontos_m, areas_m,
             enquadramento(todas_m.total_bounds, margem_m), "mapa_geral.png")
    indice = []
    for _, ponto in pontos_m.iterrows():
        selecionado = pontos_m.loc[pontos_m.id == ponto.id]
        area = areas_m.loc[areas_m.id == ponto.id] if areas_m is not None else None
        geoms = [ponto.geometry] + (list(area.geometry) if area is not None else [])
        limites = gpd.GeoSeries(geoms, crs=crs_metrico).total_bounds
        nome = nome_seguro(ponto.id)
        detalhe = f"Latitude {ponto.latitude:.6f}; longitude {ponto.longitude:.6f}. {ponto.descricao}"
        desenhar(f"Ocorrência {ponto.id}", selecionado, area, enquadramento(limites, margem_m), nome, detalhe)
        indice.append({"id": ponto.id, "arquivo": nome, "latitude": ponto.latitude,
                       "longitude": ponto.longitude, "descricao": ponto.descricao})
    (saida / "ocorrencias.geojson").write_text(pontos_geo.to_json(), encoding="utf-8")
    if areas_geo is not None:
        (saida / "areas_informadas.geojson").write_text(areas_geo.to_json(), encoding="utf-8")
    resumo = {"status": "previa_para_revisao", "ficticio": ficticio, "fonte": fonte,
              "crs_origem": "EPSG:4326", "crs_exibicao": crs_metrico.to_string(),
              "margem_m": margem_m, "gerados": len(indice), "rejeitados": len(rejeitados),
              "mapa_geral": "mapa_geral.png", "ocorrencias": indice}
    (saida / "indice.json").write_text(json.dumps(resumo, ensure_ascii=False, indent=2), encoding="utf-8")
    return saida, resumo


def main():
    parser = argparse.ArgumentParser(description="Gera prévias de mapas por ocorrência, sem internet.")
    parser.add_argument("entrada", type=Path, help="JSON de ocorrências WGS84")
    parser.add_argument("--saida", type=Path, default=Path("saidas"))
    parser.add_argument("--margem", type=float, default=250, help="Margem por lado, em metros; padrão: 250")
    parser.add_argument("--base", type=Path, help="Base vetorial local autorizada, como GeoJSON ou GeoPackage")
    args = parser.parse_args()
    try:
        dados = json.loads(args.entrada.read_text(encoding="utf-8-sig"))
        pasta, resumo = gerar(dados, args.saida, args.margem, args.base)
    except (OSError, ValueError, RuntimeError) as erro:
        parser.exit(1, f"Erro: {erro}\n")
    print(f"{resumo['gerados']} mapas individuais + 1 geral. Rejeitados: {resumo['rejeitados']}.")
    print(f"Saída: {pasta.resolve()}")


if __name__ == "__main__":
    main()
