# FAtech — MVP de vistorias ambientais

Aplicativo Android em Flutter para registrar visitas e ocorrências em campo. Cada ocorrência reúne formulário, coordenada, fotos, relatos escritos e áudios. Os pontos da visita aparecem no mapa, podem formar um envelope convexo e são exportados como KML 2.2 para conferência no QGIS.

Este é um MVP de hackathon. Os dados ficam no aparelho em SQLite e arquivos privados. A API Python não possui banco e não sincroniza nem faz backup.

## O que está implementado

- Visitas e múltiplas ocorrências relacionadas por UUID, com persistência SQLite local.
- Rascunhos offline, reabertura explícita e regras de finalização com revisão humana.
- Captura explícita do GPS atual, precisão/horário, aviso acima de 30 m e tratamento de permissão.
- Fotos copiadas para armazenamento privado, recuperação de retorno perdido do Android e remoção individual confirmada.
- Vários clipes M4A/AAC de até 2 minutos, reprodução, transcrição individual e preservação do texto original.
- Formulário reduzido com sugestões revisáveis e proteção contra respostas atrasadas.
- Mapa com pontos clicáveis, distinção entre rascunho/finalizado/demonstração e aviso quando os tiles falham.
- Envelope convexo calculado em projeção UTM com GeoPandas/Shapely e KML UTF-8 com atributos por ocorrência.
- Modo demonstrativo opt-in, com dados e coordenadas sempre identificados como fictícios.

## Requisitos usados

- Flutter 3.44.8 / Dart 3.12.2.
- Android SDK disponível para o Flutter.
- Python 3.13.2 (as dependências também devem funcionar em versões modernas compatíveis com os pacotes listados).
- Para IA: uma chave do Gemini e um nome de modelo ao qual a conta realmente tenha acesso.

Não é necessário Docker, PostgreSQL, Firebase ou qualquer banco remoto.

## Executar o backend no Windows/PowerShell

Na raiz do projeto:

```powershell
py -3 -m venv venv
.\venv\Scripts\Activate.ps1
python -m pip install -r .\backend\requirements.txt
Copy-Item .\backend\.env.example .\backend\.env
Set-Location .\backend
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000
```

O endpoint de saúde estará em `http://127.0.0.1:8000/health`. Ele não chama o provedor nem gasta créditos.

Por padrão, `AI_PROVIDER=disabled`: saúde e mapas funcionam, enquanto transcrição/extração retornam `AI_NOT_CONFIGURED`. Para um teste autorizado, edite `backend/.env`:

```dotenv
AI_PROVIDER=gemini
GEMINI_API_KEY=sua-chave
GEMINI_MODEL=nome-do-modelo-disponivel-na-sua-conta
```

O modelo não possui valor padrão propositalmente. Confira os modelos disponíveis para a credencial antes do teste. A chave nunca deve ser colocada no Dart, APK ou Git. A implementação usa o SDK oficial `google-genai`, áudio inline e resposta estruturada validada com Pydantic.

O host `0.0.0.0` é apropriado somente para o teste na rede local controlada. A API não tem autenticação e não deve ser publicada aberta na internet.

## Executar o aplicativo

Em outro PowerShell, na raiz:

```powershell
flutter pub get
flutter run
```

Abra o ícone de configurações no aplicativo e informe:

- Aplicativo executado no Windows: `http://127.0.0.1:8000`.
- Emulador Android padrão: `http://10.0.2.2:8000`.
- Celular físico: `http://IP_DO_NOTEBOOK:8000`, usando o IPv4 mostrado pelo `ipconfig`.

A fonte de tiles também é configurável. O padrão usa o servidor público do OpenStreetMap com atribuição e identificador do aplicativo; não use essa fonte para download massivo/offline. Ao trocar a fonte, confira e cumpra os termos e a atribuição exigida pelo provedor escolhido.

