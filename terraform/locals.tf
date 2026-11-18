locals {
  cluster_name  = "${var.name_prefix}-k8s"
  database_name = "encontros_tech"
  db_name       = "${var.name_prefix}-pg"
  vpc_name      = "${var.name_prefix}-vpc"

  tags = ["encontros-tech", "homologacao", "terraform"]
}
