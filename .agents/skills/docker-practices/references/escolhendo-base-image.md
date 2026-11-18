# Escolhendo a base image

> **Quando ler:** ao começar um Dockerfile novo e ficar em dúvida entre `python:3.12`, `python:3.12-slim`, `python:3.12-alpine` ou `gcr.io/distroless/python3`. Ao tentar entender por que sua app Python instalou em alpine mas quebrou em runtime. Ao reduzir o tamanho de uma imagem que está enorme.

## Índice

1. [O que é uma "base image" de fato](#o-que-é-uma-base-image-de-fato)
2. [As quatro famílias principais](#as-quatro-famílias-principais)
3. [Tabela comparativa](#tabela-comparativa)
4. [O drama do alpine: glibc vs musl](#o-drama-do-alpine-glibc-vs-musl)
5. [Quando usar distroless](#quando-usar-distroless)
6. [Tags: latest, semver, SHA — o que cada um significa](#tags-latest-semver-sha--o-que-cada-um-significa)
7. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## O que é uma "base image" de fato

Quando você escreve `FROM node:20-slim`, está dizendo "comece com este sistema operacional já configurado, com Node 20 instalado". A base image inclui:

- **Distribuição Linux mínima** (Debian, Ubuntu, Alpine, ou nenhuma no caso de distroless)
- **Runtime da linguagem** (Node, Python, Java, Go) já instalado
- **Bibliotecas C básicas** (glibc ou musl) — o "esqueleto" sobre o qual a maioria dos binários depende
- **Usuários e diretórios padrão** (geralmente já tem um user não-root como `node`, `app`, etc.)

A escolha da base não é estética. Afeta:

| Dimensão | Por quê |
|---|---|
| **Tamanho final** | Pode variar 10× entre alpine e default |
| **Superfície de ataque** | Imagem default tem `bash`, `apt`, `curl`, `wget` — atacante adora |
| **Compatibilidade** | Algumas libs Python/Node esperam glibc; alpine usa musl |
| **Velocidade do build** | Imagem default já tem ferramentas; alpine força você a instalar |
| **CVEs** | Mais software = mais CVEs no scan. Alpine e distroless reduzem drasticamente |

## As quatro famílias principais

### 1. Default (Debian/Ubuntu cheia)

Exemplo: `node:20`, `python:3.12`, `golang:1.22`.

Vem com:
- Distribuição completa (Debian bookworm/Ubuntu jammy)
- Compiladores, headers, ferramentas (`gcc`, `make`, `curl`, `git`)
- Pacotes auxiliares
- Tipicamente 700 MB – 1 GB

**Use quando:**
- Está aprendendo e quer foco no app, não na imagem
- Build precisa compilar extensões C (`pip install` que usa `gcc`)
- Em estágio `builder` de multi-stage (descartável)

**Não use em produção como runtime** — está pagando por gigabytes que você não usa.

### 2. Slim

Exemplo: `node:20-slim`, `python:3.12-slim`.

É a mesma base Debian, mas **stripped down**: sem ferramentas de build, sem doc, sem locales. Mantém a compatibilidade da glibc.

- Tipicamente 150 – 300 MB
- 90% dos casos de produção devem usar slim

**Use quando:**
- Runtime de produção em multi-stage
- Você precisa que `pip install` funcione com wheels precompilados (geralmente sim)
- Quer estabilidade da glibc sem o peso da imagem cheia

### 3. Alpine

Exemplo: `node:20-alpine`, `python:3.12-alpine`.

Distribuição Linux **muito** mínima, baseada em **musl** (não glibc) e **busybox**.

- Tipicamente 50 – 100 MB
- Imagem extremamente enxuta
- Usa `apk` em vez de `apt` (gerenciador de pacotes diferente)

**Use quando:**
- Tamanho importa muito (edge, IoT, cold-start de função)
- Sua app é Go, Rust ou um binário estático qualquer
- Você sabe o que está fazendo com musl (veja seção do drama)

**Não use cegamente para Python/Node sem testar** — leia a seção do drama do alpine.

### 4. Distroless

Exemplo: `gcr.io/distroless/static`, `gcr.io/distroless/nodejs20`, `gcr.io/distroless/python3`.

Mantida pelo Google. **Não tem distribuição Linux**: sem shell, sem package manager, sem ferramentas de debug.

- Tipicamente 20 – 70 MB
- Você não consegue dar `docker exec` com `bash` — não existe bash
- Apenas o runtime mínimo + suas dependências

**Use quando:**
- Binários estáticos (Go, Rust, Java jlink) — `gcr.io/distroless/static`
- Produção crítica onde superfície de ataque mínima é prioridade
- Você tem confiança no app — debug remoto fica mais difícil

## Tabela comparativa

App Node.js simples (`hello world` com Express):

| Base | Tamanho final | Tem `bash`? | Tem `apt`/`apk`? | Tem `curl`? | CVEs típicos | Compatibilidade |
|---|---|---|---|---|---|---|
| `node:20` | ~1 GB | ✅ | apt | ✅ | Dezenas | Total |
| `node:20-slim` | ~200 MB | ✅ | apt (limitado) | ❌ | Poucos | Total |
| `node:20-alpine` | ~120 MB | ❌ (sh) | apk | ❌ | Pouquíssimos | musl (cuidado) |
| `gcr.io/distroless/nodejs20` | ~150 MB | ❌ | ❌ | ❌ | Mínimos | glibc |

(Tamanhos aproximados — variam com versão e o que sua app instala.)

## O drama do alpine: glibc vs musl

Toda distribuição Linux precisa de uma **biblioteca C padrão** (libc) para fazer chamadas de sistema. Quase todo mundo usa **glibc**. Alpine usa **musl** — uma implementação alternativa, mais leve, mais estrita.

Para muitas linguagens, isso é transparente. Para Python e Node, **às vezes não é**.

### O caso clássico: pacotes Python com extensões C

Pacotes como `numpy`, `pandas`, `psycopg2`, `cryptography`, `Pillow` têm extensões C. Quando você faz `pip install`, em distribuições com glibc:

1. `pip` baixa um **wheel pré-compilado** (`*.whl`) com a extensão já buildada
2. Instalação é instantânea

Em alpine (musl):

1. `pip` não acha wheel compatível com musl (a maioria dos wheels publicados é para glibc — tag `manylinux`)
2. `pip` baixa o **source** e tenta compilar
3. Você precisa ter `gcc`, `musl-dev`, `python3-dev`, `libffi-dev`, headers da lib C que o pacote usa…
4. Compilação leva 5+ minutos
5. Talvez nem funcione

Resultado: o "alpine que era pra ser leve" virou um Dockerfile de 30 linhas instalando dependências de build, e seu CI ficou 10× mais lento.

### Quando alpine vale a pena

| Linguagem | Alpine vale? |
|---|---|
| **Go** | Sim, sempre. Binário estático, não depende de libc |
| **Rust** | Sim, com `--target x86_64-unknown-linux-musl` |
| **Java** | Sim com Eclipse Temurin alpine, ou jlink + distroless |
| **Node** | Geralmente sim. Cuidado com pacotes nativos (`bcrypt`, `sharp`, `node-gyp`) |
| **Python** | Cuidado. Slim costuma ser melhor opção |
| **.NET** | .NET 8+ tem builds para alpine, mas slim funciona melhor |

### Heurística prática

> Se sua app não tem dependências nativas (extensões C), alpine é ótimo. Se tem, **slim** é a escolha segura. Distroless é o passo seguinte quando você já dominou multi-stage.

## Quando usar distroless

Distroless brilha quando:

1. **Sua app é um binário estático.** Go compilado com `CGO_ENABLED=0` é um único binário que roda em `gcr.io/distroless/static` (~2 MB de base!).
2. **Você quer superfície de ataque mínima em produção.** Sem shell, atacante que conseguir RCE não tem `/bin/bash` para iniciar reverse shell. Sem `wget`/`curl`, downloads exfiltrativos ficam mais difíceis.
3. **Compliance pede.** Frameworks como CIS Docker Benchmark veem distroless com bons olhos.

Mas:
- **Debug fica mais difícil.** Sem `kubectl exec -it pod -- bash`. Você usa `kubectl debug` com imagem ephemeral.
- **Curva de aprendizado.** Não é o lugar para começar.

Padrão típico para Go:

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o /server ./cmd/server

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /server /server
USER nonroot
ENTRYPOINT ["/server"]
```

Imagem final: ~10 MB. Sem shell, sem package manager, só o binário.

## Tags: latest, semver, SHA — o que cada um significa

Tags em registries são **apontadores mutáveis** para um digest (SHA imutável). Quando você usa `node:20`, está pegando "o que estiver atrás dessa tag agora".

| Tag | Estabilidade | Quando faz sentido |
|---|---|---|
| `latest` | Nenhuma | Nunca em produção. Em scripts ad-hoc, talvez. |
| `20` | Acompanha minor/patch | Aceitável em dev. Frágil em produção. |
| `20.11` | Patches automáticos | OK para muitos projetos. |
| `20.11.1` | Pinada por versão | Recomendado em produção. |
| `20.11.1-slim` | Versão + variante | Idem. |
| `node@sha256:abc123...` | Imutável de verdade | Máxima reprodutibilidade. Pode usar com Renovate/Dependabot atualizando. |

### Por que evitar `latest`

Cenário real, comum em pipelines mal configurados:

1. Sexta-feira 18h, deploy "corre tudo bem". `FROM node:latest` resolveu para `node:20.11.1`.
2. Domingo de madrugada, mantenedor publica `node:20.12.0` com mudança sutil em DNS resolution.
3. Segunda-feira, primeiro pod novo é criado, puxa `latest`, agora resolve para `20.12.0`.
4. App começa a falhar intermitentemente. Você gasta 4 horas debugando.
5. Diff de código: zero linhas. Diff de imagem: nova versão da base.

Pinar versão evita esse cenário. Atualizações ficam **deliberadas**, não acidentais.

## Erros comuns de iniciante

### "Tudo roda na minha máquina mas explode no CI"

Você usou `node:20` localmente, e o CI puxou outra versão da mesma tag depois de uma atualização. Pinde patch.

### "Migrei pra alpine e o build ficou 10× mais lento"

Sua app tem dependências com extensões C. Alpine fez `pip`/`npm` cair no caminho de compilação. Volte para slim.

### "A imagem é minúscula mas a app trava"

Você pode estar usando alpine com lib que precisa glibc. Erros típicos: `Error loading shared library ld-linux-x86-64.so.2: No such file or directory`. Migre para slim ou distroless.

### "Distroless quebrou meu healthcheck que usava curl"

Distroless não tem `curl`. Healthcheck em distroless tem que usar HTTP nativo — geralmente um endpoint que sua app expõe e o orquestrador chama externamente, ou um binário Go pequeno que você copia para a imagem.

### "Coloquei `:latest` em ambiente educacional, alunos viram resultados diferentes"

Pinar versão é importante até em demos. Quem reproduz seu tutorial 3 meses depois quer ver o mesmo comportamento.

---

**Heurística que resume tudo:**

| Situação | Comece com |
|---|---|
| Estou aprendendo, quero foco no app | `<lang>:<versão>-slim` |
| Produção Node/Python típica | `<lang>:<versão>-slim` em multi-stage |
| App Go/Rust em produção | `gcr.io/distroless/static` em multi-stage |
| Cold start crítico (Lambda, edge) | Alpine se compatível, distroless se binário estático |
| Build precisa de gcc | Imagem cheia no estágio builder, slim/distroless no runtime |

Pinar versão. Sempre.
