# FATECH — primeira base do gerador de mapas

Protótipo Python da etapa que transforma coordenadas em mapas por ocorrência.
Não é o sistema completo e ainda não foi integrado ao LagoForm.

## O que está implementado

- Leitura de um JSON com id, latitude, longitude e descrição.
- Separação de registros inválidos, incluindo ids duplicados.
- Conversão dos pontos WGS84 para uma projeção UTM local antes de usar metros.
- Enquadramento geral e um PNG por ocorrência, vinculados pelo id no índice.
- Polígono opcional somente quando os vértices são fornecidos explicitamente.
- Base vetorial local opcional, sem precisar de internet na execução.
- Nova pasta por lote, evitando sobrescrever saídas anteriores.

O exemplo contém **três ocorrências fictícias válidas e uma inválida**. Nenhuma
delas representa uma vistoria, irregularidade ou limite real da Lago Azul.

## Executar no Windows

Requer Python 3.10 ou superior. Na pasta do projeto, execute:

```powershell
py -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe gerar_mapas.py exemplo_ficticio.json
```

Não é necessário ativar o ambiente ou alterar a política de execução do PowerShell.
A instalação inicial depende de internet.

No Linux/macOS:

```bash
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements.txt
.venv/bin/python gerar_mapas.py exemplo_ficticio.json
```

Para conferir as validações e a geração depois de instalar:

```powershell
.\.venv\Scripts\python.exe -m unittest -v
```

## Saída esperada

A execução cria uma subpasta em `saidas/`, contendo:

| Arquivo | Conteúdo |
| --- | --- |
| `mapa_geral.png` | Enquadramento dos pontos e áreas informadas |
| `ro_*.png` | Um mapa por ocorrência válida |
| `indice.json` | Relação entre id, coordenada, descrição e arquivo |
| `rejeitados.json` | Registros que precisam de correção, com motivo |
| `ocorrencias.geojson` | Pontos em WGS84 para continuar trabalhando em GIS |
| `areas_informadas.geojson` | Somente os polígonos explicitamente fornecidos, quando houver |

## Como GeoPandas e Shapely entram

GeoPandas organiza as ocorrências geográficas, transforma o CRS e desenha os dados.
Shapely representa pontos, polígonos e a janela de enquadramento:

```python
from shapely.geometry import Point, Polygon, box

ponto = Point(-52.2, -27.2)  # longitude primeiro, latitude depois
# Polygon(vertices) apenas se vertices descreverem um contorno informado.
# box(...) cria o retângulo de exibição, não uma área de irregularidade.
```

Matplotlib monta os PNGs. Não há Google Earth Engine nesta versão.

## Colocar uma base geográfica

Sem base, o resultado é uma **prévia geométrica com grade e coordenadas**, não um
mapa final de localização. Para incluir uma base vetorial autorizada da empresa:

```powershell
.\.venv\Scripts\python.exe gerar_mapas.py exemplo_ficticio.json --base base_local.geojson --margem 250
```

O programa não inclui nem baixa uma base real. A opção `--base` aceita arquivo
vetorial local com CRS, como GeoJSON ou GeoPackage. Não aceita imagem JPEG solta
nem imagem de satélite nesta versão. A aparência das camadas é provisória.

## Cuidados que fazem parte do escopo

1. Coordenadas devem ser longitude/latitude WGS84 (`EPSG:4326`), em graus decimais.
   Se a empresa usa outro CRS, os dados devem ser transformados corretamente;
   apenas mudar o rótulo do CRS desloca os dados de forma incorreta.
2. O protótipo trabalha com um lote local, com extensão máxima de 1 grau em cada
   eixo e latitudes entre -80 e 84. Lotes maiores são recusados para revisão.
3. As validações não detectam toda coordenada trocada ou incorreta que ainda esteja
   em um intervalo plausível. Conferir no mapa continua necessário.
4. A margem é medida no CRS UTM. Não é limite de propriedade nem de área afetada.
5. Vértices devem vir na ordem do contorno, em pares `[longitude, latitude]`.
   Polígonos inválidos são rejeitados, nunca consertados ou inferidos silenciosamente.
6. Rótulos do mapa geral não são desenhados em massa. O índice preserva os ids.
7. A seta indica norte da grade UTM. A barra usa metros da projeção. Ainda faltam
   as regras de escala, camadas, legenda e diagramação aprovadas pela empresa.
8. Descrições extensas são abreviadas apenas no PNG; o texto completo fica no índice.

## Estado dos testes nesta entrega

As validações sem dependências geográficas foram testadas. A instalação de
GeoPandas/Shapely foi bloqueada no ambiente de preparação; por isso, **a geração
de mapas e os testes de integração não foram executados nem validados visualmente**.
Os testes de integração estão incluídos e rodam depois da instalação local.
As faixas de versões de `requirements.txt` não são um ambiente travado e validado.

## Próximo passo com a Lago Azul

Obter um pequeno lote autorizado de coordenadas e **um mapa real já aprovado**.
Isso permitirá adaptar a entrada do LagoForm/CSV e conferir enquadramento, base,
escala e nomes dos arquivos. Não há importação CSV ou API do LagoForm nesta versão.

Áudio/transcrição, app móvel, banco de dados e relatórios completos continuam fora
desta primeira base. GEE só deve entrar se uma necessidade concreta de imagens
ou processamento geoespacial justificar essa integração.

## Documentação de referência

- [GeoPandas: projeções e ordem longitude/latitude](https://geopandas.org/en/stable/docs/user_guide/projections.html)
- [GeoPandas: geração de mapas](https://geopandas.org/en/stable/docs/user_guide/mapping.html)
- [Shapely: Polygon](https://shapely.readthedocs.io/en/stable/reference/shapely.Polygon.html)
