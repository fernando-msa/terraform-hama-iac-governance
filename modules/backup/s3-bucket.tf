# ==============================================================================
# modules/backup/s3-bucket.tf
# Provisiona o bucket S3 de backup com controles de segurança e retenção.
# Controle: POP.HAMA.TI.004 — Procedimento Operacional de Backup e Restauração
#
# Recursos criados:
#   - aws_s3_bucket: bucket principal de backup
#   - aws_s3_bucket_versioning: habilita versionamento (requisito do POP)
#   - aws_s3_bucket_lifecycle_configuration: política de expiração de objetos
#   - aws_s3_bucket_server_side_encryption_configuration: criptografia em repouso
#   - aws_s3_bucket_public_access_block: bloqueia acesso público (LGPD)
#   - aws_s3_bucket_policy: política de bucket exigindo HTTPS (TLS)
# ==============================================================================

# Variáveis locais do módulo
variable "bucket_name_prefix" {
  description = "Prefixo para o nome do bucket (sufixo aleatório será adicionado)"
  type        = string
}

variable "suffix" {
  description = "Sufixo aleatório para unicidade do nome do bucket"
  type        = string
}

variable "retention_days" {
  description = "[POP.HAMA.TI.004] Dias para expiração de objetos"
  type        = number
  default     = 30
}

variable "version_retention_days" {
  description = "[POP.HAMA.TI.004] Dias para expiração de versões anteriores"
  type        = number
  default     = 90
}

variable "tags" {
  description = "Tags a serem aplicadas ao bucket (recebe tags_obrigatorias do módulo raiz)"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# BUCKET PRINCIPAL DE BACKUP
# Nome único globalmente na AWS usando sufixo aleatório.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "backup" {
  bucket = "${var.bucket_name_prefix}-${var.suffix}"

  # Evita destruição acidental de dados em produção
  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = merge(var.tags, {
    Finalidade    = "backup-operacional"
    POP           = "POP.HAMA.TI.004"
    TipoRecurso   = "armazenamento-backup"
  })
}

# ------------------------------------------------------------------------------
# VERSIONAMENTO — POP.HAMA.TI.004
# Habilita versionamento para permitir restauração de versões anteriores.
# Obrigatório pelo POP de backup: permite recuperação pós-exclusão acidental.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "backup" {
  bucket = aws_s3_bucket.backup.id

  versioning_configuration {
    status = "Enabled" # Nunca desabilitar em produção — use "Suspended" se necessário
  }
}

# ------------------------------------------------------------------------------
# POLÍTICA DE CICLO DE VIDA — POP.HAMA.TI.004
# Define quando objetos e versões são automaticamente expirados.
# Alinha com as políticas de retenção documentadas no POP de backup.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "backup" {
  # Depende do versionamento estar habilitado antes de configurar o lifecycle
  depends_on = [aws_s3_bucket_versioning.backup]

  bucket = aws_s3_bucket.backup.id

  # Regra 1: Expirar objetos correntes após N dias (padrão: 30)
  rule {
    id     = "expira-objetos-correntes"
    status = "Enabled"

    # Aplica a todos os objetos no bucket (prefixo vazio = todos)
    filter {
      prefix = ""
    }

    # Expirar objeto após o número de dias configurado
    expiration {
      days = var.retention_days
    }
  }

  # Regra 2: Expirar versões não-correntes após 90 dias
  # Importante para controle de custos sem perder rastreabilidade
  rule {
    id     = "expira-versoes-anteriores"
    status = "Enabled"

    filter {
      prefix = ""
    }

    # Move versões não-correntes para expiração
    noncurrent_version_expiration {
      noncurrent_days = var.version_retention_days
    }

    # Remove marcadores de exclusão órfãos (boa prática de limpeza)
    expiration {
      expired_object_delete_marker = true
    }
  }

  # Regra 3: Transição para Glacier após 30 dias (economia de custo em produção real)
  # Descomentada para demonstração — em Free Tier, Glacier tem custo de restauração
  # rule {
  #   id     = "transicao-glacier"
  #   status = "Enabled"
  #   filter { prefix = "backups/" }
  #   transition {
  #     days          = 30
  #     storage_class = "GLACIER"
  #   }
  # }
}

# ------------------------------------------------------------------------------
# CRIPTOGRAFIA EM REPOUSO (SSE-S3) — ISO 27001 A.10.1.1 / LGPD Art. 46
# Todos os objetos são criptografados automaticamente com chave gerenciada pela AWS.
# Para ambientes com requisitos mais rígidos, use SSE-KMS com chave própria.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "backup" {
  bucket = aws_s3_bucket.backup.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256" # SSE-S3: criptografia gerenciada pela AWS (Free Tier)
      # Para SSE-KMS: sse_algorithm = "aws:kms" (tem custo de KMS)
    }

    # Garante que novos objetos sempre sejam criptografados, mesmo que o cliente
    # envie sem especificar criptografia
    bucket_key_enabled = true
  }
}

# ------------------------------------------------------------------------------
# BLOQUEIO DE ACESSO PÚBLICO — LGPD Art. 46 / ISO 27001 A.9.4.1
# Garante que dados de backup nunca sejam acessíveis publicamente.
# Esta configuração sobrescreve qualquer policy que tente conceder acesso público.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "backup" {
  bucket = aws_s3_bucket.backup.id

  block_public_acls       = true # Bloqueia novas ACLs públicas
  block_public_policy     = true # Bloqueia políticas de bucket que permitam acesso público
  ignore_public_acls      = true # Ignora ACLs públicas existentes
  restrict_public_buckets = true # Restringe acesso público mesmo com policy permissiva
}

# ------------------------------------------------------------------------------
# POLÍTICA DE BUCKET: Exige HTTPS (TLS) em todas as requisições
# Garante que dados em trânsito sejam sempre criptografados — LGPD Art. 46
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "backup_https_only" {
  bucket = aws_s3_bucket.backup.id

  # Depende do bloqueio de acesso público estar configurado primeiro
  depends_on = [aws_s3_bucket_public_access_block.backup]

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "DenyNonTLS"
    Statement = [
      {
        Sid       = "DenyHTTP"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.backup.arn,
          "${aws_s3_bucket.backup.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false" # Nega qualquer requisição sem TLS
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# OUTPUTS DO MÓDULO DE BACKUP
# ------------------------------------------------------------------------------
output "bucket_name" {
  description = "Nome do bucket S3 de backup"
  value       = aws_s3_bucket.backup.id
}

output "bucket_arn" {
  description = "ARN do bucket S3 de backup"
  value       = aws_s3_bucket.backup.arn
}

output "bucket_region" {
  description = "Região do bucket S3 de backup"
  value       = aws_s3_bucket.backup.region
}

output "bucket_domain_name" {
  description = "Nome de domínio do bucket (para configuração de clientes de backup)"
  value       = aws_s3_bucket.backup.bucket_domain_name
}
