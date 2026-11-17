---
name: docker-practices
description: "Boas práticas, padrões de qualidade e validação para Dockerfile, imagens Docker e docker-compose. Use esta skill sempre que estiver escrevendo, revisando, otimizando ou validando Dockerfile, .dockerignore, docker-compose.yml, compose.yaml ou executando comandos docker/docker compose — inclui decisão de multi-stage, segurança, camadas, healthchecks, networks, volumes, orquestração local para desenvolvimento e um gate de validação com hadolint, build e execução em compose. Ativar mesmo quando o usuário não pedir explicitamente por 'boas práticas' ou 'validação', bastando que a tarefa envolva criar, revisar ou verificar artefatos Docker. O gate roda automaticamente sempre que artefatos Docker forem criados, alterados ou revisados, e a entrega termina num relatório de criação e validação com evidências por nível."
---

# Docker Practices

Guia prescritivo de boas práticas para Dockerfile, imagens Docker e docker-compose. Aplique estas convenções diretamente ao código sem explicar cada decisão — o objetivo é consistência, segurança e performance, não ensinar conceitos.

O documento tem quatro partes:
1. **Dockerfile e imagem** — build e convenções de artefato
2. **Segurança** — o que não pode entrar na imagem
3. **Docker Compose** — orquestração local
4. **Validação de qualidade** — como verificar que o artefato está correto

## Quando aprofundar

Os guias em `references/` aprofundam o "porquê" das práticas e cobrem casos do mundo real. Carregue sob demanda quando:

| Cenário | Reference |
|---|---|
| Escrevendo Dockerfile do zero, decidindo quantos stages usar, ou debugando build lento | `references/por-que-multi-stage-e-camadas.md` |
| Em dúvida entre alpine/slim/distroless, ou imagem ficou enorme, ou falha "shared library" em runtime | `references/escolhendo-base-image.md` |
| Antes de subir imagem em produção pela primeira vez, ou alguém menciona "scan", "supply chain", "CVE" | `references/seguranca-em-containers.md` |
| Montando ambiente local com banco/Redis/fila, ou `docker compose up` sobe mas app não responde | `references/praticas-docker-compose.md` |
| Executando o gate de validação, montando o `.hadolint.yaml`, ou o gate falhou e não está claro por quê | `references/validacao-de-qualidade.md` |

---

## Parte 1 — Dockerfile e imagem

### Base image

- Use tags pinadas com versão específica — nunca `latest` em produção
- Prefira variantes slim/alpine/distroless quando compatíveis com o runtime — reduzem superfície de ataque e tamanho
- Distroless para binários estáticos (Go, Rust, Java com jlink) — sem shell, sem package manager
- Alpine apenas quando a lib C (musl vs glibc) não for problema — alguns binários Python/Node precisam glibc

```dockerfile
# Bom — tag pinada e slim
FROM node:20.11.1-slim

# Ruim — latest e base cheia
FROM node:latest
```

### Decisão de multi-stage

Antes de escrever os stages, decida se precisa deles e quantos. Três eixos independentes.

**Eixo 1 — vale a pena?** O ganho depende de quanto o artefato final difere do necessário para produzi-lo.

