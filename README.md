# tidyprf-dados

Pipeline de dados do pacote R [tidyprf](https://github.com/bonijoao/tidyprf).

Este repositório baixa os dados abertos da [Polícia Rodoviária Federal (PRF)](https://www.gov.br/prf/pt-br/acesso-a-informacao/dados-abertos/dados-abertos-da-prf), consolida os CSVs em arquivos Parquet anuais e os publica como assets de uma [GitHub Release](https://github.com/bonijoao/tidyprf-dados/releases). O pacote `tidyprf` consome esses arquivos sob demanda, guiado pelo [`catalogo.json`](catalogo.json) na raiz deste repositório.

## Estrutura

```
tidyprf-dados/
├── catalogo.json        # índice canônico dos Parquet publicados (lido pelo pacote)
├── fontes.json          # último snapshot dos links da página da PRF (dataset, ano, ID do Drive)
├── .github/workflows/
│   └── atualizar-dados.yml  # atualização automática semanal
├── scripts/
│   ├── 01_baixar.R      # carga inicial: scraping + download dos ZIPs (histórico)
│   ├── 02_descompactar.R# carga inicial: extrai ZIP/RAR em dados/processados/
│   ├── 03_reparar.R     # carga inicial: detecta ZIPs corrompidos e re-baixa
│   ├── 04_consolidar.R  # CSV → Parquet anual + catalogo.json (funções usadas pelo 05)
│   ├── fontes.R         # lê os links da página da PRF e baixa os ZIPs
│   └── 05_atualizar.R   # atualização incremental (usada pelo GitHub Actions)
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

## Atualização dos dados

### Automática (GitHub Actions)

O workflow [`atualizar-dados.yml`](.github/workflows/atualizar-dados.yml) roda **toda segunda-feira às 03h (Brasília)** e executa `scripts/05_atualizar.R`:

1. Lê a página da PRF e identifica os links de acidentes (por pessoa, todas as causas), ocorrências (`datatran`) e multas do ano atual e do anterior. Se a página não puder ser lida, usa os links salvos em `fontes.json`.
2. Baixa cada ZIP e compara o SHA-256 com o `origem_sha256` do catálogo. Se não mudou, pula.
3. Consolida os que mudaram e valida: colunas iguais ao schema, número de linhas não pode cair mais de 1% e ≥ 95% das linhas com data no ano do arquivo.
4. Se tudo passar, sobe os Parquet na release `dados-v1` (`--clobber`) e commita `catalogo.json`/`fontes.json`. Só as entradas reprocessadas recebem nova `atualizado_em`. O pacote usa essa data para renovar o cache dos usuários.

Se algo falhar, **nada é publicado** e o workflow abre (ou comenta) uma issue com o label `atualizacao-falhou`, com link para o log.

**Rodar manualmente:** aba *Actions* → *Atualizar dados PRF* → *Run workflow*. Opções: `anos` (ex.: `2024,2025`), `forcar` (reprocessa mesmo sem mudança na origem) e `dry_run` (processa e valida sem publicar). Pela linha de comando:

```sh
gh workflow run atualizar-dados.yml -f anos=2026 -f dry_run=true
```

### Local

O mesmo script roda localmente (a partir da raiz do repositório):

```sh
TIDYPRF_ANOS=2026 Rscript scripts/05_atualizar.R
```

Ele gera os Parquet em `dados/consolidados/`, atualiza `catalogo.json` e lista em `alterados.txt` o que publicar:

```sh
xargs -a alterados.txt gh release upload dados-v1 --clobber
git add catalogo.json fontes.json && git commit -m "Atualiza dados PRF" && git push
```

Para reconstruir tudo do zero (carga inicial), use `01`–`04` e `Rscript scripts/04_consolidar.R`.

Dependências: `arrow`, `readr`, `dplyr`, `purrr`, `stringr`, `lubridate`, `jsonlite`, `fs`, `cli`, `glue`, `rvest`, `httr2`, `digest`.

## Licença

Os dados são públicos, publicados pela PRF sob a política de dados abertos do governo federal. O código deste repositório está sob licença MIT.
