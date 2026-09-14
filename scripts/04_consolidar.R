# scripts/04_consolidar.R
# Consolida CSVs brutos da PRF em arquivos Parquet anuais por dataset
# e regenera o catalogo.json consumido pelo pacote tidyprf.
# Executar a partir do root do repositorio: Rscript scripts/04_consolidar.R

suppressPackageStartupMessages({
  library(arrow)
  library(readr)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(lubridate)
  library(jsonlite)
  library(fs)
  library(cli)
  library(glue)
})

REPO       <- "bonijoao/tidyprf-dados"
RELEASE_TAG <- "dados-v1"
BASE_URL    <- paste0("https://github.com/", REPO,
                      "/releases/download/", RELEASE_TAG, "/")

VALORES_NA        <- c("", "NA", "Ignorado", "Não informado",
                       "Não Informado", "NÃO INFORMADO", "-", "N/A")
BASE_PROCESSADOS  <- "dados/processados"
BASE_CONSOLIDADOS <- "dados/consolidados"

# ---- schemas ---------------------------------------------------------------

SCHEMA_ACIDENTES <- c(
  "id", "pesid", "data_inversa", "dia_semana", "horario",
  "uf", "br", "km", "municipio",
  "causa_principal", "causa_acidente", "ordem_tipo_acidente", "tipo_acidente",
  "classificacao_acidente", "fase_dia", "sentido_via",
  "condicao_metereologica", "tipo_pista", "tracado_via", "uso_solo",
  "id_veiculo", "tipo_veiculo", "marca", "ano_fabricacao_veiculo",
  "tipo_envolvido", "estado_fisico", "idade", "sexo",
  "nacionalidade", "naturalidade",
  "ilesos", "feridos_leves", "feridos_graves", "mortos",
  "latitude", "longitude",
  "regional", "delegacia", "uop",
  "ano"
)

SCHEMA_DATATRAN <- c(
  "id", "data_inversa", "dia_semana", "horario",
  "uf", "br", "km", "municipio",
  "causa_acidente", "tipo_acidente", "classificacao_acidente",
  "fase_dia", "sentido_via", "condicao_metereologica",
  "tipo_pista", "tracado_via", "uso_solo",
  "pessoas", "mortos", "feridos_leves", "feridos_graves",
  "ilesos", "ignorados", "feridos", "veiculos",
  "latitude", "longitude",
  "regional", "delegacia", "uop",
  "ano"
)

SCHEMA_INFRACOES <- c(
  "numero_auto", "dat_infracao", "tip_abordagem", "ind_assinou_auto",
  "ind_veiculo_estrangeiro", "ind_sentido_trafego",
  "uf_placa", "uf_infracao", "num_br_infracao", "num_km_infracao", "nom_municipio",
  "cod_infracao", "descricao_abreviada", "enquadramento",
  "data_inicio_vigencia", "data_fim_vigencia",
  "med_realizada", "med_considerada", "exc_verificado",
  "especie", "nome_veiculo_marca",
  "tipo_veiculo", "nom_modelo_veiculo",
  "hora", "qtd_infracoes",
  "ano"
)

# Mapeamento nomes originais infrações (após tolower) → snake_case
MAPA_INFRACOES <- c(
  "numero_auto"             = "número do auto",
  "dat_infracao"            = "data da infração (dd/mm/aaaa)",
  "tip_abordagem"           = "indicador de abordagem",
  "ind_assinou_auto"        = "assinatura do auto",
  "ind_veiculo_estrangeiro" = "indicador veiculo estrangeiro",
  "ind_sentido_trafego"     = "sentido trafego",
  "uf_placa"                = "uf placa",
  "uf_infracao"             = "uf infração",
  "num_br_infracao"         = "br infração",
  "num_km_infracao"         = "km infração",
  "nom_municipio"           = "município",
  "cod_infracao"            = "código da infração",
  "descricao_abreviada"     = "descrição abreviada infração",
  "enquadramento"           = "enquadramento da infração",
  "data_inicio_vigencia"    = "início vigência da infração",
  "data_fim_vigencia"       = "fim vigência infração",
  "med_realizada"           = "medição infração",
  "med_considerada"         = "medição considerada",
  "exc_verificado"          = "excesso verificado",
  "especie"                 = "descrição especie veículo",
  "nome_veiculo_marca"      = "descrição marca veículo",
  "tipo_veiculo"            = "descrição tipo veículo",
  "nom_modelo_veiculo"      = "descrição modelo veiculo",
  "hora"                    = "hora infração",
  "qtd_infracoes"           = "qtd infrações"
)

