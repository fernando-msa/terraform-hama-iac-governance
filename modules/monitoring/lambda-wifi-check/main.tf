# ==============================================================================
# modules/monitoring/lambda-wifi-check/main.tf
# Provisiona a infraestrutura AWS para a função Lambda de verificação de Wi-Fi.
# Checklist: CHK.HAMA.TI.WIFI — Checklist de Verificação de Rede Wi-Fi
#
# Recursos criados:
#   - aws_iam_role: papel de execução da Lambda
#   - aws_iam_role_policy: permissões mínimas (least privilege)
#   - aws_lambda_function: a função em si
#   - aws_cloudwatch_log_group: grupo de logs com retenção definida
#   - aws_scheduler_schedule: execução automática a cada 5 minutos
# ==============================================================================

# Variáveis passadas pelo módulo monitoring
variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "account_id" {
  type = string
}

variable "suffix" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "connectivity_threshold" {
  description = "Percentual mínimo de APs online considerado saudável"
  type        = number
  default     = 80.0
}

# ------------------------------------------------------------------------------
# EMPACOTAMENTO DO CÓDIGO PYTHON
# O provider "archive" cria o ZIP necessário para fazer o deploy da Lambda.
# O arquivo index.py está no mesmo diretório que este main.tf.
# ------------------------------------------------------------------------------
data "archive_file" "wifi_check_lambda" {
  type        = "zip"
  source_file = "${path.module}/index.py"
  output_path = "${path.module}/wifi_check_lambda.zip"
}

# ------------------------------------------------------------------------------
# IAM ROLE DE EXECUÇÃO DA LAMBDA
# Segue o princípio de least privilege — apenas as permissões necessárias.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "lambda_wifi_check" {
  name = "hama-lambda-wifi-check-role-${var.environment}"

  # Política de confiança: permite que o serviço Lambda assuma esta role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(var.tags, {
    Finalidade  = "execucao-lambda-wifi"
    Checklist   = "CHK.HAMA.TI.WIFI"
    TipoRecurso = "iam-role"
  })
}

# ------------------------------------------------------------------------------
# POLÍTICA IAM: Permissões mínimas para a Lambda
# Princípio de least privilege — ISO 27001 A.9.4.1
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy" "lambda_wifi_check_policy" {
  name = "hama-lambda-wifi-check-policy"
  role = aws_iam_role.lambda_wifi_check.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # Permissão 1: Escrever logs no CloudWatch Logs
      {
        Sid    = "CloudWatchLogs"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:${var.region}:${var.account_id}:log-group:/aws/lambda/hama-wifi-connectivity-check:*"
      },
      # Permissão 2: Publicar métricas customizadas no CloudWatch
      {
        Sid    = "CloudWatchMetrics"
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData"
        ]
        # Restringe ao namespace específico do hospital
        Resource = "*"
        Condition = {
          StringEquals = {
            "cloudwatch:namespace" = "HAMA/WiFi"
          }
        }
      }
    ]
  })
}

# Política gerenciada da AWS para execução básica de Lambda (logs)
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_wifi_check.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ------------------------------------------------------------------------------
# GRUPO DE LOGS CLOUDWATCH
# Criado explicitamente para controlar a retenção de logs (30 dias).
# Sem este recurso, o grupo seria criado automaticamente com retenção indefinida.
# ------------------------------------------------------------------------------
resource "aws_cloudwatch_log_group" "wifi_check_logs" {
  name              = "/aws/lambda/hama-wifi-connectivity-check"
  retention_in_days = 30 # Retenção alinhada com o POP de backup (30 dias)

  tags = merge(var.tags, {
    Finalidade  = "logs-lambda-wifi"
    Checklist   = "CHK.HAMA.TI.WIFI"
    TipoRecurso = "cloudwatch-log-group"
  })
}

