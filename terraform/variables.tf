variable "database_size" {
  description = "Slug do plano do PostgreSQL gerenciado (ADR 009)."
  type        = string
  default     = "db-amd-1vcpu-1gb"
}

variable "database_version" {
  description = "Versão major do PostgreSQL gerenciado (ADR 009)."
  type        = string
  default     = "18"
}

variable "do_token" {
  description = "Token da API da DigitalOcean, com escrita em VPC, Kubernetes e Databases."
  type        = string
  sensitive   = true
  nullable    = false

  validation {
    condition     = length(trimspace(var.do_token)) > 0
    error_message = "O do_token não pode ser vazio."
  }
}

variable "kubernetes_version" {
  description = "Versão do DOKS. Liste as opções com `doctl kubernetes options versions`."
  type        = string
  default     = "1.37.2-do.0"
}

variable "name_prefix" {
  description = "Prefixo dos nomes dos recursos na DigitalOcean."
  type        = string
  default     = "encontros-tech-hml"

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}[a-z0-9]$", var.name_prefix))
    error_message = "O name_prefix deve ter de 3 a 42 caracteres: letras minúsculas, números e hífens, sem hífen nas pontas."
  }
}

variable "node_count" {
  description = "Quantidade de nós do node pool, sem autoscaling (ADR 009)."
  type        = number
  default     = 2

  validation {
    condition     = var.node_count >= 2
    error_message = "O node pool precisa de pelo menos 2 nós para manter as 2 réplicas no ar (ADR 009)."
  }
}

variable "node_size" {
  description = "Slug do Droplet dos nós do cluster (ADR 009)."
  type        = string
  default     = "s-1vcpu-2gb"
}

variable "region" {
  description = "Região da DigitalOcean. Mudar depois recria VPC, cluster e banco (ADR 007)."
  type        = string
  default     = "nyc1"
}
