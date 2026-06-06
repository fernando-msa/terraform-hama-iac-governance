# ==============================================================================
# modules/tags/main.tf
# Módulo responsável por centralizar e padronizar as tags obrigatórias.
# Controle: DIR.MMLN.TI.001 — Gestão de Ativos Tecnológicos
#
# Este módulo não cria recursos AWS. Seu papel é:
# 1. Receber os valores de tag como input
# 2. Montar o mapa completo de tags (obrigatórias + opcionais)
# 3. Expor via output para uso em outros módulos
#
# A validação de campos obrigatórios ocorre nas variables.tf do módulo.
# ==============================================================================

locals {
  # Mapa base de tags obrigatórias — todos os campos são requeridos pela DIR.MMLN.TI.001
  tags_base = {
    Setor         = var.setor
    DataAquisicao = var.data_aquisicao
    DataFimVida   = var.data_fim_vida
    Responsavel   = var.responsavel
    CustoCentro   = var.custo_centro
    Ambiente      = var.ambiente
    Projeto       = var.projeto
  }

  # Tags de rastreabilidade de infraestrutura como código
  tags_iac = {
    GerenciadoPor = "Terraform"
    Repositorio   = "terraform-hama-iac-governance"
    Norma         = "DIR.MMLN.TI.001,ISO27001,LGPD"
  }

  # Merge final: tags obrigatórias + tags IaC + tags adicionais opcionais
  tags_completas = merge(
    local.tags_base,
    local.tags_iac,
    var.tags_adicionais
  )
}
