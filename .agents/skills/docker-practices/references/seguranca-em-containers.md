# Segurança em containers

> **Quando ler:** antes de subir uma imagem para produção pela primeira vez. Ao revisar Dockerfile alheio. Quando alguém menciona "scan de imagem", "supply chain" ou "CVE" e você não sabe o que se espera de você.

## Índice

1. [Modelo mental: o que pode dar errado](#modelo-mental-o-que-pode-dar-errado)
2. [Por que `USER root` em runtime é problema](#por-que-user-root-em-runtime-é-problema)
3. [Secrets: o que não fazer e o que fazer](#secrets-o-que-não-fazer-e-o-que-fazer)
4. [Supply chain: de onde vem sua imagem](#supply-chain-de-onde-vem-sua-imagem)
5. [Scans de vulnerabilidade: o que esperar](#scans-de-vulnerabilidade-o-que-esperar)
6. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## Modelo mental: o que pode dar errado

Container não é uma sandbox de verdade. É um **processo Linux com namespaces e cgroups isolados**, mas dividindo o mesmo kernel do host. Isso significa:

- Se sua app é comprometida (RCE), o atacante começa **dentro** do container, mas tem todas as ferramentas que estiverem na imagem.
- Se o container roda como root, e o atacante consegue um *container escape* (raro, mas existe), ele vira root no host.
- Tudo que está na imagem (incluindo histórico de camadas) é potencialmente exposto se o registry for público ou tiver leitura ampla.

A pergunta certa não é "como impedir invasão" — é **"se invadirem, qual o impacto?"**. Cada decisão de segurança no Dockerfile reduz esse impacto.

| Risco | Sintoma | Mitigação |
|---|---|---|
| Atacante usa ferramentas da imagem | RCE consegue rodar `nmap`, `curl`, `bash` | Imagem mínima (slim/distroless), sem ferramentas extras |
| Privilege escalation | Atacante vira root no container, depois no host | `USER` não-root, `allowPrivilegeEscalation: false` |
| Secrets vazados | Token publicado em registry público, em logs, em camadas | Nunca em `ARG`/`ENV`. Usar BuildKit secrets ou injeção em runtime |
| Imagem maliciosa | Você puxou `nginx:latest` e veio crypto miner | Pinning por SHA, registry interno, scan |
| Vulnerabilidade conhecida | CVE em libssl da base | Atualizar base regularmente, scan automático em CI |

## Por que `USER root` em runtime é problema

Por default, processos dentro de um container rodam como `root` do container. Isso é confortável (sem `permission denied`), mas perigoso:

- `root` no container **é o mesmo UID 0 do host**, separado por namespaces. Se o namespacing falhar (vulnerabilidade do kernel, configuração errada), root é root.
- Atacante que comprometer a app pode escrever em `/etc`, instalar pacotes, persistir.
- Compliance (PCI, SOC2) costuma exigir non-root.

### Como mudar para non-root

Imagens oficiais geralmente já criam um usuário (`node`, `nginx`, `postgres`). Use ele:

```dockerfile
FROM node:20-slim
WORKDIR /app
COPY --chown=node:node . .   # ajusta dono ANTES de mudar para non-root
RUN npm ci
USER node                     # daqui pra frente, processos rodam como node
CMD ["node", "index.js"]
```

Quando a base não tem user pronto:

```dockerfile
FROM debian:12-slim
RUN groupadd --system --gid 1001 app && \
    useradd --system --uid 1001 --gid app --no-create-home app
WORKDIR /app
COPY --chown=app:app . .
USER app
CMD ["./server"]
```

### Por que `--chown` importa

Se você fizer `COPY . .` antes de `USER app` sem `--chown`, os arquivos ficam com dono `root:root`. Quando o processo `app` tentar escrever no diretório (logs, cache, uploads), vai falhar com `permission denied`. Você vai descobrir isso em produção, às 3h da manhã.

### Quando o app precisa de root para subir

Casos legítimos: bind em porta < 1024 (ex: `:80`). Soluções:

- Use porta alta no container (`:8080`) e mapeie no orquestrador
- Use `setcap CAP_NET_BIND_SERVICE=+ep /usr/bin/myapp` no Dockerfile, então `USER app`
- Em K8s, prefira ouvir em porta alta — Service mapeia 80 → 8080

## Secrets: o que não fazer e o que fazer

### O pecado mortal: `ARG` ou `ENV` para secret em build

```dockerfile
# NUNCA FAÇA ISSO
ARG NPM_TOKEN
RUN npm config set //registry.npmjs.org/:_authToken $NPM_TOKEN && npm ci
```

Por que é problema:
- `ARG` fica gravado no histórico da imagem. `docker history` mostra. `docker inspect` mostra.
- Se a imagem vai pra um registry e alguém puxa, ele tem o token.
- Mesmo apagar em camadas seguintes não remove — camadas são imutáveis.

Esse erro já vazou tokens de produção em registries públicos várias vezes. Não exagero — é um dos vazamentos mais comuns.

### O caminho certo: BuildKit secrets

BuildKit (habilitado com `# syntax=docker/dockerfile:1.x` no topo) suporta mounts de secret em build, que **não persistem em nenhuma camada**:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM node:20-slim
WORKDIR /app
COPY package*.json ./
RUN --mount=type=secret,id=npm_token \
    npm config set //registry.npmjs.org/:_authToken $(cat /run/secrets/npm_token) && \
    npm ci && \
    npm config delete //registry.npmjs.org/:_authToken
```

Build:

```bash
docker build --secret id=npm_token,env=NPM_TOKEN -t myapp .
```

O secret está disponível durante o `RUN` em `/run/secrets/npm_token`, mas sai da camada quando o `RUN` termina.

### Secrets em runtime: nunca no Dockerfile

Senha de banco, token de API, chave privada — esses **não devem aparecer em nenhum lugar** do Dockerfile. Eles entram quando o container roda:

| Origem | Como passar | Use quando |
|---|---|---|
| Variável de ambiente | `docker run -e DATABASE_URL=...` | Dev local, prototipagem |
| `env_file:` no Compose | Arquivo `.env` não-commitado | Dev local |
| Secret manager do orquestrador | K8s `Secret` montado, AWS Secrets Manager, Vault | Produção |
| Sidecar ou init container | Vault Agent, AWS Parameter Store agent | Quando rotação automática importa |

### Como saber se um secret vazou na imagem

```bash
docker history myapp:latest --no-trunc
docker inspect myapp:latest | grep -A 50 "Env\|Cmd"
```

Procure por strings que parecem token (`ghp_`, `sk-`, valores Base64 longos, JWTs).

Para auditar de verdade, use `dive` (`brew install dive`) — abre cada camada e mostra o que entrou/saiu.

## Supply chain: de onde vem sua imagem

Quando você faz `FROM node:20`, está confiando em:

1. **Docker Hub** (ou registry que você usar) — não foi sequestrado
2. **Mantenedor da imagem `node`** (Node.js Foundation) — não publicou imagem maliciosa
3. **Cadeia de pacotes na imagem** — Debian/Alpine não foi comprometido na origem
4. **Tag não foi movida** desde que você testou — sem pinning por SHA, isso pode acontecer

Cada uma dessas pontas já foi atacada na vida real (2022-2024 teve casos públicos em todas).

### Defesas práticas para iniciantes

| Prática | Por quê | Custo |
|---|---|---|
| Use **imagens oficiais** ou de fornecedores reconhecidos (Microsoft, Bitnami, Chainguard, Google) | Reduz risco de imagem maliciosa | Zero |
| **Pin por SHA** em workloads sensíveis (`FROM node@sha256:abc...`) | Tag não pode ser movida sem você saber | Pequeno — Renovate/Dependabot mantêm atualizado |
| **Registry interno como espelho** | Pegada de pull controlada, scan automático | Médio — exige infra |
| **Renovate/Dependabot** para atualizar base regularmente | CVEs novos são descobertos toda semana | Pequeno — config inicial |
| **Cosign / sigstore** para verificar assinatura | Garantia criptográfica de origem | Médio — exige adoção do time |

### O que iniciante deve fazer no mínimo

1. Sempre tag pinada (`node:20.11.1-slim`, não `node:20` nem `node:latest`).
2. Imagens só de fornecedores reconhecidos.
3. Em CI, rode um scan (próxima seção) e bloqueie se aparecer CVE crítico/alto.

Isso já cobre 90% dos riscos práticos.

## Scans de vulnerabilidade: o que esperar

Ferramentas como **Trivy**, **Grype**, **Snyk**, **Docker Scout** abrem sua imagem, extraem a lista de pacotes (Debian/Alpine/wheels Python/dependências npm) e cruzam com bancos de CVE públicos.

Saída típica:

```
nginx:1.23.4-alpine (alpine 3.17.0)
═══════════════════════════════════
Total: 12 (UNKNOWN: 0, LOW: 5, MEDIUM: 4, HIGH: 2, CRITICAL: 1)

CRITICAL  CVE-2023-12345  openssl  3.0.7-r0  →  3.0.8-r0
HIGH      CVE-2023-67890  zlib     1.2.13-r0 →  1.2.13-r1
...
```

### Como reagir

| Severidade | Reação típica |
|---|---|
| **CRITICAL** | Bloquear deploy. Atualizar base ou patchar |
| **HIGH** | Bloquear deploy de produção. Sprint para resolver |
| **MEDIUM** | Acompanhar, resolver no próximo ciclo |
| **LOW / UNKNOWN** | Documentar, ignorar com prazo |

### O que iniciante precisa saber

- Toda imagem **vai ter** alguns CVEs. Zero CVEs em imagem complexa é quase impossível. Foco é em CRITICAL e HIGH.
- Atualizar a base (`node:20.11.1` → `node:20.11.2`) costuma resolver várias delas de uma vez.
- Algumas CVEs **não te afetam** (ex.: vulnerabilidade em util de comando que sua app não usa). Mas argumentar caso-a-caso é trabalhoso. Mais barato atualizar.
- Distroless e alpine geralmente têm muito menos CVEs porque têm muito menos software.

### Onde rodar o scan

- **Localmente** durante desenvolvimento de imagem nova
- **Em CI** antes de publicar — bloqueando se severidade alta aparecer
- **Periodicamente em registry** (Trivy server, Harbor scan) — CVEs novos surgem para imagens já publicadas

Exemplo simples em CI (GitHub Actions):

```yaml
- uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'myapp:${{ github.sha }}'
    severity: 'CRITICAL,HIGH'
    exit-code: '1'
```

## Erros comuns de iniciante

### "Funciona em dev mas falha em produção com `permission denied`"

Você passou para non-root, mas a app tenta escrever em `/var/log` ou `/app/cache`. Soluções:

- Faça a app escrever em `/tmp` ou em volume montado com chown correto
- No Dockerfile, `RUN mkdir -p /app/cache && chown -R app:app /app/cache` ANTES do `USER app`

### "Coloquei .env no .dockerignore mas o secret vazou"

`.dockerignore` evita copiar pelo `COPY . .`, mas **não** invalida camadas anteriores. Se você fez `COPY .env ./` em um build antigo, a camada com o `.env` pode estar em cache local ou no registry.

Solução: regenere a imagem do zero, e regenere o secret também (assume que vazou).

### "Meu container precisa de privilégios elevados pra rodar"

Quase sempre é falta de configuração mais cirúrgica:

- Acesso a `/dev/...` específico → `--device` em vez de `--privileged`
- Capabilities específicas → `--cap-add NET_ADMIN` em vez de `--privileged`
- Mount de host → bind mount específico, não `--privileged`

`--privileged` é praticamente "desligar todas as proteções". Reservado para casos raríssimos (rodar Docker dentro de Docker em CI, alguns drivers).

### "Eu uso `latest` porque sempre quero a mais nova"

`latest` é uma tag mutável. Você não está pegando "a mais nova" — está pegando "o que estiver atrás dessa tag agora". Pode ser uma versão antiga que ninguém atualizou. Pode ser uma versão nova que quebrou compatibilidade. Use Renovate/Dependabot para atualizar deliberadamente.

### "Confio em qualquer imagem que tem muitos pulls"

Pulls não validam confiança. `someuser/nginx-with-modules` pode ter 100k pulls e ser mantido por uma pessoa só, sem auditoria. Imagens oficiais (Docker Official Images) e de "Verified Publishers" têm validação mínima do Docker Hub. Para o resto, leia o Dockerfile (deve ser público) ou prefira espelhar internamente.

---

**Princípio que resume tudo:** segurança em container é em camadas. Cada uma sozinha não resolve, mas juntas reduzem o impacto de cada cenário ruim. Para iniciante, o mínimo essencial é: **non-root + secrets fora da imagem + tag pinada + scan em CI**. Isso já te coloca à frente da maioria.
