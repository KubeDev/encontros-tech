mock_provider "digitalocean" {
  mock_resource "digitalocean_kubernetes_cluster" {
    defaults = {
      id = "00000000-0000-0000-0000-000000000000"
      kube_config = [{
        raw_config = "apiVersion: v1\nkind: Config\n"
      }]
    }
  }

  mock_resource "digitalocean_vpc" {
    defaults = {
      id = "11111111-1111-1111-1111-111111111111"
    }
  }
}

mock_provider "local" {}

variables {
  do_token = "token-de-teste"
}

run "vpc_dedicada_com_range_da_digitalocean" {
  command = plan

  assert {
    condition     = digitalocean_vpc.main.name == "encontros-tech-hml-vpc"
    error_message = "A VPC deve usar o prefixo do projeto."
  }

  assert {
    condition     = digitalocean_vpc.main.region == "nyc1"
    error_message = "A VPC deve ficar na região padrão nyc1."
  }
}

run "cluster_enxuto_sem_ha" {
  command = apply

  assert {
    condition     = digitalocean_kubernetes_cluster.main.ha == false
    error_message = "O control plane não pode ter HA (ADR 009)."
  }

  assert {
    condition     = digitalocean_kubernetes_cluster.main.version == "1.37.2-do.0"
    error_message = "A versão inicial do Kubernetes deve ser 1.37.2-do.0."
  }

  assert {
    condition     = digitalocean_kubernetes_cluster.main.auto_upgrade && digitalocean_kubernetes_cluster.main.surge_upgrade
    error_message = "Patch automático e surge upgrade devem estar ligados."
  }

  assert {
    condition     = digitalocean_kubernetes_cluster.main.destroy_all_associated_resources
    error_message = "O destroy precisa levar junto o Load Balancer criado pelo Service (ADR 008)."
  }

  assert {
    condition     = digitalocean_kubernetes_cluster.main.vpc_uuid == digitalocean_vpc.main.id
    error_message = "O cluster deve ficar na VPC dedicada."
  }

  assert {
    condition     = length(digitalocean_kubernetes_cluster.main.control_plane_firewall) == 0
    error_message = "A API do cluster fica sem control_plane_firewall (ADR 007)."
  }

  assert {
    condition = (
      digitalocean_kubernetes_cluster.main.node_pool[0].node_count == 2 &&
      digitalocean_kubernetes_cluster.main.node_pool[0].size == "s-1vcpu-2gb" &&
      digitalocean_kubernetes_cluster.main.node_pool[0].auto_scale == false
    )
    error_message = "O node pool deve ter 2 nós s-1vcpu-2gb sem autoscaling (ADR 009)."
  }
}

run "banco_minimo_na_vpc" {
  command = apply

  assert {
    condition = (
      digitalocean_database_cluster.main.engine == "pg" &&
      digitalocean_database_cluster.main.version == "18" &&
      digitalocean_database_cluster.main.size == "db-amd-1vcpu-1gb" &&
      digitalocean_database_cluster.main.node_count == 1
    )
    error_message = "O banco deve ser PostgreSQL 18, db-amd-1vcpu-1gb, 1 nó (ADR 009)."
  }

  assert {
    condition     = digitalocean_database_cluster.main.private_network_uuid == digitalocean_vpc.main.id
    error_message = "O banco deve ficar na VPC dedicada (ADR 007)."
  }

  assert {
    condition     = digitalocean_database_db.app.name == "encontros_tech"
    error_message = "O banco da aplicação deve se chamar encontros_tech."
  }
}

run "kubeconfig_local_protegido" {
  command = apply

  assert {
    condition     = local_sensitive_file.kubeconfig.file_permission == "0600"
    error_message = "O kubeconfig deve ser legível só pelo dono."
  }

  assert {
    condition     = endswith(local_sensitive_file.kubeconfig.filename, "/kubeconfig")
    error_message = "O kubeconfig deve ser gravado em terraform/kubeconfig."
  }
}

run "rejeita_menos_de_dois_nos" {
  command = plan

  variables {
    node_count = 1
  }

  expect_failures = [var.node_count]
}
