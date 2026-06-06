# ==============================================================================
# modules/monitoring/cloudwatch-alarms.tf
# Provisiona alarmes CloudWatch para monitoramento de SLA de chamados.
# Controle: POP.HAMA.TI.005 — Procedimento de SLA e Gestão de Chamados
#
# Recursos criados:
#   - aws_sns_topic: canal de notificação de alertas
#   - aws_sns_topic_subscription: assinatura por e-mail
#   - aws_cloudwatch_metric_alarm: alarme de tempo de resposta de chamado
#   - aws_cloudwatch_dashboard: painel de visualização de SLA
# ==============================================================================

# Variáveis do módulo
variable "project_name" {
  description = "Nome do projeto para composição de nomes"
  type        = string
}

variable "environment" {
  description = "Ambiente de implantação"
  type        = string
}

variable "sla_threshold_minutes" {
  description = "[POP.HAMA.TI.005] Limiar de SLA em minutos para disparo de alarme"
  type        = number
}

variable "alert_email" {
  description = "E-mail para receber alertas de violação de SLA"
  type        = string
}

variable "account_id" {
  description = "ID da conta AWS"
  type        = string
}

variable "region" {
  description = "Região AWS"
  type        = string
}

variable "suffix" {
  description = "Sufixo aleatório para unicidade de nomes"
  type        = string
}

variable "tags" {
  description = "Tags obrigatórias"
  type        = map(string)
  default     = {}
}

# ------------------------------------------------------------------------------
# TÓPICO SNS — Canal de alertas de SLA
# Centraliza notificações de todos os alarmes do módulo.
# ------------------------------------------------------------------------------
resource "aws_sns_topic" "hama_alerts" {
  name = "hama-alerts-${var.environment}"

  # Criptografa mensagens do SNS (LGPD — dados operacionais em trânsito)
  # kms_master_key_id = "alias/aws/sns"  # Descomente para criptografia (KMS tem custo)

  tags = merge(var.tags, {
    Finalidade  = "alertas-sla"
    POP         = "POP.HAMA.TI.005"
    TipoRecurso = "notificacao"
  })
}

# ------------------------------------------------------------------------------
# ASSINATURA SNS POR E-MAIL
# ATENÇÃO: Após terraform apply, confirme a assinatura clicando no link recebido.
# ------------------------------------------------------------------------------
resource "aws_sns_topic_subscription" "email_alert" {
  topic_arn = aws_sns_topic.hama_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ------------------------------------------------------------------------------
# ALARME DE SLA — POP.HAMA.TI.005
# Monitora a métrica customizada "TicketResponseTime" no namespace "HAMA/Helpdesk".
# A métrica é publicada pela Lambda de verificação ou manualmente via AWS CLI.
#
# Como testar manualmente (para demonstração):
#   aws cloudwatch put-metric-data \
#     --namespace "HAMA/Helpdesk" \
#     --metric-name "TicketResponseTime" \
#     --value 300 \
#     --unit "Minutes" \
#     --dimensions Environment=producao
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "sla_ticket_response" {
  alarm_name          = "HAMA-SLA-TicketResponseTime"
  alarm_description   = "[POP.HAMA.TI.005] Alarme disparado quando o tempo médio de resposta de chamados ultrapassa o SLA configurado (${var.sla_threshold_minutes} minutos)"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1       # Número de períodos a avaliar antes de disparar
  metric_name         = "TicketResponseTime"
  namespace           = "HAMA/Helpdesk" # Namespace customizado para métricas do hospital
  period              = 300     # Período de avaliação: 5 minutos (300 segundos)
  statistic           = "Average"
  threshold           = var.sla_threshold_minutes

  # Ação quando o alarme estiver no estado ALARM (SLA violado)
  alarm_actions = [aws_sns_topic.hama_alerts.arn]

  # Ação quando o alarme retornar ao estado OK (SLA restaurado)
  ok_actions = [aws_sns_topic.hama_alerts.arn]

  # Ação quando não há dados suficientes (possível problema no sistema de chamados)
  insufficient_data_actions = [aws_sns_topic.hama_alerts.arn]

  # Tratar ausência de dados como violação de SLA (mais seguro para monitoramento)
  treat_missing_data = "breaching"

  dimensions = {
    Environment = var.environment
  }

  tags = merge(var.tags, {
    Finalidade  = "monitoramento-sla"
    POP         = "POP.HAMA.TI.005"
    TipoRecurso = "alarme-cloudwatch"
  })
}

# ------------------------------------------------------------------------------
# ALARME SECUNDÁRIO: Chamados sem atendimento em período crítico
# Simula o controle de chamados P1 (urgência máxima) — SLA = 60 minutos
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_metric_alarm" "sla_critico_p1" {
  alarm_name          = "HAMA-SLA-CriticoP1-TicketResponseTime"
  alarm_description   = "[POP.HAMA.TI.005] Chamado P1 (crítico) sem atendimento em 60 minutos — SLA VIOLADO"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "TicketResponseTime"
  namespace           = "HAMA/Helpdesk"
  period              = 300
  statistic           = "Maximum" # Usa máximo para capturar casos extremos
  threshold           = 60        # 60 minutos = SLA P1

  alarm_actions      = [aws_sns_topic.hama_alerts.arn]
  treat_missing_data = "notBreaching" # P1 sem dados = não há chamados críticos abertos

  dimensions = {
    Environment = var.environment
    Priority    = "P1"
  }

  tags = merge(var.tags, {
    Finalidade  = "monitoramento-sla-critico"
    POP         = "POP.HAMA.TI.005"
    TipoRecurso = "alarme-cloudwatch"
  })
}

