# install.packages(c("rvest", "stringr", "purrr", "googledrive"))
library(rvest)
library(stringr)
library(purrr)
library(googledrive)

# URL da página com os dados
url_base <- "https://www.gov.br/prf/pt-br/acesso-a-informacao/dados-abertos/dados-abertos-da-prf"

# Ler HTML
pagina <- read_html(url_base)

# Pegar TODOS os links da página
links <- pagina %>%
  html_elements("a") %>%
  html_attr("href")

# Filtrar links que levam ao Google Drive
links_drive <- links[str_detect(links, "drive.google.com")]

# Função para extrair ID do Google Drive
extrair_id <- function(link) {
  id <- str_extract(link, "(?<=/d/)[^/]+")
  
  if (is.na(id)) {
    id <- str_extract(link, "(?<=id=)[^&]+")
  }
  
  return(id)
}

ids <- map_chr(links_drive, extrair_id)

# Remover NAs
ids <- ids[!is.na(ids)]

# Baixar arquivos
walk(ids, function(id) {
  
  try({
    drive_download(
      as_id(id),
      path = file.path("dados/brutos", paste0(id, ".zip")), # pode ajustar extensão
      overwrite = TRUE
    )
  })
  
})

baixar_drive <- function(id, destino) {
  url <- paste0("https://drive.google.com/uc?export=download&id=", id)
  download.file(url, destino, mode = "wb")
}

walk(ids, function(id) {
  baixar_drive(id, file.path("dados/brutos", paste0(id, ".zip")))
})
