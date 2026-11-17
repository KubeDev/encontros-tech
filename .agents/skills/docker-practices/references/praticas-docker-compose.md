# Práticas de Docker Compose

> **Quando ler:** ao montar o ambiente local de uma app que depende de banco/Redis/fila. Quando o `docker compose up` "sobe" mas a app não responde. Ao separar cenários de dev e produção no mesmo projeto. Para entender por que `depends_on` simples não basta.

## Índice

1. [O que Compose resolve (e o que não resolve)](#o-que-compose-resolve-e-o-que-não-resolve)
2. [Anatomia de um compose.yaml comentado](#anatomia-de-um-composeyaml-comentado)
3. [`depends_on` simples vs `condition: service_healthy`](#depends_on-simples-vs-condition-service_healthy)
4. [Healthcheck: o que faz e como projetar um bom](#healthcheck-o-que-faz-e-como-projetar-um-bom)
5. [Override pattern: dev vs prod no mesmo projeto](#override-pattern-dev-vs-prod-no-mesmo-projeto)
6. [Volumes: bind mount vs named volume](#volumes-bind-mount-vs-named-volume)
7. [Profiles: serviços opcionais](#profiles-serviços-opcionais)
8. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## O que Compose resolve (e o que não resolve)

Docker Compose é uma ferramenta para **orquestrar múltiplos containers em um único host** — geralmente sua máquina de desenvolvimento. Resolve:

- Subir vários containers com um comando (`docker compose up`)
- Fazer eles se enxergarem por DNS interno (`api` consegue conectar em `db` por nome)
- Gerenciar volumes e redes consistentes
- Reproduzir o mesmo ambiente entre máquinas do time (todo mundo no mesmo `compose.yaml`)

**Não resolve:**

- Orquestração em produção (use Kubernetes, Nomad, ECS, Swarm)
- Auto-scaling, rolling updates, self-healing avançado
- Multi-host (Compose roda tudo num host só)

Para iniciante, o uso correto é: **Compose = ambiente local de desenvolvimento**. Em produção é outra ferramenta.

## Anatomia de um compose.yaml comentado

```yaml
services:
```

A unidade central do Compose. Cada serviço corresponde a um container (ou grupo, com `replicas`).

```yaml
  api:
    build: .
```

`build: .` instrui o Compose a construir uma imagem a partir do `Dockerfile` no diretório atual antes de subir. Alternativa: `image: meuapp:dev` para usar imagem já pronta.

```yaml
    ports:
      - "3000:3000"
```

Mapeia porta do host para porta do container. Formato: `"host:container"`. Em dev, expor portas é ok. Em produção, geralmente só o reverse proxy expõe.

```yaml
    environment:
      DATABASE_URL: postgres://postgres:postgres@db:5432/app
      NODE_ENV: development
```

Variáveis injetadas no container. Note que o host do banco é `db` — o nome do serviço — não `localhost`. DNS interno do Compose resolve isso.

```yaml
    depends_on:
      db:
        condition: service_healthy
```

Faz o serviço `api` esperar o serviço `db` estar **saudável** antes de subir. Veja seção dedicada — isso é uma das partes mais mal entendidas do Compose.

```yaml
    volumes:
      - ./src:/app/src
      - /app/node_modules
```

- `./src:/app/src` — bind mount: o código local entra no container. Hot reload funciona.
- `/app/node_modules` — anonymous volume: protege o `node_modules` do container de ser sobrescrito pelo bind mount do código.

```yaml
  db:
    image: postgres:16.2-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: app
    volumes:
      - db-data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s
```

- `image:` em vez de `build:` — imagem oficial direto.
- `db-data:/var/lib/postgresql/data` — named volume. Persiste entre `docker compose down`/`up`.
- `healthcheck:` — define o que significa "saudável" para esse serviço. Veja seção dedicada.

```yaml
volumes:
  db-data:
```

Declaração de named volumes na raiz. Se você não declarar aqui, o serviço falha ao iniciar.

## `depends_on` simples vs `condition: service_healthy`

Erro mais comum de iniciante em Compose:

```yaml
services:
  api:
    build: .
    depends_on:
      - db   # ← isso só espera o CONTAINER iniciar, não o serviço estar pronto
  db:
    image: postgres:16
```

O que acontece:

1. Compose sobe o container `db`.
2. Postgres começa a inicializar (cria diretório, sobe processo, abre socket — leva 3-5 segundos).
3. Compose vê o **container** rodando e sobe o `api`.
4. App tenta `psql -h db` na primeira instrução: **conexão recusada** — Postgres ainda não terminou de subir.
5. App falha com erro de conexão.

`depends_on:` simples (lista) só garante **ordem de criação de container** — não garante que o serviço dentro dele está pronto.

### A versão correta:

```yaml
services:
  api:
    build: .
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 3s
      retries: 10
      start_period: 10s
```

Agora:

1. Compose sobe `db` e roda `pg_isready` a cada 5s.
2. Postgres inicializa.
3. `pg_isready` retorna sucesso.
4. Container fica `healthy`.
5. **Só agora** Compose sobe o `api`.

A regra de ouro: **todo serviço que tem dependentes precisa ter `healthcheck`**. Sem healthcheck, `condition: service_healthy` não funciona (status fica `none`).

### Outras condições

| Condition | Quando usar |
|---|---|
| `service_started` | Equivalente a depends_on lista (default) — só ordem |
| `service_healthy` | Espera healthcheck passar — o que você quer 99% dos casos |
| `service_completed_successfully` | Para serviços one-shot (migrations) — espera exit 0 |

Padrão de migration:

```yaml
services:
  migrate:
    build: .
    command: ["npm", "run", "migrate"]
    depends_on:
      db:
        condition: service_healthy

  api:
    build: .
    depends_on:
      migrate:
        condition: service_completed_successfully
```

## Healthcheck: o que faz e como projetar um bom

Healthcheck é um comando que o Docker roda periodicamente dentro do container. Se passa (exit 0), container está `healthy`. Se falha (exit ≠ 0) por mais que `retries` vezes, fica `unhealthy`.

### Anatomia

```yaml
healthcheck:
  test: ["CMD-SHELL", "pg_isready -U postgres"]
  interval: 5s         # de quanto em quanto tempo testar
  timeout: 3s          # tempo máximo do comando antes de considerar falha
  retries: 10          # quantas falhas seguidas antes de virar unhealthy
  start_period: 10s    # tempo inicial em que falhas NÃO contam
```

`start_period` é a parte que iniciante esquece. Sem ela, durante os primeiros 5s o serviço falha o healthcheck (porque ainda nem subiu) e o contador `retries` começa a estourar antes de o serviço ter chance.

### Boa prática: healthcheck local

Healthcheck deve verificar **o serviço local**, não dependências externas:

| Bom | Ruim |
|---|---|
| `pg_isready` no Postgres | `pg_isready -h outraDB` no Postgres |
| `curl localhost:3000/health` na sua API | `curl outraAPI/health` na sua API |
| `redis-cli ping` no Redis | `redis-cli -h outroRedis ping` |

Por quê? Se sua API depender de outra API no healthcheck, e a outra API ficar instável, **a sua também fica `unhealthy`** — em cascata. Em produção, isso vira disrupção de serviço múltiplo.

### Healthcheck em apps que você está desenvolvendo

Crie um endpoint `/health` (ou `/livez`) que:

1. Responde 200 se o processo está vivo
2. **Não** verifica banco/cache/serviços externos (deixe isso para `/readyz`, se separar)
3. É leve — não loga, não faz query, retorna em <100ms

```yaml
api:
  build: .
  healthcheck:
    test: ["CMD", "curl", "-fsS", "http://localhost:3000/health"]
    interval: 10s
    timeout: 3s
    retries: 3
    start_period: 30s
```

Se sua imagem não tem `curl` (por ex. distroless), use o runtime da linguagem:

```yaml
test: ["CMD", "node", "-e", "require('http').get('http://localhost:3000/health', r => process.exit(r.statusCode === 200 ? 0 : 1))"]
```

## Override pattern: dev vs prod no mesmo projeto

Você tem um `compose.yaml` que descreve o cenário base. Para ajustes específicos por ambiente, use **override files**.

### Convenção do Compose

| Arquivo | Lido automaticamente? |
|---|---|
| `compose.yaml` | Sim, sempre |
| `compose.override.yaml` | Sim, automaticamente, em cima do base |
| `compose.prod.yaml` (ou outro nome) | Não — precisa de `-f` explícito |

### Padrão útil

`compose.yaml` (base — sem decisões de ambiente):

```yaml
services:
  api:
    image: myapp:${TAG:-dev}
    environment:
      NODE_ENV: ${NODE_ENV:-development}
  db:
    image: postgres:16-alpine
    volumes:
      - db-data:/var/lib/postgresql/data

volumes:
  db-data:
```

`compose.override.yaml` (lido auto em dev — adiciona o que dev precisa):

```yaml
services:
  api:
    build: .                       # dev builda local
    volumes:
      - ./src:/app/src             # hot reload
      - /app/node_modules
    ports:
      - "3000:3000"
      - "9229:9229"                # debug port
    environment:
      DEBUG: "*"
  db:
    ports:
      - "5432:5432"                # expor pra IDE conectar
```

`compose.prod.yaml` (não lido auto — usado com `-f`):

```yaml
services:
  api:
    image: myregistry.io/myapp:${TAG}
    restart: unless-stopped
    deploy:
      replicas: 3
```

Uso em produção:

```bash
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

### Por que essa estrutura é elegante

- O `compose.yaml` base é minimal e sem opinião de ambiente.
- Devs no time não precisam fazer nada — `docker compose up` lê o override automaticamente.
- Produção é explícita — quem rodar precisa passar `-f compose.prod.yaml` deliberadamente.
- Não há `if env == "dev"` espalhado no compose.

## Volumes: bind mount vs named volume

| Tipo | Sintaxe | Persistência | Uso típico |
|---|---|---|---|
| **Bind mount** | `./src:/app/src` | Mapeia diretório do host | Código em dev (hot reload) |
| **Named volume** | `db-data:/var/lib/...` | Gerenciado pelo Docker | Dados persistentes (banco, fila) |
| **Anonymous volume** | `/app/node_modules` | Gerenciado pelo Docker, sem nome | Proteger pasta dentro do container |
| **`tmpfs`** | `tmpfs: /tmp` | RAM (não persiste) | Cache temporário sensível |

### Por que `node_modules` precisa de tratamento especial

Cenário comum: você faz bind mount do código e o `node_modules` do container some.

```yaml
volumes:
  - ./:/app           # ← bind mount monta tudo
```

O que acontece:

1. Imagem foi construída com `node_modules` em `/app/node_modules` (cheio, com binários compilados para Linux).
2. Bind mount monta `./` do host por cima de `/app`. Seu host **não tem** `node_modules` (você está em Mac/Windows).
3. Container vê `/app/node_modules` vazio. App quebra.

Solução: anonymous volume mais específico **depois** do bind mount:

```yaml
volumes:
  - ./:/app
  - /app/node_modules    # ← preserva o que veio da imagem
```

A ordem importa: o anonymous volume tem precedência sobre o bind mount no path mais específico.

### `:ro` para read-only

Volumes podem ser montados read-only:

```yaml
volumes:
  - ./configs:/app/configs:ro
```

Útil quando o container não deve modificar — configs, fontes, certificados.

### Bind mount em produção: evite

Em produção, bind mount amarra você ao filesystem do host. Você não consegue mover o container para outro nó sem replicar o filesystem. Use named volumes (com driver de storage que persiste em rede) ou volumes externos do orquestrador.

## Profiles: serviços opcionais

Cenário: o `compose.yaml` tem o app + banco. Mas você também tem Grafana, Jaeger, MailHog que só sobem quando você está debugando observability ou email. Não quer eles subindo sempre.

```yaml
services:
  api:
    build: .

  db:
    image: postgres:16

  grafana:
    image: grafana/grafana
    profiles: ["observability"]

  mailhog:
    image: mailhog/mailhog
    profiles: ["email-dev"]
```

Por padrão, `docker compose up` sobe só `api` e `db`.

Para ativar profile:

```bash
docker compose --profile observability up
```

Para múltiplos:

```bash
docker compose --profile observability --profile email-dev up
```

Vantagem sobre comentários: tudo está no mesmo arquivo, descoberta é fácil, devs novos veem que existem mas só sobem quando precisam.

## Erros comuns de iniciante

### "Sobe tudo, mas a API conecta antes do banco estar pronto"

Use `condition: service_healthy` e healthcheck no banco. `depends_on` simples não basta.

### "Mudei o código mas o container não atualizou"

- Falta bind mount do código em dev (`./src:/app/src`)
- Você está usando `image:` em vez de `build:` — imagem velha está em cache
- O processo dentro do container não tem hot reload (rodar `npm run dev` em vez de `node dist`)

### "Roda em Linux, não roda em Mac/Windows"

- Bind mount em Mac/Windows tem performance pior (overlay filesystem). Use volumes nomeados quando possível para hot paths.
- Caminhos absolutos do host quebram entre OSes. Use caminhos relativos no `compose.yaml`.

### "Reiniciei e o banco perdeu os dados"

- Você não declarou volume nomeado, ou declarou bind mount para um diretório que não existe entre os runs.
- Conferir: `docker compose down` (sem `-v`) preserva volumes nomeados. `docker compose down -v` apaga.

### "Coloquei `version: '3.8'` no topo mas dá warning"

`version:` é obsoleto no Compose V2 (2022+). Apague a linha.

### ".env do projeto vaza credenciais"

`.env` é lido automaticamente pelo Compose para interpolação. Adicione `.env` ao `.gitignore`. Comite `.env.example` com placeholders.

### "Container roda mas não consegue conectar no host"

De dentro do container, `localhost` é o **próprio container**, não a sua máquina. Para acessar o host:

- Linux: `host.docker.internal` (precisa de configuração) ou IP da bridge
- Mac/Windows: `host.docker.internal` funciona out of the box

---

**Princípio que resume tudo:** Compose é um simulador de produção em pequena escala. Quanto mais você usar healthchecks, depends_on com condition, named volumes e profiles bem desenhados, mais o seu dev imita produção e menos surpresas você tem na hora do deploy.
