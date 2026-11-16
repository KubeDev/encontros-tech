# TRD — Technical Requirements Document

> Documento técnico global do projeto Encontros Tech. Criado e atualizado via skill `escrever-trd`.
> Granularidade baixa: cobre o que é global e estável. Regras finas ficam em ADRs.
>
> **Contexto do ciclo atual:** porte da aplicação de um servidor com systemd para imagem
> Docker, Docker Compose local e manifestos Kubernetes, com banco PostgreSQL gerenciado na
> DigitalOcean, **sem alteração do código da aplicação** ([ADR 004](adrs/004-porte-sem-alteracao-de-codigo.md)).
>
> Marcações: **[Verificado — fonte, data]** fato externo consultado; **[premissa]** inferido na
> consolidação, aceito pelo responsável, mas ainda passível de correção.

---

## Stack

| Dimensão | Valor |
|---|---|
| Linguagem principal | Python 3.12 (`.python-version`; `requires-python >=3.12,<3.14`) |
| Runtime / plataforma | Contêiner Docker (Python 3.12 slim) em Kubernetes — DOKS **[premissa]** |
| Framework principal | Flask 3.0.0, servido por gunicorn 21.2.0 |
| Banco de dados | PostgreSQL gerenciado da DigitalOcean (produção) — versão major 18 **[premissa: padrão para clusters novos; confirme a do seu cluster]**; PostgreSQL 18 em contêiner (local) |
| Acesso a dados | SQLAlchemy 2.0.43 + psycopg2-binary 2.9.10; validação com Pydantic 2.11.7 |
| Ferramentas de build | Docker (imagem multi-stage) |
| Gerenciador de pacotes | uv (`pyproject.toml` + `uv.lock`, `package = false`) |
| Registry de imagens | Docker Hub |
| Orquestração | Kubernetes, manifestos em YAML puro aplicados com `kubectl` ([ADR 002](adrs/002-manifestos-kubernetes-yaml-puro.md)) |

---

## Arquitetura

### Padrão arquitetural

Monólito web em camadas (routers → services → models), com páginas server-side (Jinja2) e uma
API JSON no mesmo processo. A aplicação não guarda estado próprio: todo o estado fica no
PostgreSQL, o que permite rodar várias réplicas sem coordenação entre elas.

### Estrutura de pastas dominante

```
encontros-tech/
├── pyproject.toml / uv.lock  # dependências (uv); raiz é o contexto de build da imagem
├── docs/                     # TRD e ADRs
└── src/                      # código da aplicação (diretório de trabalho do gunicorn)
    ├── main.py               # app Flask, métricas, create_all no import
    ├── core/                 # settings (env), database (engine/sessão), logging
    ├── routers/              # api_router (/api/events) e page_router (páginas HTML)
    ├── services/             # regras de negócio de eventos
    ├── models/               # modelos SQLAlchemy
    ├── schemas/              # schemas Pydantic
    ├── templates/ static/    # Jinja2, CSS, JS
    └── tests/                # pytest
```

### Módulos / camadas principais

| Módulo | Responsabilidade |
|---|---|
| `routers` | HTTP: API JSON em `/api/events` e páginas HTML |
| `services` | Operações de evento (criar, listar, editar via `edit_token`) |
| `models` / `schemas` | Persistência (SQLAlchemy) e validação (Pydantic) |
| `core` | Configuração por variáveis de ambiente, engine do banco, logging no stdout |

### Topologia de execução

**Produção (Kubernetes):**

| Componente | Definição |
|---|---|
| Deployment | 2 réplicas; gunicorn com **2 workers sync** por pod, ouvindo em `0.0.0.0:8000`, `main:app`, com o diretório de trabalho em `src/` ([ADR 005](adrs/005-orcamento-de-conexoes-worker-sync-sem-pgbouncer.md)) |
| Service | Tipo `LoadBalancer` (provisiona um Load Balancer da DigitalOcean), HTTP, sem TLS neste ciclo **[premissa]** ([ADR 003](adrs/003-exposicao-service-loadbalancer.md)) |
| ConfigMap | Configuração não sensível: `APP_TITLE`, `DEBUG=false`, `LOG_LEVEL`, `LOG_FORMAT`, `SERVICE_NAME`, `SERVICE_VERSION` |
| Secret | `DATABASE_URL` completa (usuário, senha, host, porta e `sslmode=require`). Não é versionada com valores reais **[premissa]** |
| Probes | `tcpSocket` na porta 8000 para liveness e readiness; sem probe HTTP, porque `/` consulta o banco ([ADR 004](adrs/004-porte-sem-alteracao-de-codigo.md)) |
| Banco | PostgreSQL gerenciado da DigitalOcean, fora do cluster ([ADR 001](adrs/001-banco-postgresql-gerenciado-digitalocean.md)) |

**Local (Docker Compose):** serviço da aplicação (mesma imagem) + serviço PostgreSQL 18 com
volume, configurados a partir de `.env` (modelo em `.env.exemple`).

### Imagem Docker

- Base Python 3.12 slim, multi-stage: o estágio de build instala as dependências pelo `uv.lock`
  (sem as de desenvolvimento); o estágio final leva só o ambiente e `src/`.
- Executa como usuário não-root; `/tmp` gravável (o código cria o diretório de métricas lá).
- Contexto de build na raiz do repositório (o `uv.lock` fica na raiz; o Dockerfile antigo, removido
  em `0f5bbad`, usava `src/` e `requirements.txt`).

### Inicialização do schema

`create_all` roda no import de `main.py`, em todo processo. A estratégia definitiva está
**em aberto** ([ADR 006](adrs/006-estrategia-de-schema-e-migrations.md)).

---

## Requisitos Não-Funcionais

