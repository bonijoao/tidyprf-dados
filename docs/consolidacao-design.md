# Design: Consolidação dos Dados PRF em Parquet

**Data:** 2026-05-03  
**Projeto:** tidyprf  
**Escopo:** Transformar os CSVs brutos da PRF em arquivos Parquet anuais prontos para hospedagem e consumo pelo pacote.

---

## 1. Objetivo

Converter ~220 arquivos CSV da PRF (dados brutos em `dados/processados/`) em um conjunto de arquivos Parquet por ano por dataset, armazenados em `dados/consolidados/`. O resultado deve ser:

- Consumível diretamente pelo pacote `tidyprf` via download sob demanda (~6 MB por ano)
- Atualizável de forma incremental (um arquivo por ano afetado)
- Schema unificado e consistente entre anos (2007–2026)
- Compatível com `{arrow}` e `{duckdb}` no R

---

## 2. Estrutura de saída

```
dados/consolidados/
├── acidentes/
│   ├── acidentes_2007.parquet
│   ├── acidentes_2008.parquet
│   ⋮
│   └── acidentes_2026.parquet
├── datatran/
│   ├── datatran_2007.parquet
│   ⋮
│   └── datatran_2026.parquet
├── infracoes/
│   ├── infracoes_2019.parquet
│   ⋮
│   └── infracoes_2026.parquet
└── catalogo.json
```

Cada arquivo Parquet contém **todos os dados de um único ano** para um dataset. O `catalogo.json` é o índice que o pacote consulta antes de qualquer download.

---

## 3. catalogo.json

Estrutura do arquivo de índice:

```json
{
  "atualizado_em": "2026-05-03",
  "datasets": {
    "acidentes": {
      "anos": [2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015,
               2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024,
               2025, 2026],
      "arquivos": {
        "acidentes_2023.parquet": {
          "tamanho_mb": 6.2,
          "linhas": 194630,
          "atualizado_em": "2026-05-03"
        }
      }
    },
    "datatran": {
      "anos": [2007, 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015,
               2016, 2017, 2018, 2019, 2020, 2021, 2022, 2023, 2024,
               2025, 2026]
    },
    "infracoes": {
      "anos": [2019, 2020, 2022, 2023, 2024, 2025, 2026]
    }
  }
}
```

O pacote lê este arquivo na primeira chamada da sessão (cache em memória) para validar se o ano pedido existe antes de tentar baixar.

---

## 4. Particularidades de leitura por dataset

### 4.0 Separadores e datas (levantamento real dos arquivos)

**Acidentes — separador:**

| Anos | Separador |
|------|-----------|
| 2007–2015 | vírgula (`,`) |
| 2016–2026 | ponto e vírgula (`;`) |

**Acidentes — formato de data:**

| Anos | Formato |
|------|---------|
| 2007–2015 | `DD/MM/YYYY` |
| 2016 | `DD/MM/YY` (ano com 2 dígitos) |
| 2017–2026 | `YYYY-MM-DD` |

**Datatran — separador:** ponto e vírgula em todos os anos.

**Datatran — formato de data (o mais inconsistente):**

| Anos | Formato |
|------|---------|
| 2007–2011 | `DD/MM/YYYY` |
| 2012–2013 | `YYYY-MM-DD` |
| 2014 | `DD/MM/YYYY` (voltou) |
| 2015 | `YYYY-MM-DD` |
| 2016 | `DD/MM/YY` (ano com 2 dígitos) |
| 2017–2026 | `YYYY-MM-DD` |

**Infrações:** todas em `YYYY-MM-DD`, separador ponto e vírgula. Encoding: 2019 = UTF-8 com BOM; 2020 e 2022+ = Latin-1.

**Estratégia de parsing unificada** — função aplicada a todos os datasets:

```r
parse_data_prf <- function(x) {
  lubridate::parse_date_time(x,
    orders = c("Ymd", "dmY", "dmy"),
    quiet  = TRUE
  ) |> as.Date()
}
```

