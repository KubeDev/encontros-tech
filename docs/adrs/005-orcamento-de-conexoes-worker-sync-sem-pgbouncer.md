---
adr_number: "005"
status: aceito
created: 2026-11-16
supersedes: ""
superseded_by: ""
---

# ADR 005: Orçamento de conexões com worker sync e sem PgBouncer

## Contexto

O PostgreSQL gerenciado da DigitalOcean (ADR 001) limita as conexões pela RAM do plano: 22 no
plano de 1 GiB, 47 no de 2 GiB, com 3 conexões já reservadas para manutenção
([Limits](https://docs.digitalocean.com/products/databases/postgresql/details/limits/) e
[Connection Pools](https://docs.digitalocean.com/products/databases/postgresql/how-to/manage-connection-pools/),
consultadas em 2026-11-16). Cada processo da aplicação tem seu próprio pool do SQLAlchemy, e o
pool não é configurável sem alterar código (ADR 004). Réplicas × workers × conexões por worker
precisa caber no limite do plano, inclusive durante o rolling update.

## Alternativas Consideradas

- **Conexão direta, com worker gunicorn sync e poucas réplicas** — o worker sync atende uma
  requisição por vez, então usa no máximo 1 conexão simultânea, apesar do pool padrão
  permitir 15; nenhum componente extra.
- **PgBouncer gerenciado da DigitalOcean (pool em modo transaction)** — desacopla conexões de
  cliente das conexões reais e permite escalar réplicas; adiciona um componente, outra
  connection string e restrições do modo transaction.
- **Plano de banco maior** — mais conexões, maior custo; não resolve o problema de
  multiplicação, só o adia.

## Decisão

Conexão direta ao banco, sem PgBouncer, com:

- plano de banco de 1 GiB (22 conexões) como ponto de partida;
- 2 réplicas da aplicação;
- gunicorn com 2 workers **sync** por pod (escalar com réplicas, não com workers).

Orçamento no pior caso: (2 réplicas + 1 pod extra no rollout) × 2 workers × 1 conexão = 6 de
22. A regra que vale daqui em diante:

> (réplicas + surge do rollout) × workers × conexões simultâneas por worker ≤ conexões do
> plano − folga administrativa

## Consequências

- **Positivas:** sobra folga ampla no plano mais barato; nenhum componente extra.
- **Negativas:** o tipo de worker passa a ser uma restrição. Trocar para `gthread`, `gevent`
  ou usar threads multiplica as conexões por worker (até 15 com o pool padrão) e pode estourar
  o limite.
- **Neutras / trade-offs aceitos:** o gatilho para revisar esta decisão é a regra acima não
  fechar — passar de cerca de 5 réplicas, adotar autoscaling ou trocar o tipo de worker. A
  revisão deve vir como ADR novo (PgBouncer ou plano maior).