| Dimensão | Requisito |
|---|---|
| Performance | Não definido |
| Disponibilidade / SLA | Sem SLA definido. 2 réplicas, para manter a aplicação no ar durante o rolling update e se um nó cair. HA e backup do banco ficam com a DigitalOcean |
| Escalabilidade | Escalar por réplicas, não por workers. Limite dado pela regra de conexões: `(réplicas + surge) × workers × conexões por worker ≤ conexões do plano − folga`. Hoje: (2 + 1) × 2 × 1 = 6 de 22 no plano de 1 GiB. Passou do limite → PgBouncer ou plano maior, via ADR novo ([ADR 005](adrs/005-orcamento-de-conexoes-worker-sync-sem-pgbouncer.md)). Sem autoscaling neste ciclo |
| Segurança | Conexão com o banco por TLS (`sslmode=require`) **[Verificado — DigitalOcean, How to Connect, 2026-11-16]**; credenciais só em Secret; imagem não-root. Riscos aceitos: `SECRET_KEY` fixa no código; tráfego público em HTTP sem TLS; o `edit_token` aparece em log de nível INFO no service de eventos |
| Observabilidade | Logs em texto no stdout (sem cor fora de TTY). Métricas Prometheus em `/metrics` na porta da aplicação, refletindo só o worker que atendeu (risco aceito; `PROMETHEUS_MULTIPROC_DIR` não deve ser definida no contêiner). A coleta pelo Prometheus fica fora do escopo deste ciclo |

---

## Dependências Externas

| Serviço / Sistema | Tipo | Constraint relevante | Dono |
|---|---|---|---|
| PostgreSQL gerenciado — DigitalOcean | Banco relacional via TCP/TLS | Conexões por plano: 1 GiB = 22, 2 GiB = 47, 4 GiB = 97 (3 já reservadas para manutenção); sem `superuser`; padrão `sslmode=require`; porta lida dos dados de conexão do cluster; PgBouncer gerenciado disponível (modo transaction por padrão, até 21 pools por cluster); versões 15 a 18 em clusters novos, 18 como padrão **[Verificado — docs.digitalocean.com: [Limits](https://docs.digitalocean.com/products/databases/postgresql/details/limits/), [Connect](https://docs.digitalocean.com/products/databases/postgresql/how-to/connect/), [Connection Pools](https://docs.digitalocean.com/products/databases/postgresql/how-to/manage-connection-pools/), [Version Support Policy](https://docs.digitalocean.com/products/databases/version-support-policy/), 2026-11-16]** | externo — DigitalOcean |
| Kubernetes — DOKS | Plataforma de execução | Service `LoadBalancer` cria um Load Balancer pago da DigitalOcean por Service **[premissa: cluster DOKS]** | externo — DigitalOcean |
| Docker Hub | Registry de imagens | Origem da imagem da aplicação para o cluster | externo — Docker |

---

## Padrões

### Testes

| Item | Valor |
|---|---|
| Framework | pytest 8.3.4 (grupo `dev`) |
| Comando completo | `uv run pytest` (config em `pyproject.toml`: `pythonpath = ["src"]`, `testpaths = ["src/tests"]`) |
| Cobertura mínima | Não definida |
| Estratégia | Testes unitários de service com sessão do banco mockada (`MagicMock`); sem integração nem E2E automatizados. Os testes não entram na imagem de produção |

### Estilo de código

- **Linter:** não configurado
- **Formatter:** não configurado
- **Convenções de nomenclatura:** snake_case para funções e módulos, PascalCase para classes (PEP 8)

### Error handling

Erros de domínio são exceções explícitas (ex.: `EventNotFoundError`). Os routers convertem
`ValueError` em 400 e exceções genéricas em 500 com `abort`, logando o erro antes.

### Logging

- **Formato:** texto `asctime | level | name | func:line | message` no stdout; cor só em TTY
- **Nível padrão:** `INFO` (`DEBUG` quando `DEBUG=true`), ajustável por `LOG_LEVEL`
- **Biblioteca:** `logging` da stdlib, com helpers em `core/logging.py` (`log_request`, `log_business_event`, `log_database_operation`)

### Configuração

Toda a configuração vem de variáveis de ambiente lidas em `core/settings.py` (com `.env` opcional
via python-dotenv). No contêiner, as variáveis vêm do ConfigMap e do Secret; nenhum `.env` entra
na imagem.

### Autenticação / autorização

Não há autenticação de usuário. A edição de um evento é autorizada pela posse do `edit_token`
(UUID gerado na criação).

---

## Decisões Globais (ADRs)

| # | Título | Data | Status | Link |
|---|--------|------|--------|------|
| 001 | Banco PostgreSQL gerenciado na DigitalOcean, fora do cluster | 2026-11-16 | aceito | [001](adrs/001-banco-postgresql-gerenciado-digitalocean.md) |
| 002 | Manifestos Kubernetes em YAML puro | 2026-11-16 | aceito | [002](adrs/002-manifestos-kubernetes-yaml-puro.md) |
| 003 | Exposição da aplicação por Service do tipo LoadBalancer | 2026-11-16 | aceito | [003](adrs/003-exposicao-service-loadbalancer.md) |
| 004 | Porte para contêiner sem alterar o código da aplicação | 2026-11-16 | aceito | [004](adrs/004-porte-sem-alteracao-de-codigo.md) |
| 005 | Orçamento de conexões com worker sync e sem PgBouncer | 2026-11-16 | aceito | [005](adrs/005-orcamento-de-conexoes-worker-sync-sem-pgbouncer.md) |
| 006 | Estratégia de criação do schema e migrations | 2026-11-16 | proposto | [006](adrs/006-estrategia-de-schema-e-migrations.md) |
