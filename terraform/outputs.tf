output "cluster_id" {
  description = "ID do cluster DOKS."
  value       = digitalocean_kubernetes_cluster.main.id
}

output "cluster_name" {
  description = "Nome do cluster DOKS."
  value       = digitalocean_kubernetes_cluster.main.name
}

output "database_host" {
  description = "Host público do banco, para acesso administrativo."
  value       = digitalocean_database_cluster.main.host
}

output "database_id" {
  description = "ID do cluster PostgreSQL gerenciado."
  value       = digitalocean_database_cluster.main.id
}

output "database_public_url" {
  description = "URL de conexão pelo host público, para acesso administrativo (psql)."
  value       = "postgresql://${digitalocean_database_cluster.main.user}:${digitalocean_database_cluster.main.password}@${digitalocean_database_cluster.main.host}:${digitalocean_database_cluster.main.port}/${digitalocean_database_db.app.name}?sslmode=require"
  sensitive   = true
}

output "database_url" {
  description = "DATABASE_URL da aplicação, pelo host privado da VPC. Vai para o Secret do Kubernetes (ADR 008)."
  value       = "postgresql://${digitalocean_database_cluster.main.user}:${digitalocean_database_cluster.main.password}@${digitalocean_database_cluster.main.private_host}:${digitalocean_database_cluster.main.port}/${digitalocean_database_db.app.name}?sslmode=require"
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Caminho do kubeconfig gerado. Uso: KUBECONFIG=<caminho> kubectl get nodes."
  value       = local_sensitive_file.kubeconfig.filename
}

output "vpc_id" {
  description = "ID da VPC dedicada."
  value       = digitalocean_vpc.main.id
}

output "vpc_ip_range" {
  description = "Range de IPs que a DigitalOcean alocou para a VPC."
  value       = digitalocean_vpc.main.ip_range
}