# ------------------------------------------------------------------------------
# FUNÇÃO LAMBDA — Verificação de Conectividade Wi-Fi
# Runtime Python 3.12 (versão LTS com suporte estendido)
# Memória: 128 MB (mínimo — suficiente para verificações de rede)
# Timeout: 30 segundos (cada AP tem até ~4 segundos de margem)
# ------------------------------------------------------------------------------
resource "aws_lambda_function" "wifi_check" {
  # Dependências que devem existir antes da Lambda
  depends_on = [
    aws_iam_role_policy_attachment.lambda_basic_execution,
    aws_cloudwatch_log_group.wifi_check_logs,
  ]

  function_name = "hama-wifi-connectivity-check"
  description   = "[CHK.HAMA.TI.WIFI] Verifica conectividade dos pontos de acesso Wi-Fi do hospital e publica métricas no CloudWatch"
  role          = aws_iam_role.lambda_wifi_check.arn
  handler       = "index.lambda_handler" # arquivo.função_handler
  runtime       = "python3.12"

  # Arquivo ZIP com o código da função
  filename         = data.archive_file.wifi_check_lambda.output_path
  source_code_hash = data.archive_file.wifi_check_lambda.output_base64sha256

  # Configurações de recursos (Free Tier: 1 milhão de invocações/mês)
  memory_size = 128  # MB
  timeout     = 30   # segundos

  # Variáveis de ambiente injetadas na função
  environment {
    variables = {
      ENVIRONMENT            = var.environment
      CONNECTIVITY_THRESHOLD = tostring(var.connectivity_threshold)
    }
  }

  tags = merge(var.tags, {
    Finalidade  = "verificacao-wifi"
    Checklist   = "CHK.HAMA.TI.WIFI"
    TipoRecurso = "lambda-function"
    Runtime     = "python3.12"
  })
}

# ------------------------------------------------------------------------------
# AGENDAMENTO: EventBridge Scheduler
# Executa a Lambda a cada 5 minutos para monitoramento contínuo.
# Free Tier: 14 milhões de invocações de scheduler por mês.
# ------------------------------------------------------------------------------
resource "aws_iam_role" "scheduler_role" {
  name = "hama-scheduler-wifi-check-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "scheduler.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "scheduler_invoke_lambda" {
  name = "hama-scheduler-invoke-lambda-policy"
  role = aws_iam_role.scheduler_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["lambda:InvokeFunction"]
        Resource = aws_lambda_function.wifi_check.arn
      }
    ]
  })
}

resource "aws_scheduler_schedule" "wifi_check_every_5min" {
  name        = "hama-wifi-check-schedule"
  description = "[CHK.HAMA.TI.WIFI] Executa verificação de Wi-Fi a cada 5 minutos"

  # Expressão cron: a cada 5 minutos
  flexible_time_window {
    mode = "OFF" # Executa exatamente no horário programado
  }

  schedule_expression = "rate(5 minutes)"

  target {
    arn      = aws_lambda_function.wifi_check.arn
    role_arn = aws_iam_role.scheduler_role.arn

    # Payload enviado para a Lambda a cada execução
    input = jsonencode({
      source    = "eventbridge-scheduler"
      checklist = "CHK.HAMA.TI.WIFI"
    })

    # Política de retry: tenta novamente 2x em caso de falha
    retry_policy {
      maximum_retry_attempts = 2
    }
  }
}

# Permissão para o EventBridge invocar a Lambda (necessária além da role)
resource "aws_lambda_permission" "allow_scheduler" {
  statement_id  = "AllowEventBridgeScheduler"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.wifi_check.function_name
  principal     = "scheduler.amazonaws.com"
  source_arn    = aws_scheduler_schedule.wifi_check_every_5min.arn
}

# ------------------------------------------------------------------------------
# OUTPUTS DO MÓDULO LAMBDA
# ------------------------------------------------------------------------------
output "lambda_wifi_check_arn" {
  description = "ARN da função Lambda de verificação de Wi-Fi"
  value       = aws_lambda_function.wifi_check.arn
}

output "lambda_wifi_check_name" {
  description = "Nome da função Lambda"
  value       = aws_lambda_function.wifi_check.function_name
}

output "log_group_name" {
  description = "Nome do grupo de logs CloudWatch da Lambda"
  value       = aws_cloudwatch_log_group.wifi_check_logs.name
}
