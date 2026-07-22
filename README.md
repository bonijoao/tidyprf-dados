# tidyprf-dados

Pipeline de dados do pacote R [tidyprf](https://github.com/bonijoao/tidyprf).

Este repositório baixa os dados abertos da [Polícia Rodoviária Federal (PRF)](https://www.gov.br/prf/pt-br/acesso-a-informacao/dados-abertos/dados-abertos-da-prf), consolida os CSVs em arquivos Parquet anuais e os publica como assets de uma [GitHub Release](https://github.com/bonijoao/tidyprf-dados/releases). O pacote `tidyprf` consome esses arquivos sob demanda, guiado pelo [`catalogo.json`](catalogo.json) na raiz deste repositório.

## Estrutura

```
tidyprf-dados/
├── catalogo.json        # índice canônico dos Parquet publicados (lido pelo pacote)
├── scripts/
│   ├── 01_baixar.R      # scraping da página da PRF + download dos ZIPs (Google Drive)
│   ├── 02_descompactar.R# extrai ZIP/RAR em dados/processados/
│   ├── 03_reparar.R     # detecta ZIPs corrompidos e re-baixa
│   └── 04_consolidar.R  # CSV → Parquet anual + regenera catalogo.json
├── dicionario/          # dicionários de variáveis oficiais da PRF (PDF)
├── docs/                # documentação técnica da consolidação
└── dados/               # (não versionado) brutos/, processados/, consolidados/
```

## Datasets

| Dataset | Granularidade | Cobertura |
|---|---|---|
| `acidentes` | uma linha por pessoa envolvida | 2007–2026 |
| `datatran` | uma linha por ocorrência (acidente) | 2007–2026 |
| `infracoes` | uma linha por infração | 2019–2020, 2022–2026 |

Detalhes de schema, separadores, encodings e datas por ano em [`docs/consolidacao-design.md`](docs/consolidacao-design.md).

## Como atualizar os dados

1. **Baixar** os arquivos novos: `Rscript scripts/01_baixar.R` (e `03_reparar.R` se houver ZIPs corrompidos).
2. **Descompactar**: `Rscript scripts/02_descompactar.R`.
3. **Consolidar** apenas os anos afetados (em uma sessão R):

   ```r
   source("scripts/04_consolidar.R")
   consolidar_acidentes(2026)
   consolidar_datatran(2026)
   consolidar_infracoes(2026)
   atualizar_catalogo()
   ```

4. **Publicar** os Parquet atualizados na release e commitar o novo catálogo:

   ```sh
   gh release upload dados-v1 dados/consolidados/acidentes/acidentes_2026.parquet --clobber
   git add catalogo.json
   git commit -m "Atualiza dados de 2026"
   git push
   ```

Dependências dos scripts: `arrow`, `readr`, `dplyr`, `purrr`, `stringr`, `lubridate`, `jsonlite`, `fs`, `cli`, `glue` (e `rvest`, `googledrive` para o download).

## Licença

Os dados são públicos, publicados pela PRF sob a política de dados abertos do governo federal. O código deste repositório está sob licença MIT.