# ------------------------------------------------------------------------------
# DASHBOARD CLOUDWATCH — Painel de visibilidade de SLA
# Centraliza métricas de SLA em um painel visual acessível no console AWS.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_dashboard" "hama_sla" {
  dashboard_name = "HAMA-SLA-Dashboard"

  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric"
        x    = 0
        y    = 0
        width  = 12
        height = 6
        properties = {
          title  = "[POP.HAMA.TI.005] Tempo de Resposta de Chamados (minutos)"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["HAMA/Helpdesk", "TicketResponseTime", "Environment", var.environment,
              { label = "Tempo Médio de Resposta", stat = "Average", color = "#2196F3" }
            ],
            ["HAMA/Helpdesk", "TicketResponseTime", "Environment", var.environment,
              { label = "Tempo Máximo (P1)", stat = "Maximum", color = "#F44336" }
            ]
          ]
          annotations = {
            horizontal = [
              {
                label = "Limite SLA P2 (${var.sla_threshold_minutes}min)"
                value = var.sla_threshold_minutes
                color = "#FF9800"
              },
              {
                label = "Limite SLA P1 (60min)"
                value = 60
                color = "#F44336"
              }
            ]
          }
          yAxis = {
            left = { min = 0, label = "Minutos" }
          }
        }
      },
      {
        type = "alarm"
        x    = 12
        y    = 0
        width  = 12
        height = 6
        properties = {
          title = "Status dos Alarmes de SLA"
          alarms = [
            "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:HAMA-SLA-TicketResponseTime",
            "arn:aws:cloudwatch:${var.region}:${var.account_id}:alarm:HAMA-SLA-CriticoP1-TicketResponseTime"
          ]
        }
      },
      {
        type = "metric"
        x    = 0
        y    = 6
        width  = 12
        height = 6
        properties = {
          title  = "[CHK.WIFI] Conectividade Wi-Fi (% disponível)"
          view   = "timeSeries"
          region = var.region
          metrics = [
            ["HAMA/WiFi", "ConnectivityScore", "Environment", var.environment,
              { label = "Score de Conectividade (%)", stat = "Average", color = "#4CAF50" }
            ]
          ]
          annotations = {
            horizontal = [
              { label = "Mínimo Aceitável (80%)", value = 80, color = "#FF9800" }
            ]
          }
        }
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# OUTPUTS DO MÓDULO DE MONITORAMENTO
# ------------------------------------------------------------------------------
output "cloudwatch_alarm_arn" {
  description = "ARN do alarme CloudWatch de SLA"
  value       = aws_cloudwatch_metric_alarm.sla_ticket_response.arn
}

output "sns_topic_arn" {
  description = "ARN do tópico SNS de alertas"
  value       = aws_sns_topic.hama_alerts.arn
}

output "dashboard_url" {
  description = "URL do dashboard CloudWatch de SLA"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home#dashboards:name=HAMA-SLA-Dashboard"
}
