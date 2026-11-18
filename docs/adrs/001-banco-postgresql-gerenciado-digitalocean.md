---
adr_number: "001"
status: aceito
created: 2026-11-16
supersedes: ""
superseded_by: ""
---

# ADR 001: Banco PostgreSQL gerenciado na DigitalOcean, fora do cluster

## Contexto

A aplicação hoje roda num servidor com systemd e depende de um PostgreSQL acessado via
`DATABASE_URL`. Com a migração para contêineres e Kubernetes, o banco precisa de um lugar:
dentro do cluster, junto da aplicação, ou fora dele como serviço gerenciado. Banco é o
componente com estado do sistema — backup, alta disponibilidade e upgrade de versão são o
custo operacional dominante.

## Alternativas Consideradas

- **PostgreSQL dentro do cluster (StatefulSet ou operator)** — tudo num lugar só e sem custo
  de serviço gerenciado; em troca, a equipe assume backup, failover, volume persistente e
  upgrade de versão do banco.
- **PostgreSQL gerenciado na DigitalOcean (DBaaS)** — backup, HA e upgrade ficam com o
  provedor; em troca, há limite de conexões por plano, uma dependência de rede para fora do
  cluster e custo do serviço.

## Decisão

Usar o PostgreSQL gerenciado da DigitalOcean, fora do cluster Kubernetes. O cluster fica sem
estado (stateless); o banco é uma dependência externa acessada por `DATABASE_URL`, mantida num
Secret. O que pesou: tirar a operação do dado de dentro do cluster.

## Consequências

- **Positivas:** os manifestos Kubernetes não têm StatefulSet, PVC nem rotina de backup;
  pods da aplicação podem ser destruídos e recriados livremente.
- **Negativas:** o número de conexões é limitado pelo plano (1 GiB = 22 conexões, segundo a
  [doc de Limits da DigitalOcean](https://docs.digitalocean.com/products/databases/postgresql/details/limits/),
  consultada em 2026-11-16) — isso restringe réplicas e workers (ver ADR 005). Não há acesso
  `superuser`.
- **Neutras / trade-offs aceitos:** a conexão usa TLS (`sslmode=require`, padrão da
  DigitalOcean) e a porta vem dos dados de conexão do cluster, não de uma porta fixa. O
  ambiente local (compose) usa um PostgreSQL próprio em contêiner, da mesma versão major que o
  gerenciado (18 é o padrão para clusters novos *(premissa — confirme a versão do seu
  cluster)*), porque não depende do banco gerenciado.
