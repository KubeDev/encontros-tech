# Por que multi-stage e camadas

> **Quando ler:** ao escrever um Dockerfile do zero, ao tentar entender por que um build está lento ou uma imagem está enorme, ao revisar Dockerfile de outra pessoa e algo "parece ruim mas você não sabe explicar o porquê".

## Índice

1. [O modelo mental: imagem como pilha de camadas](#o-modelo-mental-imagem-como-pilha-de-camadas)
2. [Cache: por que a ordem das instruções importa](#cache-por-que-a-ordem-das-instruções-importa)
3. [O problema que multi-stage resolve](#o-problema-que-multi-stage-resolve)
4. [Arquitetura de stages: decidindo o desenho](#arquitetura-de-stages-decidindo-o-desenho)
5. [Anatomia comentada de um Dockerfile multi-stage](#anatomia-comentada-de-um-dockerfile-multi-stage)
6. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## O modelo mental: imagem como pilha de camadas

Uma imagem Docker não é "um arquivo grande com tudo dentro". É **uma pilha de camadas read-only empilhadas** — cada instrução do Dockerfile que altera o filesystem (`RUN`, `COPY`, `ADD`) cria uma camada nova.

Pense em transparências de retroprojetor: cada uma carrega um pedaço da imagem final, e o que você "vê" é a soma de todas empilhadas.

Por que isso importa?

- **Reaproveitamento entre builds.** Se a camada já existe no cache local (ou no registry, com BuildKit), o Docker pula a execução e usa a camada pronta. Builds que demoravam 5 minutos passam a demorar 5 segundos.
- **Reaproveitamento entre imagens.** Se você tem 10 imagens que partem do mesmo `FROM node:20-slim`, essa camada é baixada uma vez só, mesmo que cada imagem use.
- **Você não consegue "deletar" da história.** Se uma camada anterior copiou um secret, ele continua lá no histórico mesmo que a camada seguinte o apague. Por isso `ARG SECRET=...` é proibido em build.

```
┌─────────────────────────────┐
│ Camada N: CMD ["node"...]   │  ← topo (sua app)
├─────────────────────────────┤
│ Camada N-1: COPY dist/      │
├─────────────────────────────┤
│ Camada N-2: RUN npm ci      │
├─────────────────────────────┤
│ Camada N-3: COPY package*   │
├─────────────────────────────┤
│ Camada base: node:20-slim   │  ← FROM
└─────────────────────────────┘
```

## Cache: por que a ordem das instruções importa

A regra fundamental do cache do Docker:

> Quando uma camada é invalidada, **todas as camadas acima dela** também são invalidadas.

Isso é cascata. Não é "o Docker recompila só o que mudou" — é "qualquer mudança em uma camada força refazer tudo dali pra cima".

### Exemplo: o pecado clássico

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY . .             # ← qualquer mudança em qualquer arquivo invalida aqui
RUN npm ci           # ← então npm ci roda DE NOVO toda vez
RUN npm run build
CMD ["node", "dist/index.js"]
```

Você muda uma vírgula no `README.md`. O cache do `COPY . .` é invalidado. O `npm ci` roda de novo. O build leva 3 minutos. Repete-se a cada commit.

### A versão correta

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY package*.json ./   # ← muda só quando dependências mudam
RUN npm ci              # ← cacheado se package*.json não mudou
COPY . .                # ← essa camada invalida com qualquer mudança...
RUN npm run build       # ← ...mas npm ci já passou
CMD ["node", "dist/index.js"]
```

Agora `npm ci` só roda quando `package.json` ou `package-lock.json` mudam. No dia-a-dia, isso significa builds de segundos em vez de minutos.

### A heurística que vale para qualquer linguagem

> **Coisas que mudam pouco vão primeiro. Coisas que mudam muito vão por último.**

| Posição no Dockerfile | O que coloca | Frequência de mudança |
|---|---|---|
| Topo (próximo do FROM) | Pacotes do sistema, ferramentas de build | Mensal/raro |
| Meio | Manifestos de dependência (`package.json`, `requirements.txt`, `go.sum`) | A cada nova lib |
| Meio-baixo | Instalação das dependências (`npm ci`, `pip install`, `go mod download`) | Junto com manifesto |
| Baixo | Código-fonte (`COPY . .`) | A cada commit |
| Final | Build do código (`npm run build`) | A cada commit |

## O problema que multi-stage resolve

Antes do multi-stage builds (introduzido no Docker 17.05, em 2017), você tinha duas opções ruins:

**Opção A — uma imagem só, com tudo dentro:**

```dockerfile
FROM node:20
WORKDIR /app
COPY package*.json ./
RUN npm ci                     # instala TUDO, inclusive devDependencies
COPY . .
RUN npm run build
CMD ["node", "dist/index.js"]
```

Resultado: imagem final com `node_modules` inteiro (incluindo TypeScript, ESLint, Jest), código-fonte, ferramentas de build. Tamanho final: 1.5 GB. Em produção, você está carregando o compilador para rodar o que poderia ser só `node dist/index.js`.

**Opção B — dois Dockerfiles, scripts colando os dois:**

Você fazia o build em uma imagem, copiava o resultado para fora com `docker cp`, e copiava para dentro de outra imagem mais enxuta. Frágil, difícil de reproduzir, indecente em CI.

**Multi-stage é a solução elegante:**

> Use estágios diferentes no MESMO Dockerfile. Um para construir, outro para rodar. Copie só o necessário entre eles.

```dockerfile
# Estágio 1 — builder. Pode ter tudo: compiladores, devDeps, ferramentas.
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Estágio 2 — runtime. Só o que precisa para rodar.
FROM node:20-slim AS runtime
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package*.json ./
USER node
CMD ["node", "dist/index.js"]
```

A imagem **final** é só o estágio `runtime`. O estágio `builder` é jogado fora — você não paga o preço dele em produção.

Resultado típico: imagem final cai de 1.5 GB para 200 MB. Em alguns casos (Go, Rust com distroless), cai para 20 MB.

### O que você ganha de verdade com multi-stage

| Ganho | Por quê |
|---|---|
| **Imagem menor** | DevDeps, compiladores e código-fonte ficam no estágio descartado |
| **Mais segura** | Menos software = menos CVEs. Sem `gcc` em produção, sem `npm` para um atacante usar |
| **Pull mais rápido** | Pods Kubernetes sobem mais rápido. Cold start de Lambda menor |
| **Separação de responsabilidades** | Cada estágio tem um propósito claro |

## Arquitetura de stages: decidindo o desenho

Saber *como* multi-stage funciona não responde às perguntas práticas: preciso disso no meu projeto? quantos stages? o que copio de um para o outro? São três decisões independentes.

### Eixo 1 — vale a pena aqui?

O ganho de multi-stage não depende da linguagem, e sim de **quanto o artefato final difere do que foi preciso para produzi-lo**. Onde essa distância é grande, o ganho é grande.

| Natureza do artefato | Vale? | Ganho e por quê |
|---|---|---|
| Compilada (Go, Rust, C#, Java) | Obrigatório | Enorme. O binário não precisa de nada do toolchain — runtime pode ser distroless ou até `scratch`. 1 GB → 20 MB |
| Transpilada (TS, bundlers, Sass) | Obrigatório | Grande. Sai o toolchain inteiro e as devDependencies; fica o `dist/` |
| Interpretada com extensões C (`psycopg2`, `node-gyp`, `nokogiri`) | Sim | Médio. Sai o `build-essential`, fica o código. A economia é o compilador, não a aplicação |
| Interpretada pura (Python puro, PHP) | Opcional | Pequeno. Só evita cache do pip/composer. Single-stage sobre base slim é honesto aqui |
| Assets estáticos → nginx | Obrigatório | O caso clássico: Node constrói, nginx serve. Zero Node na imagem final |

A linha das extensões C tem uma armadilha própria: os `.so` compilados no builder só carregam no runtime se **os dois stages usarem a mesma libc**. Compilar num `python:3.12-slim` (glibc) e copiar para um `python:3.12-alpine` (musl) produz um `ImportError` em runtime que não aparece no build. Veja `escolhendo-base-image.md`.

### Eixo 2 — quantos stages?

**Dois (builder + runtime) é o default.** Resolve o problema central e é o que a maioria dos projetos precisa. Não invente um terceiro sem conseguir nomear o problema que ele resolve.

**Três (deps + build + runtime)** quando dependências e código mudam em ritmos diferentes:

```dockerfile
# Stage 1 — só dependências. Muda quando o package.json muda: raramente.
FROM node:20.11.1-slim AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

# Stage 2 — build. Muda a cada commit: o tempo todo.
FROM node:20.11.1-slim AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

# Stage 3 — runtime. Só o resultado.
FROM node:20.11.1-slim AS runtime
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY --from=build /app/dist ./dist
USER node
CMD ["node", "dist/index.js"]
```

O ganho é de cache: com o `npm ci` isolado num stage que só depende do `package*.json`, mudar código-fonte não toca o stage `deps`. Em dois stages você consegue quase o mesmo com ordem de instruções — a diferença aparece quando mais de um stage consome as mesmas dependências, como acima.

**Stages extras** (`lint`, `docs`) só se justificam quando algo externo os consome via `--target`:

```bash
docker build --target lint .
```

Se ninguém chama esse alvo, o stage é peso morto: mais Dockerfile para ler, mais coisa para manter desatualizada. Um stage não consumido é comentário que finge ser código.

Cada stage custa legibilidade. A pergunta é sempre: *que problema concreto este stage resolve?*

### Eixo 3 — o que atravessa o `COPY --from`

Só o artefato e as dependências de runtime. Nunca o diretório de build inteiro:

```dockerfile
# Ruim — traz de volta tudo o que o multi-stage tinha descartado
COPY --from=builder /app /app

# Bom — só o que roda
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
```

O primeiro é o erro mais frustrante de multi-stage: o Dockerfile *parece* correto — tem dois stages, tem `COPY --from` — e a imagem final continua enorme, porque um `COPY` genérico desfez todo o trabalho.

### A heurística de parada

> Se o stage final contém algo que você não executaria em produção — compilador, gerenciador de pacotes, suíte de testes, código-fonte de linguagem compilada — falta um stage. Se você não sabe explicar por que um arquivo está na imagem final, ele não deveria estar.

É a mesma pergunta que o nível 3 do gate de `validacao-de-qualidade.md` faz de forma automatizada.

## Anatomia comentada de um Dockerfile multi-stage

Vamos ler um Dockerfile real linha por linha. App Node.js + TypeScript.

```dockerfile
# syntax=docker/dockerfile:1.7
```

Habilita features modernas do BuildKit (mounts de cache, secrets, plataformas múltiplas). É boa prática colocar sempre.

```dockerfile
FROM node:20.11.1-slim AS builder
```

- `node:20.11.1-slim` — versão pinada (não `20`, não `latest`). Reproduz o build daqui a 6 meses.
- `slim` — variante baseada em Debian slim. Menor que a default, sem ser `alpine` (que tem incompatibilidade com algumas libs Node por usar musl).
- `AS builder` — nomeia o estágio. Vamos referenciar mais à frente.

```dockerfile
WORKDIR /app
```

Define o diretório de trabalho. Equivale a `mkdir -p /app && cd /app`. Daqui pra frente, todos os caminhos relativos são a partir de `/app`.

```dockerfile
COPY package*.json ./
```

Copia só os manifestos. **Antes** do código. Por causa do cache em cascata.

```dockerfile
RUN npm ci
```

`npm ci` (não `npm install`) — instala exatamente o que está no `package-lock.json`. Determinístico. Falha se o lock está desatualizado. Perfeito para builds.

```dockerfile
COPY . .
RUN npm run build
```

Agora sim, copia o resto e roda o build. Se só o código mudou, as camadas anteriores estão em cache.

```dockerfile
FROM node:20.11.1-slim AS runtime
```

Começa o estágio final. Mesma base do builder (consistência), mas vai conter coisas diferentes.

```dockerfile
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
COPY package*.json ./
```

`--from=builder` — copia do estágio `builder`. Pega só o que precisa para rodar:
- `dist/` — código compilado
- `node_modules/` — dependências (poderíamos refinar com `npm ci --omit=dev`, mas vamos deixar simples)
- `package*.json` — para o Node achar o `main` e os metadados

Note que **nenhum arquivo `.ts`, nenhum config de eslint/jest, nenhum README** entrou na imagem final.

```dockerfile
USER node
```

Muda para o usuário não-root `node`, que já existe na imagem oficial. Nunca rode como root em runtime.

```dockerfile
CMD ["node", "dist/index.js"]
```

Forma exec (array), não forma shell. Garante que sinais (SIGTERM no `kubectl delete pod`) cheguem direto ao processo Node, e ele consiga fazer graceful shutdown.

## Erros comuns de iniciante

### "Por que minha imagem Python tá com 1.5 GB?"

Provavelmente você usou `FROM python:3.12` (a default, baseada em Debian completa) e não fez multi-stage. A imagem default vem com gcc, build-essential, headers — tudo para compilar pacotes que precisam de extensão C. Em produção, você não compila nada.

Solução: `python:3.12-slim` para runtime, e use `python:3.12` (cheia) só no estágio builder se precisar de compilação.

### "Mudei uma linha do código e o build levou 5 minutos"

Você está com `COPY . .` antes de `RUN npm ci` (ou equivalente). Cache em cascata invalida tudo a cada commit.

### "Adicionei `RUN apt-get install` e a imagem ficou enorme"

Você esqueceu de limpar o cache do apt na mesma camada:

```dockerfile
# Ruim — cache do apt fica gravado na camada
RUN apt-get update && apt-get install -y curl

# Bom — cache não persiste
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl ca-certificates && \
    rm -rf /var/lib/apt/lists/*
```

Por que `&&` em vez de `RUN` separados? Porque cada `RUN` cria uma camada. Se você fizer `RUN apt-get update` em uma camada e `RUN rm -rf ...` em outra, o cache do apt já foi gravado na camada anterior — apagar depois não diminui o tamanho.

### "Coloquei meu .env no Dockerfile e funcionou"

Funcionou em dev. Em produção, você acabou de gravar suas credenciais na imagem, que vai pra um registry, que talvez seja público, que com certeza tem mais gente com acesso de leitura do que você imagina. Use variáveis em runtime (`docker run -e`, `env_file:` no Compose, Secret no K8s) — nunca em build.

### "Por que `CMD bash -c 'node app.js'` não recebe SIGTERM?"

Forma shell vira `/bin/sh -c "bash -c 'node app.js'"`. O shell é PID 1, não o Node. Quando o orquestrador manda SIGTERM, o shell recebe e ignora. Use forma exec: `CMD ["node", "app.js"]`.

---

**Princípio que une tudo:** o Dockerfile não é só um script de instalação. É a especificação de uma imagem que vai rodar em produção, ser puxada centenas de vezes por dia, e talvez ser auditada. Cada decisão (ordem das camadas, multi-stage, `USER`, forma exec) tem motivo prático observável.
