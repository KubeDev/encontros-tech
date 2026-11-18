# VPC dedicada; o range de IPs é alocado pela DigitalOcean (ADR 007).
resource "digitalocean_vpc" "main" {
  name   = local.vpc_name
  region = var.region
}

resource "digitalocean_kubernetes_cluster" "main" {
  name     = local.cluster_name
  region   = var.region
  version  = var.kubernetes_version
  vpc_uuid = digitalocean_vpc.main.id

  # O padrão é true a partir da 1.36 e não pode ser desligado depois (ADR 009).
  ha = false

  auto_upgrade  = true
  surge_upgrade = true

  # O Load Balancer é criado pelo Service; sem isto um destroy deixaria o LB órfão (ADR 008).
  destroy_all_associated_resources = true

  tags = local.tags

  node_pool {
    name       = "default"
    size       = var.node_size
    node_count = var.node_count
    auto_scale = false
    tags       = local.tags
  }
}

# Banco sem trusted sources: aceita conexão de qualquer origem, risco aceito (ADR 007).
resource "digitalocean_database_cluster" "main" {
  name                 = local.db_name
  engine               = "pg"
  version              = var.database_version
  size                 = var.database_size
  region               = var.region
  node_count           = 1
  private_network_uuid = digitalocean_vpc.main.id
  tags                 = local.tags
}

resource "digitalocean_database_db" "app" {
  cluster_id = digitalocean_database_cluster.main.id
  name       = local.database_name
}

resource "local_sensitive_file" "kubeconfig" {
  content         = digitalocean_kubernetes_cluster.main.kube_config[0].raw_config
  filename        = "${path.module}/kubeconfig"
  file_permission = "0600"
}
