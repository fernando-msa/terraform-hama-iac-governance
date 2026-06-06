# ==============================================================================
# variables.tf
# Declaração de todas as variáveis do projeto com validação e documentação.
# Reflete os campos obrigatórios definidos na DIR.MMLN.TI.001 (Gestão de Ativos).
# ==============================================================================

# ------------------------------------------------------------------------------
# VARIÁVEIS DE AMBIENTE E PROJETO
# ------------------------------------------------------------------------------

variable "aws_region" {
  description = "Região AWS onde os recursos serão provisionados"
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "A região AWS deve estar no formato 'us-east-1', 'sa-east-1', etc."
  }
}

variable "environment" {
  description = "Ambiente de implantação (producao, homologacao, desenvolvimento)"
  type        = string
  default     = "producao"

  validation {
    condition     = contains(["producao", "homologacao", "desenvolvimento"], var.environment)
    error_message = "O ambiente deve ser 'producao', 'homologacao' ou 'desenvolvimento'."
  }
}

variable "project_name" {
  description = "Nome do projeto para composição de nomes de recursos"
  type        = string
  default     = "hama-iac-governance"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,30}$", var.project_name))
    error_message = "O nome do projeto deve ter 3-31 caracteres, iniciar com letra minúscula e conter apenas letras, números e hífens."
  }
}

# ------------------------------------------------------------------------------
# TAGS OBRIGATÓRIAS — DIR.MMLN.TI.001 (Gestão de Ativos Tecnológicos)
# Todos os campos abaixo são obrigatórios conforme a diretriz de inventário.
# ------------------------------------------------------------------------------

variable "tag_setor" {
  description = "[DIR.MMLN.TI.001] Setor responsável pelo ativo (ex: TI, Radiologia, UTI)"
  type        = string
  default     = "TI"

  validation {
    condition     = length(trimspace(var.tag_setor)) > 0
    error_message = "O campo 'Setor' não pode ser vazio. Obrigatório pela DIR.MMLN.TI.001."
  }
}

variable "tag_data_aquisicao" {
  description = "[DIR.MMLN.TI.001] Data de aquisição do ativo no formato YYYY-MM-DD"
  type        = string
  default     = "2025-01-01"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.tag_data_aquisicao))
    error_message = "A data de aquisição deve estar no formato YYYY-MM-DD (ex: 2025-01-01)."
  }
}

variable "tag_data_fim_vida" {
  description = "[DIR.MMLN.TI.001] Data de fim de vida útil (8 anos após aquisição, conforme diretriz)"
  type        = string
  default     = "2033-01-01"

  validation {
    condition     = can(regex("^\\d{4}-\\d{2}-\\d{2}$", var.tag_data_fim_vida))
    error_message = "A data de fim de vida deve estar no formato YYYY-MM-DD (ex: 2033-01-01)."
  }
}

variable "tag_responsavel" {
  description = "[DIR.MMLN.TI.001] E-mail ou nome do responsável técnico pelo ativo"
  type        = string
  default     = "ti-hama@igh.org.br"

  validation {
    condition     = length(trimspace(var.tag_responsavel)) > 3
    error_message = "O responsável deve ser identificado com pelo menos 4 caracteres (e-mail ou nome)."
  }
}

variable "tag_custo_centro" {
  description = "[DIR.MMLN.TI.001] Centro de custo contábil associado ao ativo"
  type        = string
  default     = "TI-HAMA"

  validation {
    condition     = length(trimspace(var.tag_custo_centro)) > 0
    error_message = "O campo 'CustoCentro' não pode ser vazio. Obrigatório pela DIR.MMLN.TI.001."
  }
}

# ------------------------------------------------------------------------------
# VARIÁVEIS DE BACKUP — POP.HAMA.TI.004
# ------------------------------------------------------------------------------

variable "backup_retention_days" {
  description = "[POP.HAMA.TI.004] Dias de retenção dos objetos no bucket de backup"
  type        = number
  default     = 30

  validation {
    condition     = var.backup_retention_days >= 7 && var.backup_retention_days <= 365
    error_message = "A retenção de backup deve ser entre 7 e 365 dias, conforme POP.HAMA.TI.004."
  }
}

variable "backup_version_retention_days" {
  description = "[POP.HAMA.TI.004] Dias de retenção de versões anteriores no bucket de backup"
  type        = number
  default     = 90

  validation {
    condition     = var.backup_version_retention_days >= 30
    error_message = "A retenção de versões deve ser de no mínimo 30 dias."
  }
}

# ------------------------------------------------------------------------------
# VARIÁVEIS DE MONITORAMENTO — POP.HAMA.TI.005
# ------------------------------------------------------------------------------

variable "sla_threshold_minutes" {
  description = "[POP.HAMA.TI.005] Limiar de SLA em minutos para disparo de alarme (tempo de resposta de chamado)"
  type        = number
  default     = 240 # 4 horas — SLA nível P2 conforme POP.HAMA.TI.005

  validation {
    condition     = var.sla_threshold_minutes > 0 && var.sla_threshold_minutes <= 1440
    error_message = "O limiar de SLA deve ser entre 1 e 1440 minutos (24 horas)."
  }
}

variable "alert_email" {
  description = "[POP.HAMA.TI.005] E-mail que receberá alertas de violação de SLA via SNS"
  type        = string
  default     = "ti-hama@igh.org.br"

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.alert_email))
    error_message = "O e-mail de alerta deve ser um endereço válido."
  }
}

# ------------------------------------------------------------------------------
# VARIÁVEIS DE ACESSO — FORM.HAMA.TI.015
# ------------------------------------------------------------------------------

variable "tecnico_rack_allowed_ips" {
  description = "[FORM.HAMA.TI.015] Lista de IPs permitidos para acesso de técnicos ao rack (para condição de policy)"
  type        = list(string)
  default     = ["10.0.0.0/8"] # Rede interna do hospital

  validation {
    condition     = length(var.tecnico_rack_allowed_ips) > 0
    error_message = "Deve haver ao menos um CIDR de IP permitido para acesso ao rack."
  }
}

variable "cloudtrail_retention_days" {
  description = "[ISO 27001 A.12.4.1] Dias de retenção dos logs do CloudTrail no S3"
  type        = number
  default     = 365 # 1 ano — exigência mínima de auditoria

  validation {
    condition     = var.cloudtrail_retention_days >= 90
    error_message = "Logs de auditoria devem ser retidos por no mínimo 90 dias (ISO 27001 A.12.4.1)."
  }
}
