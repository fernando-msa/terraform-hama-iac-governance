# ==============================================================================
# main.tf
# Configuração raiz do projeto terraform-hama-iac-governance.
# Orquestra todos os módulos e define o provider AWS com tags padrão globais.
#
# Referências:
#   DIR.MMLN.TI.001 — Gestão de Ativos Tecnológicos
#   DIR.MMLN.TI.002 — Diretrizes de Restrição de Uso
#   POP.HAMA.TI.004 — Procedimento de Backup
#   POP.HAMA.TI.005 — Procedimento de SLA
#   FORM.HAMA.TI.015 — Checklist de Controle de Acesso à Sala de Rack
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.5"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
  }

  # Descomente e configure para armazenar o state remotamente (recomendado em produção):
  # backend "s3" {
  #   bucket = "meu-bucket-terraform-state"
  #   key    = "hama-iac-governance/terraform.tfstate"
  #   region = "us-east-1"
  # }
}

# ------------------------------------------------------------------------------
# PROVIDER AWS
# O bloco default_tags aplica as tags obrigatórias em TODOS os recursos,
# implementando automaticamente o controle DIR.MMLN.TI.001.
# ------------------------------------------------------------------------------
provider "aws" {
  region = var.aws_region

  # Tags aplicadas globalmente em todos os recursos — DIR.MMLN.TI.001
  default_tags {
    tags = local.tags_obrigatorias
  }
}

# ------------------------------------------------------------------------------
# DATA SOURCES
# Coleta informações da conta AWS sem criar recursos adicionais.
# ------------------------------------------------------------------------------

# Obtém detalhes da conta AWS atual (ID, ARN, alias)
data "aws_caller_identity" "current" {}

# Obtém a região atual configurada no provider
data "aws_region" "current" {}

# Obtém informações sobre as zonas de disponibilidade da região
data "aws_availability_zones" "available" {
  state = "available"
}

# ------------------------------------------------------------------------------
# LOCALS
# Centraliza a lógica de composição de tags e nomes de recursos.
# Evita repetição e garante consistência em todo o projeto.
# ------------------------------------------------------------------------------
locals {
  # Sufixo aleatório para garantir unicidade nos nomes de buckets S3
  # (nomes de buckets S3 são globais na AWS)
  resource_suffix = random_id.suffix.hex

  # Prefixo padrão para nomear todos os recursos
  name_prefix = "${var.project_name}-${var.environment}"

  # ============================================================================
  # TAGS OBRIGATÓRIAS — DIR.MMLN.TI.001
  # Implementa o inventário de ativos de TI como metadados em cada recurso AWS.
  # Campo DataFimVida: calculado como 8 anos após DataAquisicao, conforme diretriz.
  # ============================================================================
  tags_obrigatorias = {
    Setor         = var.tag_setor
    DataAquisicao = var.tag_data_aquisicao
    DataFimVida   = var.tag_data_fim_vida # 8 anos — conforme DIR.MMLN.TI.001
    Responsavel   = var.tag_responsavel
    CustoCentro   = var.tag_custo_centro
    Ambiente      = var.environment
    Projeto       = var.project_name
    GerenciadoPor = "Terraform"
    Repositorio   = "terraform-hama-iac-governance"
  }

  # Informações da conta para uso em ARNs e policies
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ------------------------------------------------------------------------------
# RECURSO AUXILIAR: Sufixo aleatório para unicidade de nomes
# ------------------------------------------------------------------------------
resource "random_id" "suffix" {
  byte_length = 4
}

# ------------------------------------------------------------------------------
# MÓDULO: Tags Obrigatórias
# Expõe as tags como output reutilizável por outros módulos.
# Controle: DIR.MMLN.TI.001
# ------------------------------------------------------------------------------
module "tags" {
  source = "./modules/tags"

  setor          = var.tag_setor
  data_aquisicao = var.tag_data_aquisicao
  data_fim_vida  = var.tag_data_fim_vida
  responsavel    = var.tag_responsavel
  custo_centro   = var.tag_custo_centro
  ambiente       = var.environment
  projeto        = var.project_name
}

# ------------------------------------------------------------------------------
# MÓDULO: Backup S3
# Provisiona bucket com versionamento e lifecycle conforme POP.HAMA.TI.004.
# ------------------------------------------------------------------------------
module "backup" {
  source = "./modules/backup"

  bucket_name_prefix    = "${local.name_prefix}-backup"
  suffix                = local.resource_suffix
  retention_days        = var.backup_retention_days
  version_retention_days = var.backup_version_retention_days
  tags                  = local.tags_obrigatorias
}

# ------------------------------------------------------------------------------
# MÓDULO: Monitoramento e Alarmes
# Provisiona CloudWatch Alarm para SLA e Lambda de verificação de Wi-Fi.
# Controles: POP.HAMA.TI.005 e CHK.HAMA.TI.WIFI
# ------------------------------------------------------------------------------
module "monitoring" {
  source = "./modules/monitoring"

  project_name          = var.project_name
  environment           = var.environment
  sla_threshold_minutes = var.sla_threshold_minutes
  alert_email           = var.alert_email
  account_id            = local.account_id
  region                = local.region
  suffix                = local.resource_suffix
  tags                  = local.tags_obrigatorias
}
