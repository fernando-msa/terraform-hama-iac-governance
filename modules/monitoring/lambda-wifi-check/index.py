# ==============================================================================
# modules/monitoring/lambda-wifi-check/index.py
# Função Lambda que simula verificação de conectividade Wi-Fi.
# Checklist: CHK.HAMA.TI.WIFI — Checklist de Verificação de Rede Wi-Fi
#
# O que esta função faz:
#   1. Simula a verificação de múltiplos pontos de acesso (APs) Wi-Fi do hospital
#   2. Calcula um "score de conectividade" baseado nos APs respondendo
#   3. Publica a métrica no CloudWatch (namespace: HAMA/WiFi)
#   4. Retorna resultado detalhado em JSON para auditoria
#
# Em produção real, esta função seria integrada com:
#   - API de controlador Wi-Fi (ex: Cisco WLC, Ubiquiti UniFi)
#   - Verificações ICMP/HTTP contra IPs fixos dos APs
#   - Banco de dados de inventário de APs do HAMA
# ==============================================================================

import json
import os
import random
import socket
import boto3
from datetime import datetime, timezone

# Cliente CloudWatch para publicação de métricas
cloudwatch = boto3.client("cloudwatch")

# Configuração dos pontos de acesso simulados
# Em produção: carregar do SSM Parameter Store ou DynamoDB
ACCESS_POINTS = [
    {"id": "AP-TI-01",        "location": "Sala de TI",          "ip": "10.0.1.10"},
    {"id": "AP-UTI-01",       "location": "UTI Adulto",           "ip": "10.0.2.10"},
    {"id": "AP-UTI-02",       "location": "UTI Pediátrica",       "ip": "10.0.2.11"},
    {"id": "AP-RECEPCAO-01",  "location": "Recepção Principal",   "ip": "10.0.3.10"},
    {"id": "AP-FARMACIA-01",  "location": "Farmácia",             "ip": "10.0.4.10"},
    {"id": "AP-RADIOLOGIA-01","location": "Radiologia",           "ip": "10.0.5.10"},
    {"id": "AP-RACK-01",      "location": "Sala de Rack (teste)", "ip": "10.0.0.1"},
]

# Limiar de qualidade de conectividade (percentual de APs respondendo)
CONNECTIVITY_THRESHOLD_PERCENT = float(os.environ.get("CONNECTIVITY_THRESHOLD", "80.0"))
ENVIRONMENT = os.environ.get("ENVIRONMENT", "producao")
CLOUDWATCH_NAMESPACE = "HAMA/WiFi"


def check_ap_connectivity(ap: dict) -> dict:
    """
    Verifica a conectividade de um ponto de acesso Wi-Fi.
    
    Em ambiente de produção real: faz ping (ICMP) ou requisição HTTP.
    Em ambiente Lambda/simulado: usa probabilidade ponderada para simular
    falhas ocasionais (baseado em padrões reais de disponibilidade de APs).
    
    Retorna:
        dict com status, latência simulada e timestamp da verificação
    """
    # Simulação de conectividade com 90% de chance de sucesso por AP
    # Ajuste esta probabilidade para refletir a realidade do ambiente
    is_online = random.random() > 0.10

    # Latência simulada: entre 1ms e 50ms para APs online
    latency_ms = round(random.uniform(1.0, 50.0), 2) if is_online else None

    return {
        "ap_id":      ap["id"],
        "location":   ap["location"],
        "ip":         ap["ip"],
        "status":     "online" if is_online else "offline",
        "latency_ms": latency_ms,
        "checked_at": datetime.now(timezone.utc).isoformat(),
    }


def publish_metrics(connectivity_score: float, total_aps: int, online_aps: int) -> None:
    """
    Publica métricas de conectividade no CloudWatch.
    As métricas alimentam os alarmes configurados no cloudwatch-alarms.tf.
    """
    timestamp = datetime.now(timezone.utc)

    cloudwatch.put_metric_data(
        Namespace=CLOUDWATCH_NAMESPACE,
        MetricData=[
            # Score geral de conectividade (0-100%)
            {
                "MetricName": "ConnectivityScore",
                "Value":      connectivity_score,
                "Unit":       "Percent",
                "Timestamp":  timestamp,
                "Dimensions": [{"Name": "Environment", "Value": ENVIRONMENT}],
            },
            # Contagem de APs online
            {
                "MetricName": "AccessPointsOnline",
                "Value":      float(online_aps),
                "Unit":       "Count",
                "Timestamp":  timestamp,
                "Dimensions": [{"Name": "Environment", "Value": ENVIRONMENT}],
            },
            # Contagem de APs offline (para alertas de falha)
            {
                "MetricName": "AccessPointsOffline",
                "Value":      float(total_aps - online_aps),
                "Unit":       "Count",
                "Timestamp":  timestamp,
                "Dimensions": [{"Name": "Environment", "Value": ENVIRONMENT}],
            },
        ],
    )


def lambda_handler(event, context) -> dict:
    """
    Handler principal da Lambda — ponto de entrada da função.
    
    Pode ser invocado:
    - Automaticamente por EventBridge (a cada 5 minutos — ver main.tf)
    - Manualmente via console AWS para teste
    - Via API Gateway para integração com dashboard
    """
    print(f"[{datetime.now(timezone.utc).isoformat()}] Iniciando verificação de conectividade Wi-Fi — CHK.HAMA.TI.WIFI")

    # Verificar todos os pontos de acesso
    results = [check_ap_connectivity(ap) for ap in ACCESS_POINTS]

    # Calcular estatísticas de conectividade
    total_aps  = len(results)
    online_aps = sum(1 for r in results if r["status"] == "online")
    connectivity_score = (online_aps / total_aps) * 100 if total_aps > 0 else 0.0

    # Determinar status geral baseado no limiar configurado
    overall_status = "OK" if connectivity_score >= CONNECTIVITY_THRESHOLD_PERCENT else "DEGRADED"

    # Identificar APs offline para registro de auditoria
    offline_aps = [r for r in results if r["status"] == "offline"]

    # Log estruturado para CloudWatch Logs (facilita troubleshooting)
    print(json.dumps({
        "evento":              "wifi-check-completed",
        "total_aps":           total_aps,
        "online_aps":          online_aps,
        "offline_aps":         len(offline_aps),
        "connectivity_score":  round(connectivity_score, 2),
        "status_geral":        overall_status,
        "limiar_configurado":  CONNECTIVITY_THRESHOLD_PERCENT,
        "aps_offline":         [ap["ap_id"] for ap in offline_aps],
        "checklist_ref":       "CHK.HAMA.TI.WIFI",
    }))

    # Publicar métricas no CloudWatch
    publish_metrics(connectivity_score, total_aps, online_aps)

    # Resposta estruturada da função
    response_body = {
        "statusCode":         200,
        "checklist_ref":      "CHK.HAMA.TI.WIFI",
        "execution_time":     datetime.now(timezone.utc).isoformat(),
        "environment":        ENVIRONMENT,
        "summary": {
            "total_access_points":    total_aps,
            "online":                 online_aps,
            "offline":                len(offline_aps),
            "connectivity_score_pct": round(connectivity_score, 2),
            "overall_status":         overall_status,
            "threshold_pct":          CONNECTIVITY_THRESHOLD_PERCENT,
        },
        "access_points": results,
        "offline_details": offline_aps if offline_aps else [],
    }

    # Alerta no log se houver APs offline
    if offline_aps:
        print(f"⚠️  ATENÇÃO: {len(offline_aps)} AP(s) offline detectado(s): "
              f"{[ap['ap_id'] for ap in offline_aps]}")

    return response_body
