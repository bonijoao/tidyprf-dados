# scripts/05_atualizar.R
# Atualizacao incremental dos dados (usado pelo GitHub Actions, mas roda
# localmente igual). Executar a partir do root do repositorio:
#   Rscript scripts/05_atualizar.R
#
# Variaveis de ambiente:
#   TIDYPRF_ANOS    anos a verificar, ex. "2025,2026" (padrao: ano atual e anterior)
#   TIDYPRF_FORCAR  "1" reprocessa mesmo se o zip de origem nao mudou
#
# Resultado:
#   dados/consolidados/<dataset>/<dataset>_<ano>.parquet  (so os que mudaram)
#   catalogo.json atualizado para esses arquivos
#   alterados.txt com os caminhos dos Parquets a publicar (vazio = nada novo)

source("scripts/fontes.R")
source("scripts/04_consolidar.R")

# Tudo e processado numa area temporaria; so vai para dados/consolidados e
# para o catalogo depois de todas as validacoes passarem
DIR_TRABALHO      <- "dados/atualizacao"
BASE_PROCESSADOS  <- path(DIR_TRABALHO, "processados")
BASE_CONSOLIDADOS <- path(DIR_TRABALHO, "consolidados")
DESTINO_FINAL     <- "dados/consolidados"

SCHEMAS <- list(
  acidentes = SCHEMA_ACIDENTES,
  datatran  = SCHEMA_DATATRAN,
  infracoes = SCHEMA_INFRACOES
)
CONSOLIDAR <- list(
  acidentes = consolidar_acidentes,
  datatran  = consolidar_datatran,
  infracoes = consolidar_infracoes
)

anos_alvo <- function() {
  env <- Sys.getenv("TIDYPRF_ANOS")
  if (nzchar(env)) {
    anos <- as.integer(str_split_1(env, "[,; ]+"))
    if (anyNA(anos)) cli_abort("TIDYPRF_ANOS invalido: {env}")
    return(anos)
  }
  ano <- as.integer(format(Sys.Date(), "%Y"))
  c(ano - 1L, ano)
}

validar_parquet <- function(caminho, dataset, ano_arquivo, info_antiga) {
  ds     <- open_dataset(caminho)
  linhas <- nrow(ds)
  erros  <- character()

  if (!identical(names(ds), SCHEMAS[[dataset]])) {
    erros <- c(erros, "Colunas diferentes do schema esperado.")
  }
  if (linhas == 0) {
    erros <- c(erros, "Arquivo sem linhas.")
  }
  if (!is.null(info_antiga$linhas) && linhas < 0.99 * info_antiga$linhas) {
    erros <- c(erros, glue(
      "Linhas cairam de {info_antiga$linhas} para {linhas} (> 1%)."
    ))
  }
  if (linhas > 0) {
    no_ano <- ds |>
      summarise(n = sum(as.integer(!is.na(ano) & ano == !!ano_arquivo))) |>
      collect() |>
      pull(n)
    if (no_ano / linhas < 0.95) {
      erros <- c(erros, glue(
        "So {round(100 * no_ano / linhas, 1)}% das linhas tem data valida em {ano_arquivo}."
      ))
    }
  }

  if (length(erros) > 0) {
    cli_abort(c("Validacao falhou para {path_file(caminho)}:", set_names(erros, "x")))
  }
  cli_inform(c("v" = "{path_file(caminho)} validado ({linhas} linhas)."))
}

main <- function() {
  forcar <- identical(Sys.getenv("TIDYPRF_FORCAR"), "1")
  anos   <- anos_alvo()
  cli_h1("Atualizando dados PRF: {anos}")

  if (dir_exists(DIR_TRABALHO)) dir_delete(DIR_TRABALHO)
  dir_create(c(BASE_PROCESSADOS, BASE_CONSOLIDADOS))
  writeLines(character(), "alterados.txt")

  catalogo <- read_json("catalogo.json", simplifyVector = FALSE)
  fontes   <- listar_fontes() |> filter(ano %in% anos)

  if (nrow(fontes) == 0) {
    cli_abort("Nenhuma fonte na pagina da PRF para os anos {anos}.")
  }

  novos  <- character()
  sha256 <- character()

  for (i in seq_len(nrow(fontes))) {
    f   <- fontes[i, ]
    arq <- glue("{f$dataset}_{f$ano}.parquet")
    cli_h2(arq)

    zip <- path(DIR_TRABALHO, glue("{f$dataset}_{f$ano}.zip"))
    baixar_fonte(f$drive_id, zip)
    hash <- digest::digest(file = zip, algo = "sha256")

    info_antiga <- catalogo$datasets[[f$dataset]]$arquivos[[arq]]
    if (!forcar && identical(info_antiga$origem_sha256, hash)) {
      cli_inform(c("i" = "Sem mudancas na origem."))
      file_delete(zip)
      next
    }

    unzip(zip, exdir = BASE_PROCESSADOS)
    file_delete(zip)

    CONSOLIDAR[[f$dataset]](f$ano)
    saida <- path(BASE_CONSOLIDADOS, f$dataset, arq)
    if (!file_exists(saida)) cli_abort("{arq} nao foi gerado.")
    validar_parquet(saida, f$dataset, f$ano, info_antiga)

    novos  <- c(novos, saida)
    sha256 <- c(sha256, set_names(hash, arq))

    # Libera disco antes do proximo dataset
    dir_delete(BASE_PROCESSADOS)
    dir_create(BASE_PROCESSADOS)
  }

  if (length(novos) == 0) {
    dir_delete(DIR_TRABALHO)
    cli_alert_success("Nenhum dado novo.")
    return(invisible(character()))
  }

  finais <- path(DESTINO_FINAL, path_file(path_dir(novos)), path_file(novos))
  dir_create(path_dir(finais))
  file_copy(novos, finais, overwrite = TRUE)

  atualizar_catalogo(finais, sha256)
  writeLines(as.character(finais), "alterados.txt")
  dir_delete(DIR_TRABALHO)

  cli_alert_success("Atualizados: {path_file(finais)}")
  invisible(finais)
}

main()