O `lubridate` testa os três formatos em ordem. `DD/MM/YY` cai em `dmy` e o ano de 2 dígitos é expandido corretamente (16 → 2016). Todas as datas saem como `Date` em `YYYY-MM-DD`.

---

## 5. Transformações por dataset

### 5.1 Acidentes (por pessoa)

**Fonte:**
- 2007–2015: `acidentes{ano}.csv` com separador vírgula
- 2016: `acidentes2016_atual.csv` com separador ponto e vírgula
- 2017–2026: `acidentes{ano}_todas_causas_tipos.csv` (versão mais completa, com `causa_principal` e `ordem_tipo_acidente`)

**Schema de saída unificado (39 colunas):**

| Coluna | Tipo R | Notas |
|--------|--------|-------|
| `id` | character | |
| `pesid` | character | |
| `data_inversa` | Date | `parse_data_prf()` |
| `dia_semana` | character | minúsculas |
| `horario` | character | `"HH:MM:SS"` |
| `uf` | character | maiúsculas, 2 letras |
| `br` | integer | |
| `km` | double | vírgula → ponto |
| `municipio` | character | |
| `causa_principal` | character | `NA` pré-2017 (coluna inexistente) |
| `causa_acidente` | character | |
| `ordem_tipo_acidente` | integer | `NA` pré-2017 |
| `tipo_acidente` | character | |
| `classificacao_acidente` | character | |
| `fase_dia` | character | |
| `sentido_via` | character | |
| `condicao_metereologica` | character | |
| `tipo_pista` | character | |
| `tracado_via` | character | |
| `uso_solo` | character | 2017+: normalizar `"Sim"`→`"Urbano"`, `"Não"`→`"Rural"` |
| `id_veiculo` | character | |
| `tipo_veiculo` | character | |
| `marca` | character | |
| `ano_fabricacao_veiculo` | integer | |
| `tipo_envolvido` | character | |
| `estado_fisico` | character | |
| `idade` | integer | |
| `sexo` | character | normalizar: `"M"` → `"Masculino"`, `"F"` → `"Feminino"` |
| `nacionalidade` | character | `NA` pós-2017 (coluna existia só pré-2017) |
| `naturalidade` | character | `NA` pós-2017 |
| `ilesos` | integer | `NA` pré-2017 — valor **binário** (0/1) por pessoa, não contagem |
| `feridos_leves` | integer | `NA` pré-2017 — valor **binário** (0/1) por pessoa |
| `feridos_graves` | integer | `NA` pré-2017 — valor **binário** (0/1) por pessoa |
| `mortos` | integer | `NA` pré-2017 — valor **binário** (0/1) por pessoa |
| `latitude` | double | `NA` pré-2017 |
| `longitude` | double | `NA` pré-2017 |
| `regional` | character | `NA` pré-2017 |
| `delegacia` | character | `NA` pré-2017 |
| `uop` | character | `NA` pré-2017 |
| `ano` | integer | coluna derivada do `year(data_inversa)` |

**Nota:** o mapeamento exato de nomes pré-2017 será confirmado durante implementação consultando `dicionario/acidentes agrupados por pessoa (até 2016).pdf`. Os nomes das colunas nos arquivos reais de 2007–2016 já são `snake_case` idênticos aos de 2017+ (confirmado nos headers lidos) — a diferença é de colunas presentes/ausentes, não de nomes.

---

### 5.2 Datatran (por ocorrência)

**Fonte:** `datatran{ano}.csv` (2007–2026), um arquivo por ano, separador ponto e vírgula em todos.

**Particularidades (verificado nos arquivos reais):**
- 2007–2016: não tem `latitude`, `longitude`, `regional`, `delegacia`, `uop` — preencher com `NA`
- 2007–2015: tem coluna `ano` já embutida (remover — será derivada uniformemente)
- 2016+: não tem coluna `ano` na fonte (adicionar como derivada)

**Schema de saída unificado:**

