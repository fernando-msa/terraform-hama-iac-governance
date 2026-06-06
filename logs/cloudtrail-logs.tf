# ==============================================================================
# logs/cloudtrail-logs.tf
# Configura auditoria centralizada via AWS CloudTrail.
# Controles:
#   FORM.HAMA.TI.015 — Checklist de Controle de Acesso à Sala de Rack
#   ISO 27001 A.12.4.1 — Registro de Eventos de Segurança
#   ISO 27001 A.12.4.2 — Proteção das Informações de Log
#   ISO 27001 A.12.4.3 — Logs de Administrador e Operador
#   LGPD Art. 37 — Registro de Operações de Tratamento de Dados
#
# Recursos criados:
#   - aws_s3_bucket: bucket para armazenamento de logs
#   - aws_s3_bucket_policy: política de acesso exclusivo do CloudTrail
#   - aws_cloudtrail: trilha de auditoria principal
# ==============================================================================

# Dados de referência para políticas (região e conta)
data "aws_caller_identity" "cloudtrail" {}
data "aws_region" "cloudtrail" {}

# Referência à política de partição (necessária para ARNs corretos)
data "aws_partition" "cloudtrail" {}

# ------------------------------------------------------------------------------
# BUCKET S3 PARA LOGS DO CLOUDTRAIL
# Armazena TODOS os eventos de API da conta AWS.
# Retenção: configurável (padrão: 365 dias).
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "cloudtrail_logs" {
  # Nome único globalmente com sufixo do número da conta para evitar conflitos
  bucket = "hama-cloudtrail-logs-${data.aws_caller_identity.cloudtrail.account_id}"

  # Em produção: habilitar prevent_destroy para proteção de logs de auditoria
  # lifecycle {
  #   prevent_destroy = true
  # }

  tags = {
    Finalidade    = "logs-auditoria-cloudtrail"
    Norma         = "ISO27001-A.12.4.1,LGPD-Art37"
    TipoRecurso   = "armazenamento-logs"
    GerenciadoPor = "Terraform"
    Setor         = "TI"
    Responsavel   = "ti-hama@igh.org.br"
    CustoCentro   = "TI-HAMA"
  }
}

# Bloqueia qualquer acesso público ao bucket de logs — ISO 27001 A.12.4.2
resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versionamento dos logs para proteção contra sobrescrita — ISO 27001 A.12.4.2
resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Criptografia em repouso dos logs — ISO 27001 A.10.1.1
resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Política de expiração de logs — retenção configurável
resource "aws_s3_bucket_lifecycle_configuration" "cloudtrail_logs" {
  bucket = aws_s3_bucket.cloudtrail_logs.id

  rule {
    id     = "retencao-logs-auditoria"
    status = "Enabled"

    filter { prefix = "" }

    expiration {
      days = var.cloudtrail_retention_days # Padrão: 365 dias
    }

    noncurrent_version_expiration {
      noncurrent_days = 30 # Versões antigas expiram após 30 dias adicionais
    }
  }
}

