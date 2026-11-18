# TRD — Technical Requirements Document

> Documento técnico global do projeto Encontros Tech. Criado e atualizado via skill `escrever-trd`.
> Granularidade baixa: cobre o que é global e estável. Regras finas ficam em ADRs.
>
> **Contexto do ciclo atual:** porte da aplicação de um servidor com systemd para imagem
> Docker, Docker Compose local e manifestos Kubernetes, com banco PostgreSQL gerenciado na
> DigitalOcean, **sem alteração do código da aplicação** ([ADR 004](adrs/004-porte-sem-alteracao-de-codigo.md)).
> O ambiente na DigitalOcean é de **homologação de um MVP**, não de produção, dimensionado para
> custo baixo e provisionado com Terraform ([ADR 007](adrs/007-rede-vpc-dedicada-homologacao.md),
> [ADR 008](adrs/008-terraform-estado-local-aplicacao-manual.md), [ADR 009](adrs/009-homologacao-otimizada-para-custo.md)).
>
> Os manifestos Kubernetes seguem o padrão definido em
> [Padrão dos manifestos Kubernetes](#padrão-dos-manifestos-kubernetes).
>
> **Pipelines:** validação de PR, CI e CD em GitHub Actions; todo merge de código na `main` vira
> imagem publicada e aplicada na homologação, sem passo manual. O Terraform fica fora da automação
> ([ADR 011](adrs/011-entrega-em-tres-workflows-github-actions.md) a
> [ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md); ver [Pipelines](#pipelines)).
>
> Marcações: **[Verificado — fonte, data]** fato externo consultado; **[premissa]** inferido na
> consolidação, aceito pelo responsável, mas ainda passível de correção.

---

## Stack

| Dimensão | Valor |
|---|---|
| Linguagem principal | Python 3.12 (`.python-version`; `requires-python >=3.12,<3.14`) |
| Runtime / plataforma | Contêiner Docker (Python 3.12 slim) em Kubernetes gerenciado da DigitalOcean (DOKS), versão `1.37.2-do.0` como valor inicial **[premissa: DOKS]** **[Verificado — `doctl kubernetes options versions`, 2026-11-17]** |
| Framework principal | Flask 3.0.0, servido por gunicorn 21.2.0 |
| Banco de dados | PostgreSQL 18 gerenciado da DigitalOcean (homologação) **[Verificado — `doctl databases options versions`: 15 a 18, 2026-11-17]**; PostgreSQL 18 em contêiner (local) |
| Acesso a dados | SQLAlchemy 2.0.43 + psycopg2-binary 2.9.10; validação com Pydantic 2.11.7 |
| Ferramentas de build | Docker (imagem single-stage) |
| Infraestrutura como código | Terraform ≥ 1.17 com provider `digitalocean` ~> 2.108, estado local, aplicado manualmente **[Verificado — registry.terraform.io e checkpoint-api.hashicorp.com: Terraform 1.17.2, provider 2.108.0, 2026-11-17]** ([ADR 008](adrs/008-terraform-estado-local-aplicacao-manual.md)) |
| Gerenciador de pacotes | uv (`pyproject.toml` + `uv.lock`, `package = false`) |
| Registry de imagens | Docker Hub, repositório público, tag `v<run_number>` da CI, sobrescrita permitida ([ADR 012](adrs/012-tag-run-number-com-sobrescrita.md), que substitui o [ADR 010](adrs/010-imagem-docker-hub-publico-tags-sequenciais.md)) |
| CI/CD | GitHub Actions: workflows de PR, CI e CD ([ADR 011](adrs/011-entrega-em-tres-workflows-github-actions.md)) |
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

### Infraestrutura na DigitalOcean (homologação)

```mermaid
flowchart LR
    usuarios(["Quem testa a homologação"])
    operador["Máquina do operador<br/>Terraform + estado local<br/>kubectl / psql"]
    gha["GitHub Actions<br/>CI publica · CD aplica"]
    dockerhub[("Docker Hub (público)<br/>imagem da aplicação, tags v#lt;run_number#gt;")]

    subgraph cloud["DigitalOcean — região var.region (padrão nyc1)"]
        subgraph vpc["VPC dedicada ao projeto"]
            lb["Load Balancer<br/>HTTP :80<br/>criado pelo Service"]
            subgraph doks["Cluster DOKS — control plane sem HA"]
                subgraph n1["Nó 1 — s-1vcpu-2gb"]
                    p1["Pod encontros-tech<br/>gunicorn, 2 workers sync"]
                end
                subgraph n2["Nó 2 — s-1vcpu-2gb"]
                    p2["Pod encontros-tech<br/>gunicorn, 2 workers sync"]
                end
            end
            db[("PostgreSQL 18 gerenciado<br/>db-amd-1vcpu-1gb, 1 nó<br/>sem trusted sources")]
        end
    end

    usuarios -->|HTTP| lb
    lb --> p1
    lb --> p2
    p1 -->|"endereço privado, TLS"| db
    p2 -->|"endereço privado, TLS"| db
    dockerhub -.->|pull da imagem| doks
    operador -.->|"terraform apply: VPC, cluster, banco"| cloud
    gha -.->|"push da imagem"| dockerhub
    gha -.->|"kubectl apply: Secret + manifestos"| doks
    operador -.->|"endereço público, TLS"| db
```

| Recurso | Definição | Criado por |
|---|---|---|
| VPC | Dedicada ao projeto, na região `var.region` (padrão `nyc1`). Mudar a região = destruir e recriar tudo ([ADR 007](adrs/007-rede-vpc-dedicada-homologacao.md)) | Terraform |
| Cluster DOKS | VPC-native, sub-redes de pods /16 e services /19 sem sobrepor nenhuma VPC do time **[premissa: tamanhos padrão]**; `ha = false` explícito; versão por variável (inicial `1.37.2-do.0`), patch automático ligado; `destroy_all_associated_resources = true`; API sem `control_plane_firewall` ([ADR 009](adrs/009-homologacao-otimizada-para-custo.md)) | Terraform |
| Node pool | 2 nós `s-1vcpu-2gb`, sem autoscaling | Terraform |
| Banco | PostgreSQL 18, `db-amd-1vcpu-1gb`, 1 nó sem standby, sem trusted sources (aceita qualquer origem — risco aceito) | Terraform |
| Load Balancer | Um, criado pelo Service `LoadBalancer` dentro da VPC ([ADR 003](adrs/003-exposicao-service-loadbalancer.md)) | Kubernetes (Service) |
| Aplicação | Namespace, Deployment, Service e ConfigMap em YAML puro ([ADR 002](adrs/002-manifestos-kubernetes-yaml-puro.md)); Secret criado pelo CD a partir do secret `DATABASE_URL` do GitHub | `kubectl` no CD (GitHub Actions) |

**Fronteira Terraform × pipeline:** a `DATABASE_URL` vem do output `database_url` do Terraform e é
copiada **manualmente** para o secret `DATABASE_URL` do repositório no GitHub; o CD cria o Secret
no cluster ([ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md), que substitui
esse passo do [ADR 008](adrs/008-terraform-estado-local-aplicacao-manual.md)). O Terraform não roda
em nenhuma pipeline. O estado do Terraform e os `*.tfvars` contêm segredos e nunca são commitados.

### Topologia de execução

**Homologação (Kubernetes):**

| Componente | Definição |
|---|---|
| Namespace | `encontros-tech`, dedicado; nada da aplicação vai para o `default` **[premissa]** |
| Deployment | 2 réplicas (uma por nó, quando o scheduler distribuir **[premissa]**); gunicorn com **2 workers sync** por pod, ouvindo em `0.0.0.0:8000`, `main:app`, com o diretório de trabalho em `src/` ([ADR 005](adrs/005-orcamento-de-conexoes-worker-sync-sem-pgbouncer.md)). Imagem do Docker Hub com tag `v<run_number>` aplicada pelo CD, nunca `latest` ([ADR 012](adrs/012-tag-run-number-com-sobrescrita.md)). Estratégia `RollingUpdate` padrão, sem `minReadySeconds`: com 2 réplicas, o padrão arredonda `maxUnavailable` para 0 e `maxSurge` para 1 |
| Service | Tipo `LoadBalancer` (provisiona um Load Balancer da DigitalOcean), HTTP, sem TLS e sem domínio neste ciclo — acesso pelo IP do Load Balancer ([ADR 003](adrs/003-exposicao-service-loadbalancer.md)) |
| ConfigMap | Configuração não sensível: `APP_TITLE`, `DEBUG=false`, `LOG_LEVEL`, `LOG_FORMAT`, `SERVICE_NAME`, `SERVICE_VERSION`. `SERVICE_VERSION` usa o mesmo `v<run_number>` da tag da imagem, injetado pelo CD ([ADR 013](adrs/013-versao-aplicada-no-runner-sem-commit.md)) |
| Secret | `encontros-tech-secrets`, com a `DATABASE_URL` completa pelo **host privado** do banco (usuário, senha, host, porta e `sslmode=require`). **Criado ou atualizado pelo CD** a cada deploy, a partir do secret `DATABASE_URL` do repositório no GitHub; não existe em nenhum YAML do repositório ([ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md)) |
| Probes | **Nenhuma** (liveness, readiness e startup), por simplicidade. Substitui a probe `tcpSocket` citada nas consequências do [ADR 004](adrs/004-porte-sem-alteracao-de-codigo.md). Custo aceito: ver [Padrão dos manifestos Kubernetes](#padrão-dos-manifestos-kubernetes) |
| Banco | PostgreSQL gerenciado da DigitalOcean, fora do cluster e dentro da mesma VPC ([ADR 001](adrs/001-banco-postgresql-gerenciado-digitalocean.md), [ADR 007](adrs/007-rede-vpc-dedicada-homologacao.md)) |

**Local (Docker Compose):** serviço da aplicação (mesma imagem) + serviço PostgreSQL 18 com
volume, configurados a partir de `.env` (modelo em `.env.exemple`).

### Padrão dos manifestos Kubernetes

Regras que todo manifesto da aplicação segue. Escopo: **homologação**; não há validação
automática dos YAMLs neste ciclo (kubeconform, kube-linter) — a conferência é na revisão.

| Regra | Definição |
|---|---|
| Formato | YAML puro aplicado com `kubectl apply` ([ADR 002](adrs/002-manifestos-kubernetes-yaml-puro.md)); **um único arquivo** `k8s/encontros-tech.yaml` com todos os recursos (Namespace, ConfigMap, Deployment, Service) separados por `---` — decisão do responsável |
| Namespace | Todo recurso declara `namespace: encontros-tech` **[premissa]** |
| Labels | Labels recomendadas `app.kubernetes.io/*` (`name`, `instance`, `version`, `component`, `part-of`, `managed-by`) em todos os recursos; o `selector` do Deployment e do Service usa só labels estáveis (sem `version`) **[premissa]** |
| Imagem | `<usuário>/<repositório>:v<run_number>` do Docker Hub público, sem `imagePullSecret`; sobrescrita de tag permitida; nunca `latest` ([ADR 012](adrs/012-tag-run-number-com-sobrescrita.md)) |
| Versão | O CD troca, **só na cópia do runner**, a tag da imagem, o `SERVICE_VERSION` e a label `app.kubernetes.io/version`, e aplica; o arquivo no repositório não é commitado e não reflete a versão em execução — consultar o cluster. Um `kubectl apply` manual a partir do repositório volta o cluster para a versão escrita no arquivo ([ADR 013](adrs/013-versao-aplicada-no-runner-sem-commit.md)) |
| Probes | Nenhuma, por **simplicidade** — decisão do responsável. Não adicionar probes sem rever esta regra. Custo aceito: (1) sem readiness, o pod novo entra no Load Balancer assim que o contêiner sobe, antes de o gunicorn abrir a porta 8000 — por alguns segundos a cada rollout, parte das requisições recebe recusa de conexão ou 502; (2) sem liveness, um processo travado sem cair continua recebendo tráfego. Processo que **morre** (ex.: `create_all` falhando) é reiniciado pela `restartPolicy`, sem precisar de probe. O `HEALTHCHECK` do Dockerfile é ignorado pelo Kubernetes e vale só no Compose |
| Recursos | Todo contêiner declara `requests` e `limits` de CPU e memória; valores definidos no manifesto, compatíveis com nós `s-1vcpu-2gb` e 1 pod por nó **[premissa]** |
| securityContext | `runAsNonRoot: true` com `runAsUser: 1001` (o Dockerfile declara `USER app` pelo nome; sem UID numérico o kubelet não consegue confirmar que não é root e recusa o contêiner); `allowPrivilegeEscalation: false`; `capabilities.drop: [ALL]`; `readOnlyRootFilesystem: true` com `/tmp` montado como `emptyDir`, porque o código grava métricas lá **[premissa]** |
| Secret | Criado ou atualizado pelo CD antes do Deployment, no namespace `encontros-tech`, com a chave `DATABASE_URL` vinda do secret do repositório no GitHub; o Deployment só referencia o Secret pelo nome ([ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md)) |
| Schema | Sem Job nem initContainer de schema: vale o `create_all` no import ([ADR 006](adrs/006-estrategia-de-schema-e-migrations.md), em aberto) |

### Imagem Docker

- Base Python 3.12 slim, **single-stage**: o `uv` e o `uv.lock` entram só como mount de build
  (`uv sync --frozen --no-dev`), sem ficar em nenhuma camada; a imagem leva o ambiente e `src/`.
- Construída e publicada pela CI no Docker Hub, repositório público, com tag `v<run_number>`
  ([ADR 012](adrs/012-tag-run-number-com-sobrescrita.md)).
  Como é pública, nada sensível entra nela: credenciais só pelo Secret, nenhum `.env` copiado.
- Executa como usuário não-root `app` (UID 1001); `/tmp` gravável (o código cria o diretório de métricas lá).
- Contexto de build na raiz do repositório (o `uv.lock` fica na raiz; o Dockerfile antigo, removido
  em `0f5bbad`, usava `src/` e `requirements.txt`).

### Inicialização do schema

`create_all` roda no import de `main.py`, em todo processo. Com 2 réplicas × 2 workers subindo
juntos, um pod pode reiniciar uma vez no primeiro deploy (risco aceito). A estratégia definitiva
está **em aberto** ([ADR 006](adrs/006-estrategia-de-schema-e-migrations.md)).

### Pipelines

Três workflows do GitHub Actions ([ADR 011](adrs/011-entrega-em-tres-workflows-github-actions.md)).
O Terraform não roda em nenhum deles e continua aplicado à mão ([ADR 008](adrs/008-terraform-estado-local-aplicacao-manual.md)).

```mermaid
flowchart TB
    dev(["Desenvolvedor"])

    subgraph gh["GitHub — repositório público"]
        pr_open["Pull request para a main"]
        main[("Branch main<br/>protegida: merge só por PR<br/>com o check da PR verde")]
        secrets[["Secrets do repositório<br/>DOCKERHUB_TOKEN · KUBECONFIG · DATABASE_URL<br/>Variables: DOCKERHUB_USERNAME · IMAGE_NAME"]]

        subgraph wf_pr["Workflow PR — toda PR, sem filtro de caminho, sem secrets"]
            pr_test["uv run pytest"]
            pr_build["docker build<br/>(sem push)"]
            pr_test --> pr_build
        end

        subgraph wf_ci["Workflow CI — push na main que altera<br/>src/** · Dockerfile · .dockerignore · pyproject.toml · uv.lock · k8s/**"]
            ci_test["uv run pytest"]
            ci_build["docker build"]
            ci_push["docker push<br/>IMAGE_NAME:v#lt;run_number#gt;"]
            ci_test --> ci_build --> ci_push
        end

        subgraph wf_cd["Workflow CD — workflow_run da CI, só se conclusion = success<br/>um deploy por vez"]
            cd_kube["Kubeconfig a partir do secret"]
            cd_secret["Cria/atualiza Secret<br/>encontros-tech-secrets"]
            cd_render["Troca imagem, SERVICE_VERSION e label version<br/>na cópia do runner (sem commit)"]
            cd_apply["kubectl apply -f k8s/encontros-tech.yaml"]
            cd_wait["Espera o rollout<br/>(com prazo máximo)"]
            cd_kube --> cd_secret --> cd_render --> cd_apply --> cd_wait
        end
    end

    dockerhub[("Docker Hub<br/>fabricioveronez/encontros-tech")]
    doks["Cluster DOKS — homologação<br/>namespace encontros-tech"]
    operador["Operador<br/>terraform apply (manual)<br/>renova KUBECONFIG a cada 7 dias<br/>copia DATABASE_URL do output"]

    dev --> pr_open --> wf_pr
    wf_pr -->|"check obrigatório"| main
    main -->|"push com mudança de código"| wf_ci
    wf_ci -->|"run_number"| wf_cd
    ci_push --> dockerhub
    cd_apply --> doks
    dockerhub -.->|"pull da imagem"| doks
    secrets -.-> wf_ci
    secrets -.-> wf_cd
    operador -.->|"atualiza à mão"| secrets
```

| Workflow | Gatilho | Etapas | Credenciais |
|---|---|---|---|
| **PR** | Toda PR para a `main`, **sem filtro de caminho** — um check obrigatório pulado por filtro fica "Pending" e bloqueia o merge **[Verificado — docs.github.com, Skipping workflow runs, via Context7, 2026-11-18]** | `uv run pytest`; build da imagem sem push | Nenhuma (roda com segurança em PR de fork) |
| **CI** | Push na `main` que altere `src/**`, `Dockerfile`, `.dockerignore`, `pyproject.toml`, `uv.lock` ou `k8s/**`. Mudança só em docs, ADRs ou `terraform/**` não dispara | `uv run pytest`; build; push `IMAGE_NAME:v<run_number>` (sem `latest`) | `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` |
| **CD** | `workflow_run` da CI na `main`, só com `conclusion == success`; versão recebida pelo evento **[Verificado — docs.github.com, workflow_run, via Context7, 2026-11-18]** | Kubeconfig do secret; cria/atualiza o Secret `encontros-tech-secrets`; troca a versão na cópia do runner; `kubectl apply`; espera o rollout com prazo | `KUBECONFIG`, `DATABASE_URL`, `IMAGE_NAME` |

**Regras:**

- **Versão:** `v<run_number>` do workflow de CI; o número começa em 1 e não muda em reexecução
  **[Verificado — docs.github.com, Contexts reference, 2026-11-18]**; sobrescrita de tag
  permitida ([ADR 012](adrs/012-tag-run-number-com-sobrescrita.md)).
- **Manifesto:** a versão é trocada só no runner, sem commit ([ADR 013](adrs/013-versao-aplicada-no-runner-sem-commit.md)).
- **Proteção da `main`:** merge só por PR, com o check do workflow de PR obrigatório
  (configuração do repositório) **[premissa]**.
- **Concorrência:** um deploy por vez; o seguinte espera na fila, sem cancelar o atual **[premissa]**.
- **Sucesso do deploy:** fim do rollout dentro do prazo. Sem probes, isso prova só que o contêiner
  subiu, não que a aplicação responde **[premissa]**.
- **Rollback:** reverter o commit numa PR, o que gera uma versão nova **[premissa]**.
- **Fora de escopo neste ciclo:** lint e formatter de Python, hadolint, validação de manifestos,
  `terraform fmt/validate`, scan de vulnerabilidade, cobertura mínima, GitHub Environments, teste
  de saúde pós-deploy, imagem multi-arquitetura, notificações.

**Secrets e variables** — todos no nível do repositório, sem Environment ([ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md)):

| Tipo | Nome | Conteúdo | Usado por | Origem e manutenção |
|---|---|---|---|---|
| Secret | `DOCKERHUB_TOKEN` | Token de acesso do Docker Hub, leitura e escrita | CI | Criado à mão no Docker Hub |
| Secret | `KUBECONFIG` | Kubeconfig do cluster, token com validade padrão de 7 dias **[Verificado — docs.digitalocean.com, 2026-11-18]** | CD | Renovado à mão a cada 7 dias com `doctl kubernetes cluster kubeconfig show <cluster>` **[premissa]**; vencido, o CD falha |
| Secret | `DATABASE_URL` | Conexão pelo host privado da VPC, `sslmode=require` | CD | `terraform output -raw database_url`, copiado à mão; atualizar se o banco for recriado |
| Variable | `DOCKERHUB_USERNAME` | `fabricioveronez` | CI | — |
| Variable | `IMAGE_NAME` | `fabricioveronez/encontros-tech` | CI, CD | — |

Ficam fora do inventário: os valores do ConfigMap (versionados no manifesto), o `SERVICE_VERSION`
(injetado pelo CD), o namespace (fixo no manifesto), `POSTGRES_*` (só no Compose local) e a
`SECRET_KEY` (fixa no código, [ADR 004](adrs/004-porte-sem-alteracao-de-codigo.md)). Mudar só a
`DATABASE_URL` não reinicia os pods; o valor novo vale quando forem recriados **[premissa]**.

---

## Requisitos Não-Funcionais

| Dimensão | Requisito |
|---|---|
| Performance | Não definido |
| Custo | Restrição declarada: homologação otimizada para custo baixo — control plane sem HA, 2 nós do menor tamanho, banco de 1 nó sem standby ([ADR 009](adrs/009-homologacao-otimizada-para-custo.md)) |
| Disponibilidade / SLA | Sem SLA (homologação). 2 réplicas em 2 nós, para manter a aplicação no ar durante o rolling update e se um nó cair. Sem HA no control plane nem standby no banco: falha do banco derruba o ambiente. Sem probes: a cada rollout há uma janela curta em que parte das requisições falha (ver [Padrão dos manifestos Kubernetes](#padrão-dos-manifestos-kubernetes)), e processo travado não é reiniciado. Backup diário do banco fica com a DigitalOcean; dados de homologação são descartáveis **[premissa]**. Backup do estado do Terraform é responsabilidade do operador, fora do escopo |
| Escalabilidade | Escalar por réplicas, não por workers. Limite dado pela regra de conexões: `(réplicas + surge) × workers × conexões por worker ≤ conexões do plano − folga`. Hoje: (2 + 1) × 2 × 1 = 6 de 22 no plano de 1 GiB. Passou do limite → PgBouncer ou plano maior, via ADR novo ([ADR 005](adrs/005-orcamento-de-conexoes-worker-sync-sem-pgbouncer.md)). Sem autoscaling neste ciclo |
| Segurança | Conexão com o banco por TLS (`sslmode=require`) **[Verificado — DigitalOcean, How to Connect, 2026-11-16]**; aplicação → banco pelo endereço privado da VPC; credenciais só em secrets do repositório no GitHub e no Secret do Kubernetes criado pelo CD, nunca em arquivo versionado nem na imagem; contêiner com `runAsNonRoot`, sem escalada de privilégio, sem capabilities e com sistema de arquivos somente leitura; estado do Terraform e `*.tfvars` fora do Git; imagem não-root. Riscos aceitos: banco sem trusted sources (aceita conexão de qualquer origem) e API do cluster sem firewall ([ADR 007](adrs/007-rede-vpc-dedicada-homologacao.md)) — desenho não serve para produção; `SECRET_KEY` fixa no código; imagem pública no Docker Hub (o código de `src/` fica visível) ([ADR 012](adrs/012-tag-run-number-com-sobrescrita.md)); tags sobrescritas pela CI ([ADR 012](adrs/012-tag-run-number-com-sobrescrita.md)); kubeconfig da pipeline com acesso de admin ao cluster inteiro e validade de 7 dias, renovado à mão; secrets do repositório legíveis por PR de branch interna que altere um workflow (PR de fork não recebe secrets **[Verificado — docs.github.com, Using secrets, 2026-11-18]**); credencial do banco guardada também no GitHub ([ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md)); tráfego público em HTTP sem TLS; o `edit_token` aparece em log de nível INFO no service de eventos |
| Observabilidade | Logs em texto no stdout (sem cor fora de TTY). Métricas Prometheus em `/metrics` na porta da aplicação, refletindo só o worker que atendeu (risco aceito; `PROMETHEUS_MULTIPROC_DIR` não deve ser definida no contêiner). A coleta pelo Prometheus fica fora do escopo deste ciclo |

---

## Dependências Externas

| Serviço / Sistema | Tipo | Constraint relevante | Dono |
|---|---|---|---|
| PostgreSQL gerenciado — DigitalOcean | Banco relacional via TCP/TLS | Conexões por plano: 1 GiB = 22, 2 GiB = 47, 4 GiB = 97 (3 já reservadas para manutenção); sem `superuser`; padrão `sslmode=require`; porta lida dos dados de conexão do cluster; PgBouncer gerenciado disponível (modo transaction por padrão, até 21 pools por cluster); versões 15 a 18 em clusters novos, 18 como padrão **[Verificado — docs.digitalocean.com: [Limits](https://docs.digitalocean.com/products/databases/postgresql/details/limits/), [Connect](https://docs.digitalocean.com/products/databases/postgresql/how-to/connect/), [Connection Pools](https://docs.digitalocean.com/products/databases/postgresql/how-to/manage-connection-pools/), [Version Support Policy](https://docs.digitalocean.com/products/databases/version-support-policy/), 2026-11-16]** | externo — DigitalOcean |
| Kubernetes — DOKS | Plataforma de execução | Service `LoadBalancer` cria um Load Balancer pago por Service **[premissa: cluster DOKS]**. Cluster e Load Balancer não migram de VPC; sub-redes VPC-native fixadas na criação, sem sobreposição com VPCs do time e sem ampliação; control plane HA ligado por padrão a partir da 1.36 e irreversível; menor nó `s-1vcpu-2gb` **[Verificado — docs.digitalocean.com (VPC, DOKS) e docs do provider Terraform via Context7; `doctl`, 2026-11-17]** | externo — DigitalOcean |
| VPC — DigitalOcean | Rede privada | Regional: só recursos da mesma região; banco gerenciado pode migrar de VPC, cluster e Load Balancer não **[Verificado — docs.digitalocean.com, VPC, via Context7, 2026-11-17]** | externo — DigitalOcean |
| Terraform + provider `digitalocean` | Provisionamento | Estado local com segredos em texto puro; sem lock de concorrência (operador único) ([ADR 008](adrs/008-terraform-estado-local-aplicacao-manual.md)) | externo — HashiCorp / DigitalOcean |
| Docker Hub | Registry de imagens | Repositório público, pull anônimo pelo cluster. Limite de pull anônimo: 100 a cada 6 horas por IPv4 (ou sub-rede IPv6 /64); conta pessoal autenticada: 200 **[Verificado — [Docker Hub pull usage and limits](https://docs.docker.com/docker-hub/usage/pulls/), 2026-11-17]**. Com 2 nós e poucos deploys, longe do limite ([ADR 010](adrs/010-imagem-docker-hub-publico-tags-sequenciais.md)). Push pela CI com token de acesso em secret ([ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md)) | externo — Docker |
| GitHub Actions | Execução das pipelines de PR, CI e CD | `run_number` começa em 1 por workflow e não muda em reexecução; `workflow_run` só dispara se o workflow existir na branch padrão e dispara em qualquer conclusão (filtrar por `success`); check obrigatório pulado por filtro de caminho bloqueia o merge; secrets não chegam a PR de fork **[Verificado — docs.github.com (contexts, events-that-trigger-workflows, skip-workflow-runs, use-secrets), via Context7, 2026-11-18]** ([ADR 011](adrs/011-entrega-em-tres-workflows-github-actions.md)) | externo — GitHub |
| Kubeconfig do DOKS | Credencial do CD | Token expira em 7 dias por padrão; validade ajustável por `expiry_seconds`, sem máximo documentado **[Verificado — docs.digitalocean.com e docs do provider, via Context7, 2026-11-18]** ([ADR 014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md)) | externo — DigitalOcean |

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
| 007 | Rede da homologação — VPC dedicada, banco por endereço privado e acesso público aceito | 2026-11-17 | aceito | [007](adrs/007-rede-vpc-dedicada-homologacao.md) |
| 008 | Infraestrutura em Terraform, com estado local e aplicação manual | 2026-11-17 | aceito | [008](adrs/008-terraform-estado-local-aplicacao-manual.md) |
| 009 | Ambiente de homologação dimensionado para custo baixo | 2026-11-17 | aceito | [009](adrs/009-homologacao-otimizada-para-custo.md) |
| 010 | ~~Imagem publicada no Docker Hub, repositório público, com tags sequenciais~~ | 2026-11-17 | obsoleto (substituído pelo 012) | [010](adrs/010-imagem-docker-hub-publico-tags-sequenciais.md) |
| 011 | Entrega em três workflows do GitHub Actions, com CD automático disparado pela CI | 2026-11-18 | aceito | [011](adrs/011-entrega-em-tres-workflows-github-actions.md) |
| 012 | Tag da imagem `v<run_number>` da CI, com sobrescrita permitida | 2026-11-18 | aceito | [012](adrs/012-tag-run-number-com-sobrescrita.md) |
| 013 | Versão aplicada só na cópia do runner, sem commit do manifesto | 2026-11-18 | aceito | [013](adrs/013-versao-aplicada-no-runner-sem-commit.md) |
| 014 | Credenciais da pipeline em secrets do repositório — kubeconfig de 7 dias e `DATABASE_URL` aplicada pelo CD | 2026-11-18 | aceito | [014](adrs/014-credenciais-da-pipeline-em-secrets-do-repositorio.md) |