| Coluna | Tipo R | Notas |
|--------|--------|-------|
| `id` | character | |
| `data_inversa` | Date | `parse_data_prf()` |
| `dia_semana` | character | minúsculas |
| `horario` | character | |
| `uf` | character | |
| `br` | integer | |
| `km` | double | |
| `municipio` | character | |
| `causa_acidente` | character | |
| `tipo_acidente` | character | |
| `classificacao_acidente` | character | |
| `fase_dia` | character | |
| `sentido_via` | character | |
| `condicao_metereologica` | character | |
| `tipo_pista` | character | |
| `tracado_via` | character | |
| `uso_solo` | character | |
| `pessoas` | integer | |
| `mortos` | integer | |
| `feridos_leves` | integer | |
| `feridos_graves` | integer | |
| `ilesos` | integer | |
| `ignorados` | integer | |
| `feridos` | integer | |
| `veiculos` | integer | |
| `latitude` | double | `NA` para 2007–2016 (confirmado nos arquivos reais) |
| `longitude` | double | `NA` para 2007–2016 |
| `regional` | character | `NA` para 2007–2016 |
| `delegacia` | character | `NA` para 2007–2016 |
| `uop` | character | `NA` para 2007–2016 |
| `ano` | integer | derivada de `year(data_inversa)` |

---

### 5.3 Infrações

**Fonte:**
- 2019: `infracoes_2019_{MM}.csv` — separador `;`, UTF-8 com BOM, **22 colunas** (faltam `tipo_veiculo`, `nom_modelo_veiculo`, `qtd_infracoes`)
- 2020: `infracoes_2020_{MM}.csv` — separador `;`, Latin-1, **23 colunas** (faltam `tipo_veiculo`, `nom_modelo_veiculo`; tem `qtd_infracoes`)
- 2022–2026: `ajustados_{ano}/infraçoes{ano}_{MM}.csv` — separador `;`, Latin-1, **25 colunas** (schema completo)
- 2021: ausente

Todos os meses do ano são concatenados com `purrr::map_dfr()` antes de escrever o Parquet anual.

**Mapeamento de nomes** (título com espaços → snake_case):

| Nome original | Nome padronizado |
|--------------|-----------------|
| `Número do Auto` | `numero_auto` |
| `Data da Infração (DD/MM/AAAA)` | `dat_infracao` |
| `Indicador de Abordagem` | `tip_abordagem` |
| `Assinatura do Auto` | `ind_assinou_auto` |
| `Indicador Veiculo Estrangeiro` | `ind_veiculo_estrangeiro` |
| `Sentido Trafego` | `ind_sentido_trafego` |
| `UF Placa` | `uf_placa` |
| `UF Infração` | `uf_infracao` |
| `BR Infração` | `num_br_infracao` |
| `Km Infração` | `num_km_infracao` |
| `Município` | `nom_municipio` |
| `Código da Infração` | `cod_infracao` |
| `Descrição Abreviada Infração` | `descricao_abreviada` |
| `Enquadramento da Infração` | `enquadramento` |
| `Início Vigência da Infração` | `data_inicio_vigencia` | `parse_data_prf()` — formato `dd/mm/aaaa` |
| `Fim Vigência Infração` | `data_fim_vigencia` | `parse_data_prf()` |
| `Medição Infração` | `med_realizada` |
| `Medição Considerada` | `med_considerada` |
| `Excesso Verificado` | `exc_verificado` |
| `Descrição Especie Veículo` | `especie` |
| `Descrição Marca Veículo` | `nome_veiculo_marca` |
| `Descrição Tipo Veículo` | `tipo_veiculo` — `NA` em 2019–2020 (ausente nos CSVs) |
| `Descrição Modelo Veiculo` | `nom_modelo_veiculo` — `NA` em 2019–2020 |
| `Hora Infração` | `hora` |
| `Qtd Infrações` | `qtd_infracoes` — `NA` em 2019 (ausente); presente em 2020 e 2022+ |
| *(derivada)* | `ano` — `year(dat_infracao)` |

---

### 4.2 Datatran (por ocorrência)

