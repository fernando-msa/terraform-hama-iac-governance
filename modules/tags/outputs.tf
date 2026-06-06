# ==============================================================================
# modules/tags/outputs.tf
# Expõe o mapa de tags para consumo pelos outros módulos e pelo módulo raiz.
# ==============================================================================

output "tags_completas" {
  description = "Mapa completo de tags obrigatórias e de rastreabilidade"
  value       = local.tags_completas
}

output "tags_obrigatorias" {
  description = "Apenas as tags obrigatórias pela DIR.MMLN.TI.001"
  value       = local.tags_base
}

output "data_fim_vida" {
  description = "Data de fim de vida do ativo (para uso em lógica de ciclo de vida)"
  value       = var.data_fim_vida
}
