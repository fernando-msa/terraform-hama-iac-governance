# ==============================================================================
# modules/monitoring/main.tf
# Módulo orquestrador de monitoramento — une alarmes e Lambda de Wi-Fi.
# ==============================================================================

module "cloudwatch_alarms" {
  source = "./cloudwatch-alarms"

  # Não é um módulo isolado, os recursos estão definidos diretamente no arquivo .tf
  # Este arquivo serve como ponto de entrada para variáveis compartilhadas
}

# As variáveis e outputs do módulo monitoring estão definidos
# em cloudwatch-alarms.tf e lambda-wifi-check/main.tf
# O módulo raiz (main.tf) referencia este módulo via:
#   module "monitoring" { source = "./modules/monitoring" }
# e acessa:
#   module.monitoring.cloudwatch_alarm_arn
#   module.monitoring.lambda_wifi_check_arn
#   module.monitoring.sns_topic_arn