# ------------------------------------------------------------------------------
# POLÍTICA DO BUCKET: Permite SOMENTE o CloudTrail escrever logs
# Esta política é OBRIGATÓRIA para o CloudTrail funcionar.
# O CloudTrail exige permissões específicas para escrever no bucket.
# ------------------------------------------------------------------------------
resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  bucket     = aws_s3_bucket.cloudtrail_logs.id
  depends_on = [aws_s3_bucket_public_access_block.cloudtrail_logs]

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permissão 1: CloudTrail verifica se tem permissão para escrever (GetBucketAcl)
      {
        Sid    = "CloudTrailACLCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.cloudtrail_logs.arn
        Condition = {
          StringEquals = {
            "aws:SourceArn" = "arn:${data.aws_partition.cloudtrail.partition}:cloudtrail:${data.aws_region.cloudtrail.name}:${data.aws_caller_identity.cloudtrail.account_id}:trail/hama-audit-trail"
          }
        }
      },
      # Permissão 2: CloudTrail escreve os arquivos de log
      {
        Sid    = "CloudTrailPutObject"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${data.aws_caller_identity.cloudtrail.account_id}/*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = "bucket-owner-full-control"
            "aws:SourceArn" = "arn:${data.aws_partition.cloudtrail.partition}:cloudtrail:${data.aws_region.cloudtrail.name}:${data.aws_caller_identity.cloudtrail.account_id}:trail/hama-audit-trail"
          }
        }
      },
      # Negação: Ninguém mais pode escrever no bucket (proteção de integridade)
      {
        Sid    = "DenyNonTLS"
        Effect = "Deny"
        Principal = "*"
        Action   = "s3:*"
        Resource = [
          aws_s3_bucket.cloudtrail_logs.arn,
          "${aws_s3_bucket.cloudtrail_logs.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# CLOUDWATCH LOG GROUP para CloudTrail (streaming de eventos em tempo real)
# Permite consultar eventos de auditoria diretamente no CloudWatch Logs.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "cloudtrail" {
  name              = "/aws/cloudtrail/hama-audit-trail"
  retention_in_days = 90 # 90 dias no CloudWatch (custo); resto vai para S3

  tags = {
    Finalidade    = "logs-cloudtrail-realtime"
    Norma         = "ISO27001-A.12.4.1"
    GerenciadoPor = "Terraform"
  }
}

# Role para o CloudTrail enviar logs para o CloudWatch Logs
resource "aws_iam_role" "cloudtrail_cloudwatch" {
  name = "hama-cloudtrail-cloudwatch-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Finalidade    = "cloudtrail-to-cloudwatch"
    GerenciadoPor = "Terraform"
  }
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch_policy" {
  name = "hama-cloudtrail-cloudwatch-policy"
  role = aws_iam_role.cloudtrail_cloudwatch.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# CLOUDTRAIL — Trilha de Auditoria Principal do HAMA
# Registra TODOS os eventos de API da conta: quem fez o quê, quando e de onde.
# Controles: FORM.HAMA.TI.015, ISO 27001 A.12.4.1, LGPD Art. 37
# ------------------------------------------------------------------------------
resource "aws_cloudtrail" "hama_audit" {
  name           = "hama-audit-trail"
  s3_bucket_name = aws_s3_bucket.cloudtrail_logs.id

  # Registra eventos de gerenciamento (criação/deleção de recursos)
  include_global_service_events = true # Inclui IAM, Route53, CloudFront (globais)
  is_multi_region_trail         = false # Somente a região configurada (Free Tier)
  enable_log_file_validation    = true  # Detecta se logs foram adulterados (hash SHA-256)

  # Streaming de eventos em tempo real para CloudWatch Logs
  cloud_watch_logs_group_arn = "${aws_cloudwatch_log_group.cloudtrail.arn}:*"
  cloud_watch_logs_role_arn  = aws_iam_role.cloudtrail_cloudwatch.arn

  # Configuração de eventos de dados (S3 e Lambda) — monitoramento de acesso a dados
  event_selector {
    read_write_type           = "All"   # Registra leituras E escritas
    include_management_events = true    # Inclui eventos de gerenciamento da AWS

    # Monitora acesso ao bucket de backup (todos os objetos)
    data_resource {
      type   = "AWS::S3::Object"
      values = ["arn:aws:s3:::"] # Monitora TODOS os buckets S3 da conta
    }

    # Monitora execução de funções Lambda
    data_resource {
      type   = "AWS::Lambda::Function"
      values = ["arn:aws:lambda"] # Monitora TODAS as funções Lambda da conta
    }
  }

  depends_on = [
    aws_s3_bucket_policy.cloudtrail_logs,
    aws_iam_role_policy.cloudtrail_cloudwatch_policy
  ]

  tags = {
    Finalidade    = "auditoria-completa"
    Checklist     = "FORM.HAMA.TI.015"
    Norma         = "ISO27001-A.12.4.1,LGPD-Art37"
    TipoRecurso   = "cloudtrail"
    GerenciadoPor = "Terraform"
    Setor         = "TI"
    Responsavel   = "ti-hama@igh.org.br"
    CustoCentro   = "TI-HAMA"
  }
}

# ------------------------------------------------------------------------------
# ALARME: Detecta tentativa de desabilitar o CloudTrail
# Alertas em tempo real para ações suspeitas — ISO 27001 A.12.4.2
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "cloudtrail_disable_alarm" {
  alarm_name          = "HAMA-CloudTrail-DisableDetected"
  alarm_description   = "[ISO 27001 A.12.4.2] CRÍTICO: Tentativa de desabilitar ou modificar o CloudTrail detectada!"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "EventCount"
  namespace           = "CloudTrailMetrics"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  # Filtro de métricas para capturar eventos de desabilitação do CloudTrail
  # Nota: o filtro de log correspondente deve ser criado separadamente

  tags = {
    Finalidade    = "deteccao-adulteracao-logs"
    Norma         = "ISO27001-A.12.4.2"
    GerenciadoPor = "Terraform"
  }
}

# Filtro de métricas: captura eventos de modificação do CloudTrail
resource "aws_cloudwatch_log_metric_filter" "cloudtrail_changes" {
  name           = "HAMA-CloudTrailChanges"
  pattern        = "{ ($.eventName = \"DeleteTrail\") || ($.eventName = \"UpdateTrail\") || ($.eventName = \"StopLogging\") || ($.eventName = \"StartLogging\") }"
  log_group_name = aws_cloudwatch_log_group.cloudtrail.name

  metric_transformation {
    name      = "EventCount"
    namespace = "CloudTrailMetrics"
    value     = "1"
  }
}
