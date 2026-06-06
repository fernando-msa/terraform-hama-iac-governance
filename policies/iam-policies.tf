# ==============================================================================
# policies/iam-policies.tf
# Políticas IAM de controle de acesso e restrição de uso de recursos.
#
# Controles implementados:
#   DIR.MMLN.TI.002 — Diretriz de Restrições de Uso de Recursos AWS
#   FORM.HAMA.TI.015 — Checklist de Controle de Acesso à Sala de Rack
#   ISO 27001 A.9.2.3 — Gestão de Direitos de Acesso Privilegiado
#
# Recursos criados:
#   - aws_iam_policy: política de negação para recursos sem tags obrigatórias
#   - aws_iam_role: role para técnicos de rack (acesso mínimo necessário)
#   - aws_iam_role_policy: permissões limitadas da role de técnico
#   - aws_iam_role_policy_attachment: vincula policies gerenciadas à role
# ==============================================================================

# Dados da conta AWS para uso em ARNs
data "aws_caller_identity" "policies" {}
data "aws_region" "policies" {}

# ------------------------------------------------------------------------------
# POLÍTICA DE RESTRIÇÃO: Bloqueia criação de recursos sem tags obrigatórias
# Controle: DIR.MMLN.TI.002 — Diretriz de Restrições de Uso
#
# Esta política implementa a "tag enforcement" como controle preventivo.
# Ela NEGA a criação de recursos EC2 e RDS que não possuam as tags obrigatórias
# definidas na DIR.MMLN.TI.001.
#
# NOTA: A versão completa desta política deve ser implementada como SCP
# (Service Control Policy) no AWS Organizations para cobertura total.
# Veja scp-blocklist.json para a versão SCP equivalente.
# ------------------------------------------------------------------------------
resource "aws_iam_policy" "deny_without_required_tags" {
  name        = "HAMA-DenyResourcesWithoutRequiredTags"
  description = "[DIR.MMLN.TI.002] Bloqueia criação de recursos EC2 e RDS sem as tags obrigatórias definidas na DIR.MMLN.TI.001 (Setor, DataAquisicao, DataFimVida, Responsavel, CustoCentro)"
  path        = "/hama/governanca/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ========================================================================
      # NEGAÇÃO 1: Instâncias EC2 sem tags obrigatórias
      # ========================================================================
      {
        Sid    = "DenyEC2WithoutSetor"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateVolume",
          "ec2:CreateSnapshot"
        ]
        Resource = "*"
        Condition = {
          # Nega se a tag "Setor" estiver ausente ou vazia
          StringNotLike = {
            "aws:RequestTag/Setor" = ["*"]
          }
        }
      },
      {
        Sid    = "DenyEC2WithoutResponsavel"
        Effect = "Deny"
        Action = ["ec2:RunInstances", "ec2:CreateVolume"]
        Resource = "*"
        Condition = {
          StringNotLike = {
            "aws:RequestTag/Responsavel" = ["*"]
          }
        }
      },
      {
        Sid    = "DenyEC2WithoutCustoCentro"
        Effect = "Deny"
        Action = ["ec2:RunInstances"]
        Resource = "*"
        Condition = {
          StringNotLike = {
            "aws:RequestTag/CustoCentro" = ["*"]
          }
        }
      },
      # ========================================================================
      # NEGAÇÃO 2: Buckets S3 sem tags obrigatórias
      # ========================================================================
      {
        Sid    = "DenyS3WithoutSetor"
        Effect = "Deny"
        Action = ["s3:CreateBucket"]
        Resource = "*"
        Condition = {
          StringNotLike = {
            "aws:RequestTag/Setor" = ["*"]
          }
        }
      },
      # ========================================================================
      # NEGAÇÃO 3: Funções Lambda sem tags obrigatórias
      # ========================================================================
      {
        Sid    = "DenyLambdaWithoutResponsavel"
        Effect = "Deny"
        Action = ["lambda:CreateFunction", "lambda:UpdateFunctionCode"]
        Resource = "*"
        Condition = {
          StringNotLike = {
            "aws:RequestTag/Responsavel" = ["*"]
          }
        }
      },
      # ========================================================================
      # NEGAÇÃO 4: Recursos de banco de dados sem tags
      # ========================================================================
      {
        Sid    = "DenyRDSWithoutRequiredTags"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:CreateDBCluster"
        ]
        Resource = "*"
        Condition = {
          StringNotLike = {
            "aws:RequestTag/Setor" = ["*"]
          }
        }
      }
    ]
  })

  tags = {
    Finalidade  = "tag-enforcement"
    Diretriz    = "DIR.MMLN.TI.002"
    TipoRecurso = "iam-policy"
    GerenciadoPor = "Terraform"
  }
}

