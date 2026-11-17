---
adr_number: "008"
status: aceito
created: 2026-11-17
supersedes: ""
superseded_by: ""
---

# ADR 008: Infraestrutura em Terraform, com estado local e aplicação manual

## Contexto

A infraestrutura da homologação (VPC, cluster DOKS, banco gerenciado) precisa ser criada de
forma reproduzível, inclusive para recriar tudo numa região diferente (ADR 007). Há um único
operador, e o ambiente não é de produção. A aplicação dentro do cluster já é entregue por
manifestos YAML aplicados com `kubectl` (ADR 002).

## Alternativas Consideradas

- **Painel da DigitalOcean ou `doctl` à mão** — sem ferramenta nova; em troca, nada é
  reproduzível nem revisável, e recriar em outra região é refazer cliques.
- **Terraform com estado remoto (bucket Spaces) e/ou aplicação via CI** — estado compartilhado,
  com histórico e protegido contra perda; em troca, exige bucket, credenciais de CI e pipeline.
- **Terraform com estado local, aplicado manualmente pelo operador** — mínimo de peças; em
  troca, o estado vive numa máquina só.

## Decisão

Usar **Terraform** (≥ 1.17, provider `digitalocean` ~> 2.108) **[Verificado — registry.terraform.io
e checkpoint-api.hashicorp.com, 2026-11-17: Terraform 1.17.2, provider 2.108.0]**, com o
**estado local** na máquina do responsável e `terraform apply` executado **manualmente**. O
backup do estado é responsabilidade do operador e fica fora do escopo do projeto.

Fronteira de responsabilidade: o Terraform cria os recursos da DigitalOcean (VPC, cluster,
banco); o `kubectl` aplica a aplicação no cluster (ADR 002). A `DATABASE_URL` sai de um output
do Terraform (`private_uri`) e é colocada **manualmente** no Secret do Kubernetes.

## Consequências

- **Positivas:** infraestrutura descrita em código, revisável e recriável; região e versão do
  Kubernetes como variáveis; sem bucket nem pipeline para manter.
- **Negativas:** o estado contém segredos em texto puro (senha do banco, URIs de conexão,
  kubeconfig) — o arquivo de estado e os `*.tfvars` **nunca** são commitados (`.gitignore`).
  Sem trava de concorrência: só um operador aplica por vez. Perder o estado deixa os recursos
  órfãos, ainda cobrando, recuperáveis só por `terraform import`.
- **Neutras / trade-offs aceitos:** o Load Balancer é criado pelo Service, não pelo Terraform;
  por isso o cluster usa `destroy_all_associated_resources = true`, para que um `destroy` não
  deixe o Load Balancer órfão **[Verificado — docs do provider `digitalocean_kubernetes_cluster`,
  via Context7, 2026-11-17]**. Copiar a `DATABASE_URL` para o Secret é um passo manual que pode
  sair de sincronia se o banco for recriado *(premissa — confirme ou corrija)*. Ter mais
  operadores ou um ambiente de produção pede ADR novo, com estado remoto.
