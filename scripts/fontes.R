# scripts/fontes.R
# Descobre os links do Google Drive publicados na pagina de dados abertos da
# PRF e baixa os arquivos compactados. Usado por scripts/05_atualizar.R.

suppressPackageStartupMessages({
  library(rvest)
  library(dplyr)
  library(purrr)
  library(stringr)
  library(jsonlite)
  library(cli)
})

URL_PAGINA_PRF <- paste0(
  "https://www.gov.br/prf/pt-br/acesso-a-informacao/",
  "dados-abertos/dados-abertos-da-prf"
)
ARQUIVO_FONTES <- "fontes.json"

extrair_id <- function(link) {
  id <- str_extract(link, "(?<=/d/)[^/?]+")
  if (is.na(id)) id <- str_extract(link, "(?<=id=)[^&]+")
  id
}

# Classifica o texto da coluna "Referência" da pagina
classificar_referencia <- function(texto) {
  texto <- str_squish(texto)
  case_when(
    str_detect(texto, regex("multas", ignore_case = TRUE)) ~ "infracoes",
    str_detect(texto, regex("por ocorr", ignore_case = TRUE)) ~ "datatran",
    str_detect(texto, regex("todas as causas", ignore_case = TRUE)) ~ "acidentes",
    .default = NA_character_
  )
}

# Le a pagina da PRF: cada linha das tabelas tem
# [Documento CSV de ... AAAA (...)] [Baixar planilha -> Google Drive]
raspar_fontes <- function(url = URL_PAGINA_PRF) {
  pagina <- read_html(url)
  linhas <- html_elements(pagina, "table tr")

  fontes <- map(linhas, function(tr) {
    celulas <- html_elements(tr, "td")
    if (length(celulas) < 2) return(NULL)

    referencia <- html_text2(celulas[[1]])
    # A pagina tem <a> vazios com links lixo; so vale o link com texto
    links <- html_elements(celulas[[2]], "a")
    links <- links[nzchar(str_squish(html_text2(links)))]
    links <- links[str_detect(html_attr(links, "href"), "drive\\.google\\.com")]
    if (length(links) == 0) return(NULL)

    tibble(
      dataset    = classificar_referencia(referencia),
      ano        = as.integer(str_extract(referencia, "\\b(19|20)\\d{2}\\b")),
      drive_id   = extrair_id(html_attr(links[[1]], "href")),
      referencia = str_squish(referencia)
    )
  }) |>
    list_rbind() |>
    filter(!is.na(dataset), !is.na(ano), !is.na(drive_id)) |>
    distinct(dataset, ano, .keep_all = TRUE) |>
    arrange(dataset, ano)

  ano_atual <- as.integer(format(Sys.Date(), "%Y"))
  faltando <- setdiff(c("acidentes", "datatran", "infracoes"), fontes$dataset)
  if (length(faltando) > 0) {
    cli_abort("Pagina da PRF sem links para: {faltando}. O layout mudou?")
  }
  if (!any(fontes$ano >= ano_atual - 1)) {
    cli_abort("Nenhum link recente (>= {ano_atual - 1}) encontrado na pagina da PRF.")
  }

  fontes
}

# Tenta raspar a pagina; se falhar usa o ultimo snapshot em fontes.json
listar_fontes <- function() {
  fontes <- tryCatch(raspar_fontes(), error = function(e) {
    if (!file.exists(ARQUIVO_FONTES)) stop(e)
    cli_warn(c(
      "Falha ao ler a pagina da PRF; usando {ARQUIVO_FONTES}.",
      "x" = conditionMessage(e)
    ))
    NULL
  })

  if (is.null(fontes)) {
    return(as_tibble(read_json(ARQUIVO_FONTES, simplifyVector = TRUE)$fontes))
  }

  # Sem data de raspagem: o arquivo so muda (e gera commit) quando a PRF
  # troca algum link
  write_json(list(fontes = fontes), ARQUIVO_FONTES, pretty = TRUE, auto_unbox = TRUE)
  fontes
}

# Download direto do Google Drive (confirm=t pula a pagina de aviso de
# arquivo grande, que gerava HTML no lugar do zip)
baixar_fonte <- function(drive_id, destino) {
  url <- paste0(
    "https://drive.usercontent.google.com/download?id=", drive_id,
    "&export=download&confirm=t"
  )
  httr2::request(url) |>
    httr2::req_retry(max_tries = 3) |>
    httr2::req_timeout(1800) |>
    httr2::req_perform(path = destino)

  conteudo <- tryCatch(unzip(destino, list = TRUE), error = function(e) NULL)
  if (is.null(conteudo) || nrow(conteudo) == 0) {
    cli_abort("Download de {drive_id} nao e um zip valido.")
  }
  invisible(conteudo)
}