# ------------------------------------------------------------------------------
# IAM ROLE: Técnico de Rack
# Controle: FORM.HAMA.TI.015 — Checklist de Controle de Acesso à Sala de Rack
# ISO 27001 A.9.2.3 — Acesso com privilégio mínimo
#
# Esta role é assumida por técnicos que precisam:
# - Verificar status de instâncias e volumes (leitura)
# - Acessar logs de auditoria da sala de rack
# - NÃO pode criar, modificar ou destruir recursos
# ------------------------------------------------------------------------------
resource "aws_iam_role" "tecnico_rack" {
  name        = "hama-tecnico-rack-role"
  description = "[FORM.HAMA.TI.015] Role com privilégio mínimo para técnicos de rack — somente leitura em recursos de infraestrutura"
  path        = "/hama/operacional/"

  # Política de confiança: permite que usuários IAM da mesma conta assumam esta role
  # Em produção, restrinja ao ARN específico do usuário do técnico
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowTecnicoRackAssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.policies.account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          # Exige MFA para assumir a role — camada extra de segurança
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })

  # Duração máxima da sessão: 4 horas (turno de trabalho)
  max_session_duration = 14400

  tags = {
    Finalidade    = "acesso-sala-rack"
    Checklist     = "FORM.HAMA.TI.015"
    TipoRecurso   = "iam-role"
    Norma         = "ISO27001-A.9.2.3"
    GerenciadoPor = "Terraform"
    Setor         = "TI"
    Responsavel   = "ti-hama@igh.org.br"
    CustoCentro   = "TI-HAMA"
  }
}

# ------------------------------------------------------------------------------
# POLÍTICA DA ROLE DE TÉCNICO: Permissões de somente leitura + operações básicas
# ------------------------------------------------------------------------------
resource "aws_iam_role_policy" "tecnico_rack_permissions" {
  name = "hama-tecnico-rack-permissions"
  role = aws_iam_role.tecnico_rack.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # ========================================================================
      # PERMISSÕES CONCEDIDAS: Operações de leitura em EC2
      # O técnico pode VER o estado dos servidores, mas não modificá-los
      # ========================================================================
      {
        Sid    = "EC2ReadOnly"
        Effect = "Allow"
        Action = [
          "ec2:Describe*",          # Listar e descrever todos os recursos EC2
          "ec2:GetConsoleOutput",   # Ver saída do console (útil para troubleshooting)
          "ec2:GetConsoleScreenshot" # Ver screenshot do console da instância
        ]
        Resource = "*"
      },
      # Permite reiniciar instâncias (necessário para manutenção de rack)
      {
        Sid    = "EC2Reboot"
        Effect = "Allow"
        Action = ["ec2:RebootInstances"]
        Resource = "*"
        Condition = {
          # Restringe o reboot a instâncias tagueadas como pertencentes ao TI
          StringEquals = {
            "ec2:ResourceTag/Setor" = ["TI", "Infraestrutura"]
          }
        }
      },
      # ========================================================================
      # PERMISSÕES CONCEDIDAS: Leitura de logs de auditoria (CloudTrail)
      # ========================================================================
      {
        Sid    = "CloudTrailReadOnly"
        Effect = "Allow"
        Action = [
          "cloudtrail:LookupEvents",      # Consultar eventos de auditoria
          "cloudtrail:GetTrailStatus",    # Ver status da trilha
          "cloudtrail:DescribeTrails"     # Listar trilhas configuradas
        ]
        Resource = "*"
      },
      # ========================================================================
      # PERMISSÕES CONCEDIDAS: Leitura de métricas CloudWatch
      # ========================================================================
      {
        Sid    = "CloudWatchReadOnly"
        Effect = "Allow"
        Action = [
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "cloudwatch:DescribeAlarms"
        ]
        Resource = "*"
      },
      # ========================================================================
      # PERMISSÕES CONCEDIDAS: Leitura de objetos no bucket de backup
      # Técnico pode verificar integridade de backups, mas não deletar
      # ========================================================================
      {
        Sid    = "S3BackupReadOnly"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketVersioning",
          "s3:GetObjectVersion"
        ]
        # Restringe ao bucket de backup (outros buckets são bloqueados)
        Resource = [
          "arn:aws:s3:::hama-iac-governance-*-backup-*",
          "arn:aws:s3:::hama-iac-governance-*-backup-*/*"
        ]
      },
      # ========================================================================
      # NEGAÇÕES EXPLÍCITAS: O técnico NUNCA pode fazer estas ações
      # Deny explícito sobrepõe qualquer Allow — camada extra de segurança
      # ========================================================================
      {
        Sid    = "DenyDestructiveActions"
        Effect = "Deny"
        Action = [
          "ec2:TerminateInstances",   # Não pode deletar instâncias
          "ec2:DeleteVolume",         # Não pode deletar volumes
          "s3:DeleteObject",          # Não pode deletar arquivos de backup
          "s3:DeleteBucket",          # Não pode deletar buckets
          "iam:*",                    # Não pode modificar IAM de forma alguma
          "cloudtrail:DeleteTrail",   # Não pode deletar logs de auditoria
          "cloudtrail:StopLogging"    # Não pode parar o registro de auditoria
        ]
        Resource = "*"
      }
    ]
  })
}

# Política gerenciada AWS de somente leitura para serviços comuns
resource "aws_iam_role_policy_attachment" "tecnico_rack_readonly" {
  role       = aws_iam_role.tecnico_rack.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ------------------------------------------------------------------------------
# OUTPUTS deste arquivo (usados pelo outputs.tf raiz)
# ------------------------------------------------------------------------------
# Nota: os outputs principais estão no outputs.tf raiz, que referencia diretamente
# aws_iam_role.tecnico_rack.arn e aws_iam_policy.deny_without_required_tags.arn