# ---- funções ---------------------------------------------------------------
parse_data_prf <- function(x) {
  lubridate::parse_date_time(
    x,
    orders = c("Ymd", "dmY", "dmy"),
    quiet  = TRUE
  ) |> as.Date()
}

consolidar_acidentes <- function(ano) {
  if (ano <= 2015) {
    arquivo    <- path(BASE_PROCESSADOS, glue("acidentes{ano}.csv"))
    sep        <- ","
    locale_csv <- locale(encoding = "latin1")
  } else if (ano == 2016) {
    arquivo    <- path(BASE_PROCESSADOS, "acidentes2016_atual.csv")
    sep        <- ";"
    locale_csv <- locale(encoding = "latin1", decimal_mark = ",")
  } else {
    arquivo    <- path(BASE_PROCESSADOS, glue("acidentes{ano}_todas_causas_tipos.csv"))
    sep        <- ";"
    locale_csv <- locale(encoding = "latin1", decimal_mark = ",")
  }

  df <- read_delim(arquivo, delim = sep, locale = locale_csv,
                   na = VALORES_NA, name_repair = "minimal",
                   show_col_types = FALSE) |>
    rename_with(tolower)

  df <- df |>
    mutate(data_inversa = parse_data_prf(data_inversa))

  if (ano >= 2017) {
    df <- df |>
      mutate(uso_solo = case_match(uso_solo,
        "Sim" ~ "Urbano", "Não" ~ "Rural", .default = uso_solo))
  }

  df <- df |>
    mutate(sexo = case_match(sexo,
      "M" ~ "Masculino", "F" ~ "Feminino", .default = sexo))

  if ("idade" %in% names(df)) {
    df <- df |>
      mutate(idade = if_else(as.integer(idade) == -1L, NA_integer_, as.integer(idade)))
  }

  if (ano < 2017) {
    df <- df |>
      mutate(
        causa_principal      = NA_character_,
        ordem_tipo_acidente  = NA_integer_,
        ilesos               = NA_integer_,
        feridos_leves        = NA_integer_,
        feridos_graves       = NA_integer_,
        mortos               = NA_integer_,
        latitude             = NA_real_,
        longitude            = NA_real_,
        regional             = NA_character_,
        delegacia            = NA_character_,
        uop                  = NA_character_
      )
  } else {
    df <- df |>
      mutate(nacionalidade = NA_character_, naturalidade = NA_character_)
  }

  df <- df |>
    mutate(ano = as.integer(year(data_inversa))) |>
    select(all_of(SCHEMA_ACIDENTES)) |>
    mutate(
      br                     = as.integer(br),
      km                     = as.double(km),
      ordem_tipo_acidente    = as.integer(ordem_tipo_acidente),
      ano_fabricacao_veiculo = as.integer(ano_fabricacao_veiculo),
      ilesos                 = as.integer(ilesos),
      feridos_leves          = as.integer(feridos_leves),
      feridos_graves         = as.integer(feridos_graves),
      mortos                 = as.integer(mortos),
      latitude               = as.double(latitude),
      longitude              = as.double(longitude),
      uf                     = toupper(uf),
      dia_semana             = tolower(dia_semana)
    )

  saida <- path(BASE_CONSOLIDADOS, "acidentes", glue("acidentes_{ano}.parquet"))
  dir_create(path_dir(saida), recurse = TRUE)
  write_parquet(df, saida)

  res <- list(linhas = nrow(df), tamanho_mb = round(file.size(saida) / 1e6, 2))
  cli_inform("acidentes_{ano}: {res$linhas} linhas, {res$tamanho_mb} MB")
  invisible(res)
}
consolidar_datatran <- function(ano) {
  arquivo <- path(BASE_PROCESSADOS, glue("datatran{ano}.csv"))

  df <- read_delim(arquivo, delim = ";",
                   locale = locale(encoding = "latin1", decimal_mark = ","),
                   na = VALORES_NA, name_repair = "minimal",
                   show_col_types = FALSE) |>
    rename_with(tolower)

  # Remove pre-existing 'ano' column in 2007–2015 (will be re-derived below)
  if (ano <= 2015 && "ano" %in% names(df)) {
    df <- df |> select(-ano)
  }

  df <- df |>
    mutate(data_inversa = parse_data_prf(data_inversa))

  if (ano >= 2017) {
    df <- df |>
      mutate(uso_solo = case_match(uso_solo,
        "Sim" ~ "Urbano", "Não" ~ "Rural", .default = uso_solo))
  }

  # 2007–2016 lack lat/lon and regional info
  if (ano <= 2016) {
    df <- df |>
      mutate(
        latitude  = NA_real_,  longitude = NA_real_,
        regional  = NA_character_, delegacia = NA_character_, uop = NA_character_
      )
  }

  df <- df |>
    mutate(ano = as.integer(year(data_inversa))) |>
    select(all_of(SCHEMA_DATATRAN)) |>
    mutate(
      br             = as.integer(br),
      km             = as.double(km),
      pessoas        = as.integer(pessoas),
      mortos         = as.integer(mortos),
      feridos_leves  = as.integer(feridos_leves),
      feridos_graves = as.integer(feridos_graves),
      ilesos         = as.integer(ilesos),
      ignorados      = as.integer(ignorados),
      feridos        = as.integer(feridos),
      veiculos       = as.integer(veiculos),
      latitude       = as.double(latitude),
      longitude      = as.double(longitude),
      uf             = toupper(uf),
      dia_semana     = tolower(dia_semana)
    )

  saida <- path(BASE_CONSOLIDADOS, "datatran", glue("datatran_{ano}.parquet"))
  dir_create(path_dir(saida), recurse = TRUE)
  write_parquet(df, saida)

  res <- list(linhas = nrow(df), tamanho_mb = round(file.size(saida) / 1e6, 2))
  cli_inform("datatran_{ano}: {res$linhas} linhas, {res$tamanho_mb} MB")
  invisible(res)
}
consolidar_infracoes <- function(ano) {
  if (ano == 2021) {
    cli_warn("Infrações 2021 ausentes — pulando.")
    return(invisible(NULL))
  }

  if (ano %in% c(2019, 2020)) {
    arquivos <- dir_ls(BASE_PROCESSADOS,
                       regexp = glue("infracoes_{ano}_\\d+\\.csv$"))
    enc_csv <- if (ano == 2019) "UTF-8" else "latin1"
  } else {
    pasta    <- path(BASE_PROCESSADOS, glue("ajustados_{ano}"))
    arquivos <- dir_ls(pasta, regexp = "\\.csv$", ignore.case = TRUE)
    enc_csv <- "latin1"
  }

  if (length(arquivos) == 0) {
    cli_warn("Nenhum arquivo para infrações {ano}.")
    return(invisible(NULL))
  }

  # Um CSV (mes) por vez, cada um vira um row group do mesmo Parquet:
  # memoria limitada a ~1 mes em vez do ano inteiro (~2,5 GB de CSV)
  ler_mes <- function(arq) {
    df <- read_delim(arq, delim = ";",
                     locale = locale(encoding = enc_csv, decimal_mark = ","),
                     na = VALORES_NA, name_repair = "minimal",
                     col_types = cols(.default = "c"),
                     show_col_types = FALSE) |>
      rename_with(tolower) |>
      rename(any_of(MAPA_INFRACOES))

    if (ano == 2019) {
      df <- df |>
        mutate(tipo_veiculo       = NA_character_,
               nom_modelo_veiculo = NA_character_,
               qtd_infracoes      = NA_integer_)
    } else if (ano == 2020) {
      df <- df |>
        mutate(tipo_veiculo       = NA_character_,
               nom_modelo_veiculo = NA_character_)
    }

    df |>
      mutate(
        dat_infracao         = parse_data_prf(dat_infracao),
        data_inicio_vigencia = parse_data_prf(data_inicio_vigencia),
        data_fim_vigencia    = parse_data_prf(data_fim_vigencia),
        ano                  = as.integer(year(dat_infracao))
      ) |>
      select(all_of(SCHEMA_INFRACOES)) |>
      mutate(
        num_br_infracao = as.integer(num_br_infracao),
        num_km_infracao = as.double(num_km_infracao),
        med_realizada   = as.double(med_realizada),
        med_considerada = as.double(med_considerada),
        exc_verificado  = as.double(exc_verificado),
        qtd_infracoes   = as.integer(qtd_infracoes)
      )
  }

  saida <- path(BASE_CONSOLIDADOS, "infracoes", glue("infracoes_{ano}.parquet"))
  dir_create(path_dir(saida), recurse = TRUE)

  sink    <- FileOutputStream$create(saida)
  writer  <- NULL
  schema  <- NULL
  linhas  <- 0L

  for (arq in arquivos) {
    tabela <- Table$create(ler_mes(arq))
    if (is.null(writer)) {
      schema <- tabela$schema
      writer <- ParquetFileWriter$create(schema, sink,
                                         properties = ParquetWriterProperties$create(names(schema)))
    }
    writer$WriteTable(tabela$cast(schema), chunk_size = tabela$num_rows)
    linhas <- linhas + tabela$num_rows
    rm(tabela); invisible(gc())
  }
  writer$Close()
  sink$close()

  res <- list(linhas = linhas, tamanho_mb = round(file.size(saida) / 1e6, 2))
  cli_inform("infracoes_{ano}: {res$linhas} linhas, {res$tamanho_mb} MB")
  invisible(res)
}

