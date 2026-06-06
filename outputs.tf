# ==============================================================================
# outputs.tf
# Expõe os valores mais importantes após o terraform apply.
# Útil para integração com pipelines CI/CD e referência cruzada entre módulos.
# ==============================================================================

# ------------------------------------------------------------------------------
# OUTPUTS DO MÓDULO DE TAGS
# ------------------------------------------------------------------------------

output "tags_obrigatorias" {
  description = "Mapa completo de tags obrigatórias aplicadas (DIR.MMLN.TI.001)"
  value       = module.tags.tags_completas
}

# ------------------------------------------------------------------------------
# OUTPUTS DO MÓDULO DE BACKUP
# ------------------------------------------------------------------------------

output "backup_bucket_name" {
  description = "Nome do bucket S3 de backup (POP.HAMA.TI.004)"
  value       = module.backup.bucket_name
}

output "backup_bucket_arn" {
  description = "ARN do bucket S3 de backup (POP.HAMA.TI.004)"
  value       = module.backup.bucket_arn
}

output "backup_bucket_region" {
  description = "Região do bucket S3 de backup"
  value       = module.backup.bucket_region
}

# ------------------------------------------------------------------------------
# OUTPUTS DO MÓDULO DE MONITORAMENTO
# ------------------------------------------------------------------------------

output "cloudwatch_alarm_arn" {
  description = "ARN do alarme CloudWatch de SLA (POP.HAMA.TI.005)"
  value       = module.monitoring.cloudwatch_alarm_arn
}

output "lambda_wifi_check_arn" {
  description = "ARN da função Lambda de verificação de Wi-Fi (CHK.HAMA.TI.WIFI)"
  value       = module.monitoring.lambda_wifi_check_arn
}

output "sns_topic_arn" {
  description = "ARN do tópico SNS de alertas de SLA"
  value       = module.monitoring.sns_topic_arn
}

# ------------------------------------------------------------------------------
# OUTPUTS DE POLÍTICAS E AUDITORIA
# ------------------------------------------------------------------------------

output "tecnico_rack_role_arn" {
  description = "ARN da IAM Role para técnico de rack (FORM.HAMA.TI.015)"
  value       = aws_iam_role.tecnico_rack.arn
}

output "cloudtrail_arn" {
  description = "ARN da trilha CloudTrail de auditoria (ISO 27001 A.12.4.1)"
  value       = aws_cloudtrail.hama_audit.arn
}

output "cloudtrail_log_bucket_name" {
  description = "Nome do bucket S3 que armazena os logs do CloudTrail"
  value       = aws_s3_bucket.cloudtrail_logs.id
}

# ------------------------------------------------------------------------------
# OUTPUTS DE INFORMAÇÕES DA CONTA
# ------------------------------------------------------------------------------

output "aws_account_id" {
  description = "ID da conta AWS utilizada"
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Região AWS onde os recursos foram provisionados"
  value       = data.aws_region.current.name
}

# ------------------------------------------------------------------------------
# OUTPUT RESUMIDO — útil para demonstrações e entrevistas
# ------------------------------------------------------------------------------

output "resumo_governanca" {
  description = "Resumo dos recursos de governança provisionados"
  value = {
    backup = {
      bucket      = module.backup.bucket_name
      retencao    = "${var.backup_retention_days} dias"
      versionamento = "habilitado"
    }
    monitoramento = {
      alarme_sla  = "HAMA-SLA-TicketResponseTime"
      limiar_sla  = "${var.sla_threshold_minutes} minutos"
      lambda_wifi = module.monitoring.lambda_wifi_check_arn
    }
    auditoria = {
      cloudtrail  = aws_cloudtrail.hama_audit.name
      retencao_logs = "${var.cloudtrail_retention_days} dias"
    }
    iam = {
      role_tecnico_rack = aws_iam_role.tecnico_rack.name
    }
    tags_aplicadas = length(local.tags_obrigatorias)
  }
}
