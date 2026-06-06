# ==============================================================================
# modules/tags/variables.tf
# Variáveis de entrada do módulo de tags obrigatórias.
# Cada campo corresponde a um atributo de inventário da DIR.MMLN.TI.001.
# ==============================================================================

variable "setor" {
  description = "[DIR.MMLN.TI.001] Setor do hospital responsável pelo ativo"
  type        = string
}

variable "data_aquisicao" {
  description = "[DIR.MMLN.TI.001] Data de aquisição no formato YYYY-MM-DD"
  type        = string
}

variable "data_fim_vida" {
  description = "[DIR.MMLN.TI.001] Data de fim de vida útil (8 anos após aquisição)"
  type        = string
}

variable "responsavel" {
  description = "[DIR.MMLN.TI.001] Responsável técnico pelo ativo"
  type        = string
}

variable "custo_centro" {
  description = "[DIR.MMLN.TI.001] Centro de custo do ativo"
  type        = string
}

variable "ambiente" {
  description = "Ambiente de implantação (producao, homologacao, desenvolvimento)"
  type        = string
}

variable "projeto" {
  description = "Nome do projeto associado ao ativo"
  type        = string
}

variable "tags_adicionais" {
  description = "Tags opcionais adicionais para contextos específicos"
  type        = map(string)
  default     = {}
}