# Atualiza o catalogo de forma incremental: so as entradas dos Parquets
# informados em `arquivos` (caminhos locais) sao reescritas; as demais mantem
# seus metadados, inclusive `atualizado_em` -- o pacote usa essa data para
# decidir se o cache do usuario esta desatualizado.
# `sha256` e um vetor nomeado (nome do Parquet -> hash do zip de origem).
# Sem argumentos, reescreve as entradas de todos os Parquets locais.
atualizar_catalogo <- function(arquivos = NULL, sha256 = character()) {
  datasets <- c("acidentes", "datatran", "infracoes")
  saida    <- "catalogo.json"
  hoje     <- as.character(Sys.Date())

  if (is.null(arquivos)) {
    arquivos <- dir_ls(BASE_CONSOLIDADOS, recurse = TRUE, glob = "*.parquet")
  }

  catalogo <- if (file_exists(saida)) {
    read_json(saida, simplifyVector = FALSE)
  } else {
    list(datasets = list())
  }

  for (caminho in arquivos) {
    arq     <- path_file(caminho)
    dataset <- str_remove(arq, "_\\d{4}\\.parquet$")
    if (!dataset %in% datasets) cli_abort("Parquet inesperado: {arq}")

    info <- list(
      url           = paste0(BASE_URL, arq),
      tamanho_mb    = round(file.size(caminho) / 1e6, 2),
      linhas        = nrow(open_dataset(caminho)),
      atualizado_em = hoje
    )
    if (!is.na(sha256[arq])) info$origem_sha256 <- unname(sha256[arq])

    catalogo$datasets[[dataset]]$arquivos[[arq]] <- info
  }

  for (dataset in datasets) {
    arqs <- names(catalogo$datasets[[dataset]]$arquivos)
    arqs <- arqs[order(arqs)]
    catalogo$datasets[[dataset]]$arquivos <- catalogo$datasets[[dataset]]$arquivos[arqs]
    catalogo$datasets[[dataset]]$anos <- as.list(as.integer(str_extract(arqs, "\\d{4}")))
    catalogo$datasets[[dataset]] <- catalogo$datasets[[dataset]][c("anos", "arquivos")]
  }

  catalogo <- list(
    atualizado_em = hoje,
    repo          = REPO,
    release_tag   = RELEASE_TAG,
    base_url      = BASE_URL,
    datasets      = catalogo$datasets[datasets]
  )

  write_json(catalogo, saida, pretty = TRUE, auto_unbox = TRUE)
  cli_inform("Catálogo escrito: {saida}")
  invisible(saida)
}

consolidar_tudo <- function() {
  if (!dir_exists(BASE_PROCESSADOS)) {
    cli_abort("Execute a partir do root do repositorio tidyprf-dados.")
  }

  cli_h1("Acidentes (2007-2026)")
  walk(2007:2026, consolidar_acidentes)

  cli_h1("Datatran (2007-2026)")
  walk(2007:2026, consolidar_datatran)

  cli_h1("Infrações (2019-2020, 2022-2026)")
  walk(c(2019, 2020, 2022:2026), consolidar_infracoes)

  cli_h1("Atualizando catálogo")
  atualizar_catalogo()

  cli_inform("Consolidação completa.")
  invisible(NULL)
}

# Executar so ao rodar diretamente (Rscript scripts/04_consolidar.R),
# nao quando carregado via source() por outro script
if (!interactive() && sys.nframe() == 0L) consolidar_tudo()
