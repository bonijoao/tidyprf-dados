library(stringr)
library(purrr)
library(tools)

dir_base <- "dados/brutos"

# LISTAR ARQUIVOS BAIXADOS
arquivos <- list.files(dir_base, full.names = TRUE)

# ---------------------------
# 1) IDENTIFICAR CORROMPIDOS
# ---------------------------

# função: verifica se é zip válido
is_zip_valido <- function(file) {
  ext <- tools::file_ext(file)
  
  # tem que ser zip
  if (ext != "zip") return(FALSE)
  
  # tenta listar conteúdo
  res <- try(unzip(file, list = TRUE), silent = TRUE)
  
  return(!inherits(res, "try-error"))
}

validos <- map_lgl(arquivos, is_zip_valido)

corrompidos <- arquivos[!validos]

cat("Corrompidos encontrados:\n")
print(basename(corrompidos))

# ---------------------------
# 2) REBAIXAR CORRETAMENTE
# ---------------------------

# função para extrair ID do nome (já que veio zoado)
extrair_id_nome <- function(path) {
  nome <- basename(path)
  str_extract(nome, "[A-Za-z0-9_-]{20,}")
}

ids_corrompidos <- map_chr(corrompidos, extrair_id_nome)

# função correta de download
baixar_drive_fix <- function(id, destino) {
  
  url <- paste0("https://drive.google.com/uc?export=download&id=", id)
  
  download.file(url, destino, mode = "wb", quiet = TRUE)
}

# apagar corrompidos
file.remove(corrompidos)

# baixar novamente
walk(ids_corrompidos, function(id) {
  
  destino <- file.path(dir_base, paste0(id, ".rar"))
  
  baixar_drive_fix(id, destino)
})

# ---------------------------
# 3) DESCOMPACTAR E RENOMEAR
# ---------------------------

arquivos <- list.files(dir_base, full.names = TRUE)

dir.create("dados/processados", showWarnings = FALSE)

walk(arquivos, function(zip_file) {
  
  # listar conteúdo interno
  conteudo <- unzip(zip_file, list = TRUE)
  
  nome_real <- conteudo$Name[1]
  
  destino <- file.path("dados/processados", nome_real)
  
  unzip(zip_file, exdir = "dados/processados")
  
})