| Natureza do artefato | Multi-stage | Ganho |
|---|---|---|
| Compilada (Go, Rust, C#, Java) | Obrigatório | Enorme — 1 GB → 20 MB; runtime pode ser distroless ou `scratch` |
| Transpilada (TS, bundlers, Sass) | Obrigatório | Grande — sai toolchain e devDependencies |
| Interpretada com extensões C (`psycopg2`, `node-gyp`, `nokogiri`) | Sim | Médio — sai o `build-essential`. **Atenção:** os stages precisam da mesma libc, senão o `.so` do builder não carrega no runtime |
| Interpretada pura (Python puro, PHP) | Opcional | Pequeno — single-stage sobre base slim é aceitável |
| Assets estáticos → nginx | Obrigatório | Node constrói, nginx serve |

**Eixo 2 — quantos stages?**

- **2 (builder + runtime)** — default. Não invente um terceiro sem nomear o problema que ele resolve
- **3 (deps + build + runtime)** — quando dependências e código mudam em ritmos diferentes; isolar o install dá cache estável
- **Extras (`lint`, `docs`)** — só se algo externo consome via `--target`. Stage não consumido é peso morto

**Eixo 3 — o que atravessa o `COPY --from`?** Só o artefato e as dependências de runtime, nunca o diretório de build inteiro.

```dockerfile
# Ruim — desfaz o multi-stage
COPY --from=builder /app /app

# Bom — só o que roda
COPY --from=builder /app/dist ./dist
```

> **Heurística de parada:** se o stage final contém algo que você não executaria em produção — compilador, gerenciador de pacotes, código-fonte de linguagem compilada — falta um stage. Se você não sabe explicar por que um arquivo está na imagem final, ele não deveria estar.

### Multi-stage builds

- Separe estágios de build e runtime — imagem final carrega só o necessário para rodar
- Nomeie estágios com `AS` para referenciar em `COPY --from=`
- Stage final deve ser mínimo — sem compiladores, sem dev dependencies

```dockerfile
FROM node:20.11.1-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20.11.1-slim AS runtime
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package*.json ./
USER node
CMD ["node", "dist/index.js"]
```

### Ordem de camadas e cache

- Instruções que mudam menos vão primeiro — cache é invalidado em cascata
- Copie manifestos de dependência antes do código-fonte, instale, depois copie o resto
- Agrupe comandos `RUN` relacionados com `&&` para reduzir camadas, sem sacrificar legibilidade

```dockerfile
# Bom — manifestos antes do código
COPY package*.json ./
RUN npm ci
COPY . .

# Ruim — qualquer mudança de código reinstala dependências
COPY . .
RUN npm ci
```

### .dockerignore

- Sempre criar `.dockerignore` — arquivos desnecessários em build context degradam performance e podem vazar secrets
- Incluir: `.git`, `node_modules`, `.env*`, `*.log`, diretórios de IDE, artefatos de build local

```
.git
.gitignore
node_modules
npm-debug.log*
.env
.env.*
!.env.example
.vscode
.idea
dist
build
coverage
*.md
```

### HEALTHCHECK

- Defina `HEALTHCHECK` para imagens de serviço — orquestradores usam para rotear tráfego
- Intervalos conservadores (30s–60s) para não pressionar o app

```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://localhost:3000/health || exit 1
```

### Labels (OCI annotations)

- Adicione labels OCI para rastreabilidade — úteis em registries e scanners
- Passe via `ARG` para não fixar valores no Dockerfile

```dockerfile
ARG VERSION=dev
ARG COMMIT_SHA=unknown
LABEL org.opencontainers.image.source="https://github.com/org/repo" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${COMMIT_SHA}" \
      org.opencontainers.image.licenses="MIT"
```

### ENTRYPOINT vs CMD

- `ENTRYPOINT` para o binário principal — não deve ser sobrescrito casualmente
- `CMD` para argumentos default — fáceis de sobrescrever em `docker run`
- Use forma exec (`["cmd", "arg"]`), não forma shell — garante que sinais (SIGTERM) cheguem ao processo

```dockerfile
ENTRYPOINT ["node"]
CMD ["dist/index.js"]
```

### Tamanho de imagem

- Instale só o necessário — evite ferramentas de debug em runtime
- Limpe cache de package managers na mesma camada em que instalou
- `--no-install-recommends` em apt, `--no-cache` em apk
- Verifique tamanho com `docker images` e `dive` antes de publicar

```dockerfile
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*
```

---

## Parte 2 — Segurança

Regras prescritivas abaixo. O "porquê" de cada uma, incidentes reais e o que fazer diante de um scan com 200 CVEs estão em `references/seguranca-em-containers.md`.

### Procedência da imagem

- Prefira imagens oficiais ou de fornecedores confiáveis (Microsoft, Bitnami, Chainguard)
- Tag pinada não é só reprodutibilidade, é segurança — `latest` significa que o conteúdo da sua imagem muda sem você saber
- Em contexto sensível, pine por digest: `FROM node:20.11.1-slim@sha256:...`

### Non-root user

- Nunca rode como `root` em runtime — crie um usuário dedicado ou use o do runtime oficial (ex.: `USER node`)
- Ajuste ownership antes de mudar para non-root

```dockerfile
RUN addgroup --system --gid 1001 app && \
    adduser --system --uid 1001 --ingroup app app
COPY --chown=app:app . .
USER app
```

### Secrets

- Nunca use `ARG` ou `ENV` para secrets — ficam gravados nas camadas e aparecem em `docker history`
- Use BuildKit secrets com `--mount=type=secret`
- Variáveis de runtime (senhas de banco, tokens) passam via `docker run -e` ou gerenciador de secrets, nunca via Dockerfile

```dockerfile
# syntax=docker/dockerfile:1.7
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm ci
```

### Scan de vulnerabilidades

- Escaneie a imagem antes de publicar (`docker scout cves`, `trivy image`)
- CVE em base image se resolve atualizando a base, não remendando o app
- Base menor = menos CVEs: boa parte dos achados vem de pacotes do sistema que a app nunca usa

---

## Parte 3 — Docker Compose

### Estrutura base

- Use `compose.yaml` como nome padrão (Compose V2) — `docker-compose.yml` ainda funciona mas é legado
- Não declare `version:` — obsoleto no Compose V2
- Organize em blocos: `services`, `networks`, `volumes`, `configs`, `secrets`

```yaml
services:
  api:
    build: .
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/app
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16.2-alpine
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      retries: 10

volumes:
  db-data:
```

### depends_on com healthcheck

- `depends_on` simples apenas espera o container iniciar — não espera o serviço estar pronto
- Use `condition: service_healthy` para aguardar o healthcheck passar
- Todo serviço com dependências deve ter healthcheck declarado

### Healthchecks em serviços

- Healthcheck local (sem depender de rede externa) — `pg_isready`, `curl localhost`, `redis-cli ping`
- `start_period` suficiente para o serviço subir antes da primeira checagem começar a contar como falha

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres"]
  interval: 5s
  timeout: 3s
  retries: 10
  start_period: 10s
```

### profiles

- Use `profiles` para serviços opcionais (observability, seeders, ferramentas de dev) que não devem subir por padrão
- Ative com `docker compose --profile <name> up`

```yaml
services:
  app:
    image: myapp

  grafana:
    image: grafana/grafana
    profiles: ["observability"]
```

### Variáveis de ambiente

- `.env` na raiz é lido automaticamente — commitar `.env.example`, nunca `.env`
- Use interpolação `${VAR}` com default `${VAR:-default}` e obrigatório `${VAR:?mensagem}`
- Arquivos específicos por serviço via `env_file:`

```yaml
services:
  api:
    env_file:
      - .env.local
    environment:
      NODE_ENV: ${NODE_ENV:-development}
      DATABASE_URL: ${DATABASE_URL:?precisa estar definida}
```

### Volumes

- Named volumes para dados persistentes (bancos, filas) — `docker compose down` preserva por padrão
- Bind mounts para código em dev (hot reload) — não use em produção
- `:ro` para volumes que devem ser read-only

```yaml
services:
  api:
    volumes:
      - ./src:/app/src          # bind mount — hot reload em dev
      - /app/node_modules       # evita sobrescrever node_modules do container
      - configs:/app/configs:ro # named volume read-only
```

### Override pattern

- `compose.yaml` é o arquivo base — descreve o cenário comum
- `compose.override.yaml` é lido automaticamente e sobrescreve para dev (ports expostos, volumes bind, debug)
- `compose.prod.yaml` para produção, ativado com `-f compose.yaml -f compose.prod.yaml`

```yaml
# compose.yaml
services:
  api:
    image: myapp:${TAG:-latest}

# compose.override.yaml
services:
  api:
    build: .
    volumes:
      - ./src:/app/src
    ports:
      - "9229:9229"  # debug port
```

---

## Parte 4 — Validação de qualidade

Verifica o **artefato Docker** — build reproduz, imagem está sã, aplicação sobe e se sustenta. Não verifica a corretude do código: executar a suíte de testes do projeto é etapa anterior, de outra responsabilidade.

**A validação é não-invasiva:** não adiciona serviço ao `compose.yaml`, não cria arquivo de override, não altera nada no projeto. Observa o container de fora.

Todo o gate roda sob project name isolado — `PROJ="$(basename "$PWD")-qa"` — que é o que torna o `down -v` seguro.

### Quando executar — automático, sem esperar o pedido

O gate é **parte do trabalho, não um extra opcional**. Dispare-o no mesmo turno, sem perguntar antes, sempre que:

- criar ou alterar `Dockerfile`, `.dockerignore`, `compose.yaml` ou arquivo de override
- o usuário pedir revisão de artefatos Docker existentes — dizer "está bom" sem rodar o gate é palpite

Validar não é ação destrutiva: roda sob project name isolado e derruba tudo no `trap`. Só interrompa para perguntar se o gate precisar mexer em algo **fora** desse isolamento — parar um container do dev, liberar porta ocupada, apagar volume que não é da validação.

Quando um nível não puder rodar (daemon indisponível, build exige secret ausente, projeto sem `compose.yaml`), **reporte o nível como não executado com o motivo** e siga com os demais. Nunca silencie: nível omitido é lido como nível aprovado.

| # | Nível | Verificação | Falha |
|---|---|---|---|
| 1 | Lint | `hadolint` via container, com o `.hadolint.yaml` da skill | para |
| 2 | Build | Build do target final — se não constrói, nada mais importa | para |
| 3 | Inspeção | **Reprova:** `USER` root ou vazio, secret em `docker history`, `CMD`/`ENTRYPOINT` em forma shell, base `latest`. **Avisa:** tamanho, `HEALTHCHECK` ausente | para / avisa |
| 4 | Subida | `up -d --wait` — serviços atingem healthy no timeout | para |
| 5 | Sustentação | `RestartCount == 0` e `status == running` após ~30s | para |
| 6 | Resposta | `curl` **do host** na porta publicada → 2xx | condicional |
| — | Teardown | `down -v` no projeto isolado, em `trap`, inclusive em falha | sempre |

Fail-fast entre níveis.

**O nível 5 não é opcional.** `up -d --wait` retorna exit 0 e imprime `Healthy` para container em restart loop quando o serviço não declara `HEALTHCHECK` — comportamento verificado. Sem checar `RestartCount`, o gate aprova imagem que não roda.

**Aplicabilidade por projeto:**

| Natureza | Níveis |
|---|---|
| Serviço HTTP | 1–6 |
| Worker / consumer / cron | 1–5 (não expõe porta) |
| CLI / job batch | 1–3 + exit code 0 — critério invertido: container que termina é **sucesso** |
| Sem `compose.yaml` | 1–3 |

Comandos exatos, o `.hadolint.yaml` e as armadilhas de cada nível estão em `references/validacao-de-qualidade.md`.

### Relatório de criação e validação

A entrega ao usuário termina **sempre** com um relatório de duas partes. É ele que transforma "criei os arquivos" em "criei e provei que funcionam".

**Parte A — o que foi criado ou alterado.** Um item por arquivo, cada um carregando a decisão de projeto embutida: quantos stages e por quê, base escolhida, usuário de runtime, mecanismo do healthcheck, serviços do compose e como se ordenam. Nunca só "criei o Dockerfile".

**Parte B — o gate**, uma linha por nível:

| # | Nível | Resultado | Evidência |
|---|---|---|---|
| 1 | Lint | ✅ | hadolint exit 0, 0 findings |
| 2 | Build | ✅ | `--target runtime` ok, imagem 66 MB |
| 3 | Inspeção | ✅ | `USER=app`, forma exec, sem secret em `history`, base pinada |
| 4 | Subida | ✅ | app e db `healthy` |
| 5 | Sustentação | ✅ | `RestartCount=0`, `running` após 30s |
| 6 | Resposta | ✅ | `GET /` → 200 |
| — | Teardown | ✅ | `down -v`, `docker volume ls` idêntico antes/depois |

Regras do relatório:

- **Evidência, não adjetivo** — `RestartCount=0 após 30s`, não "container estável". O número é a prova; o adjetivo é opinião
- Nível **não aplicável** entra como `n/a` com a razão (`worker não expõe porta`) — não some da tabela
- Nível **não executado** entra como `⚠️ não executado` com o motivo
- Falha vem com a causa provável e o trecho de log ou comando que a evidencia, nunca só ❌
- Achados **fora do escopo Docker** encontrados no caminho (secret hardcoded no código, dependência de teste no requirements de produção) vão numa seção curta ao final, explicitamente marcados como **não corrigidos**
- Não anuncie aprovação sem a tabela — o relatório é a prova, não o resumo dela

---

## Anti-patterns

- `FROM <imagem>:latest` — imprevisibilidade, builds não reprodutíveis
- `COPY . .` antes dos manifestos de dependência — invalida cache a cada commit
- `COPY --from=builder /app /app` — copiar o diretório de build inteiro desfaz o multi-stage
- Stage final com compilador, gerenciador de pacotes ou código-fonte de linguagem compilada
- Stage extra (`lint`, `test`) que ninguém consome via `--target` — peso morto
- `RUN apt-get install` sem `rm -rf /var/lib/apt/lists/*` — infla layer
- Secrets em `ARG` ou `ENV` — gravados na história da imagem
- Rodar como root em runtime
- Healthcheck externo (curl para outro serviço) — falha em cascata durante incidentes
- `depends_on` sem `condition: service_healthy` quando há ordem real de inicialização
- `compose.yaml` com `version:` — obsoleto, gera warning
- Bind mount de `node_modules`/`.venv` do host para dentro do container — arquitetura do host pode diferir
- Adicionar serviço de teste ao `compose.yaml` do projeto só para validar — polui o artefato e valida uma configuração que não é a real
- Validar com `docker compose exec ... curl` — a imagem mínima que a skill manda construir não tem `curl` nem shell
- `docker compose down -v` sem project name isolado — apaga o volume de dados do desenvolvedor
- Tratar `up -d` bem-sucedido como aplicação funcionando — restart loop passa despercebido
- Entregar Dockerfile ou compose sem rodar o gate — "deve funcionar" não é validação
- Perguntar "quer que eu valide?" — o gate é isolado e não destrutivo, roda por padrão
- Relatar aprovação sem a tabela de evidências, ou omitir da tabela um nível que não rodou
