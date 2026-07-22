library(fs)
library(stringr)
library(purrr)

dir_base <- "dados/brutos"

# ---------------------------
# FUNÇÃO: verificar se já foi extraído (CORRETA)
# ---------------------------
ja_extraido <- function(arquivo) {
  
  pasta_destino <- dirname(arquivo)
  ext <- tools::file_ext(arquivo)
  
  conteudo <- tryCatch({
    
    if (ext == "zip") {
      unzip(arquivo, list = TRUE)$Name
    } else {
      return(FALSE) # não tenta validar rar
    }
    
  }, error = function(e) return(FALSE))
  
  if (length(conteudo) == 0) return(FALSE)
  
  caminhos <- file.path(pasta_destino, conteudo)
  
  # verifica se TODOS os arquivos existem
  all(file.exists(caminhos))
}

# ---------------------------
# FUNÇÃO: extrair
# ---------------------------
extrair_arquivo <- function(arquivo) {
  
  pasta_destino <- dirname(arquivo)
  ext <- tools::file_ext(arquivo)
  
  if (ja_extraido(arquivo)) {
    message("⏭️ Já extraído (correto): ", basename(arquivo))
    return(NULL)
  }
  
  message("📦 Extraindo: ", basename(arquivo))
  
  tryCatch({
    
    if (ext == "zip") {
      
      unzip(arquivo, exdir = pasta_destino)
      
    } else if (ext == "rar") {
      
      # Windows: tenta usar unrar
      status <- system2("unrar", args = c("x", "-o+", shQuote(arquivo), shQuote(pasta_destino)))
      
      if (status != 0) {
        stop("Erro ao extrair RAR (verifique se unrar está instalado)")
      }
      
    } else {
      message("⚠️ Formato não suportado: ", arquivo)
    }
    
  }, error = function(e) {
    
    message("❌ ERRO ao extrair: ", basename(arquivo))
    message("   → ", e$message)
    
  })
}

# ---------------------------
# LISTAR ARQUIVOS
# ---------------------------
arquivos_compactados <- dir_ls(
  dir_base,
  recurse = TRUE,
  regexp = "\\.(zip|rar)$",
  type = "file"
)

# ---------------------------
# EXECUTAR
# ---------------------------
walk(arquivos_compactados, extrair_arquivo)