No aparelho físico, notebook e celular devem estar na mesma rede. Redes com isolamento entre clientes podem bloquear a conexão. Se o Windows Firewall bloquear a porta, crie uma regra de entrada restrita à rede privada/porta 8000; não desative o firewall inteiro.

HTTP sem TLS é permitido somente no manifesto de debug. O release não reduz essa proteção.

## Fluxo de demonstração

1. Crie uma visita e abra `Nova ocorrência` em cada local observado.
2. Capture o GPS, adicione uma foto e escreva ou grave o relato. O salvamento acontece no aparelho antes de qualquer rede.
3. Feche e reabra o aplicativo para demonstrar a persistência.
4. Revise e preencha manualmente mesmo offline. Com o backend/IA acessíveis, transcreva e solicite sugestões.
5. Confirme a revisão e finalize cada ocorrência; depois conclua a visita.
6. Abra `Mapa / KML`, toque nos marcadores, gere o contorno e compartilhe o KML.

Para preparar rapidamente o mapa sem apresentar dados como reais, ative o modo de demonstração em Configurações e toque em `Criar visita fictícia`. As quatro ocorrências ficam marcadas como `DADO FICTÍCIO` e permanecem em rascunho, pois não têm fotos reais.

## Conferência no QGIS

Abra o arquivo `.kml` compartilhado e confira manualmente:

1. A pasta/camada `Ocorrências` contém a mesma quantidade de pontos mostrada no app.
2. As coordenadas estão na posição esperada e usam longitude/latitude no arquivo.
3. Ocorrências coincidentes continuam como registros distintos.
4. `ExtendedData` contém ID, situação, data, empreendimento, descrições, referência, origem/precisão e indicação de demonstração.
5. `Contorno dos pontos` existe somente com três ou mais posições distintas não colineares.

Fotos e áudios não acompanham o KML; ficam no armazenamento privado do app. Compartilhar KML não é backup dos demais dados.

## Testes e build

```powershell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test

Set-Location backend
..\venv\Scripts\python.exe -m pytest
Set-Location ..

flutter build apk --debug
```

O APK gerado fica em `build\app\outputs\flutter-apk\app-debug.apk`.

Os testes Python não chamam serviços pagos. Eles cobrem os contratos de erro, IA desabilitada, evidências de sugestão, coordenadas inválidas, IDs/posições coincidentes, casos com 1/2/3 pontos, colinearidade, antimeridiano, XML/KML e uma fixture de 500 pontos. Os testes Flutter cobrem serialização/hash e persistência SQLite após reabertura.

## Organização

```text
lib/
  controllers/     estado simples das listas
  data/            SQLite, repositório e arquivos privados
  models/          entidades locais
  screens/         visitas, coleta, revisão, mapa e configuração
  services/        GPS, mídia e cliente HTTP
  widgets/         componentes visuais pequenos
backend/
  app/             FastAPI, Gemini, schemas, geometria e KML
  tests/           contratos e processamento
```

## Limitações conhecidas do MVP

- Android é o único alvo validado/obrigatório; não há contas, perfis, painel web ou multiempresa.
- Não há sincronização, backup central, integração LagoForm, relatório técnico final, PDF ou cálculo de área degradada.
- O envelope convexo apenas envolve os pontos observados; pode conter locais não vistoriados e não é delimitação ambiental/técnica.
- Tiles do OpenStreetMap e IA dependem de conectividade. GPS, SQLite, anexos e preenchimento manual não dependem do mapa-base.
- Não há mapas-base offline, geocodificação, rotas, satélite, drones ou análise de fotos.
- A gravação interrompida pelo sistema só é mantida se o plugin conseguir encerrar e produzir o arquivo; o app informa a interrupção.
- A integração Gemini exige credencial, modelo e autorização para um teste real. Não existe resposta simulada em execução normal.
- A abertura no QGIS e o comportamento em hardware/permissões devem ser conferidos manualmente no aparelho e ambiente da apresentação.