**Fonte:** `datatran{ano}.csv` (2007–2026)

Schema análogo ao de acidentes, removendo campos de pessoa/veículo individuais e adicionando:

| Coluna adicional | Tipo R | Descrição |
|-----------------|--------|-----------|
| `pessoas` | integer | Total de pessoas |
| `veiculos` | integer | Total de veículos |
| `feridos` | integer | Total de feridos |
| `ignorados` | integer | Estado físico ignorado |
| `ano` | integer | Coluna derivada |

---

### 4.3 Infrações

**Fonte:**
- 2019–2020: `infracoes_{ano}_{MM}.csv` (12 arquivos mensais por ano)
- 2022–2026: `ajustados_{ano}/infra*.csv` (12 arquivos mensais por ano)
- Observação: 2021 ausente nos dados disponíveis

Todos os meses do ano são concatenados antes de escrever o Parquet anual.

Schema de saída com `ano` como coluna derivada adicional.

---

## 6. Padronização de NA

Aplicada em **todos** os datasets antes de escrever o Parquet:

```r
valores_na <- c("", "NA", "Ignorado", "Não informado",
                "Não Informado", "NÃO INFORMADO", "-", "N/A")
```

Qualquer célula com esses valores é convertida para `NA` real do R.

**Caso especial numérico:** `idade == -1` → `NA` (sentinela de dado ausente nos dicionários pré-2017 e 2017+).

---

## 7. Compressão Parquet

- **Codec:** Snappy (padrão do `{arrow}`) — bom equilíbrio entre tamanho e velocidade de leitura
- **Row group size:** padrão do arrow (~1M linhas) — adequado para os volumes PRF

---

## 8. Script de consolidação

O processo de consolidação está implementado em `scripts/04_consolidar.R` (script standalone deste repositório, não função de pacote). Estrutura:

```
04_consolidar.R
├── consolidar_acidentes(ano)     # processa um ano de acidentes
├── consolidar_datatran(ano)      # processa um ano de datatran
├── consolidar_infracoes(ano)     # processa um ano de infrações
├── atualizar_catalogo()          # regenera catalogo.json
└── consolidar_tudo()             # roda os três para todos os anos
```

Cada função `consolidar_*(ano)`:
1. Lê o(s) CSV(s) fonte detectando separador por ano (vírgula para acidentes 2007–2015, ponto e vírgula demais)
2. Concatena meses se necessário (infrações)
3. Renomeia colunas para o schema unificado
4. Converte tipos (Date, integer, double)
5. Padroniza NAs
6. Escreve `dados/consolidados/{dataset}/{dataset}_{ano}.parquet` via `arrow::write_parquet()`
7. Retorna invisível um sumário (linhas escritas, tamanho em MB)

---

## 9. Processo de atualização incremental

Quando a PRF liberar dados novos para um ano existente ou um ano novo:

```r
# Atualizar só o ano afetado
consolidar_acidentes(2026)
consolidar_infracoes(2026)
atualizar_catalogo()
```

Apenas os Parquets do(s) ano(s) afetado(s) são reescritos. O `catalogo.json` é sempre regenerado por completo ao final.

---

## 10. Dependências do script de consolidação

```r
# Necessário para rodar consolidar.R
install.packages(c("arrow", "readr", "dplyr", "purrr",
                   "stringr", "lubridate", "jsonlite", "fs"))
```

Estas são dependências do **script de consolidação** (uso interno), não do pacote `tidyprf` em si.

---

## 11. Critérios de sucesso

- [ ] Todos os anos disponíveis geram Parquets sem erro
- [ ] Schema idêntico entre todos os anos de cada dataset (verificável com `arrow::schema()`)
- [ ] Nenhum valor de NA implícito (strings "Ignorado" etc.) nos Parquets
- [ ] `catalogo.json` reflete corretamente todos os arquivos gerados
- [ ] Tamanho médio por arquivo < 15 MB
- [ ] Leitura de um Parquet no R retorna tibble com tipos corretos sem nenhuma conversão manual
