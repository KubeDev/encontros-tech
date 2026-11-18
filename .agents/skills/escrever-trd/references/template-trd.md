# TRD — Technical Requirements Document

> Documento técnico global do projeto. Criado e atualizado via skill `escrever-trd`.
> Carregado automaticamente por `preparar-execucao` e `implementar-task` como contexto global.
> Granularidade baixa: cobre o que é global e estável. Regras finas ficam em ADRs.

---

## Stack

| Dimensão | Valor |
|---|---|
| Linguagem principal | `<linguagem e versão>` |
| Runtime / plataforma | `<ex.: Node.js 20, JVM 21, Python 3.12>` |
| Framework principal | `<ex.: Next.js 14, Spring Boot 3, FastAPI>` |
| Banco de dados | `<ex.: PostgreSQL 16, MongoDB 7, SQLite>` |
| Ferramentas de build | `<ex.: Vite, Maven, Poetry>` |
| Gerenciador de pacotes | `<ex.: npm, pnpm, pip, cargo>` |

---

## Arquitetura

### Padrão arquitetural

`<ex.: MVC, hexagonal, modular monolith, serverless, event-driven>`

Breve descrição de por que esse padrão foi adotado (1-2 linhas):

### Estrutura de pastas dominante

```
<raiz>/
├── <pasta>  # responsabilidade em 1 linha
└── <pasta>  # responsabilidade em 1 linha
```

### Módulos / camadas principais

| Módulo | Responsabilidade |
|---|---|
| `<módulo>` | `<1 linha>` |

---

## Requisitos Não-Funcionais

<!-- Requisitos mensuráveis e concretos que definem o desafio de engenharia global.
     Evite vagueza: "rápido" não é requisito; "p95 < 200ms" é.
     NFR GLOBAL e transversal mora aqui; NFR específico de uma feature (com razão de
     negócio) mora no PRD daquela feature (§5a Critérios de aceite), não no TRD.
     Se um requisito não se aplica, escreva "Não definido" — não omita a linha. -->

| Dimensão | Requisito |
|---|---|
| Performance | `<ex.: p95 de resposta < 200ms para endpoints de leitura>` |
| Disponibilidade / SLA | `<ex.: uptime 99,9%; RPO 1h; RTO 4h>` |
| Escalabilidade | `<ex.: suportar até 10 000 usuários simultâneos sem degradação>` |
| Segurança | `<ex.: HTTPS obrigatório; dados sensíveis criptografados em repouso (AES-256)>` |
| Observabilidade | `<ex.: traces distribuídos via OpenTelemetry; logs estruturados em JSON>` |

---

## Dependências Externas

<!-- Liste APIs de terceiros, serviços de infraestrutura e sistemas internos que impõem
     SLA, rate limit, contrato de dado ou comportamento que afeta decisões de arquitetura.
     NÃO liste dependências de build (libs do lockfile) — essas são inferidas automaticamente.
     Se não há dependências externas relevantes, escreva "Nenhuma". -->

| Serviço / Sistema | Tipo | Constraint relevante | Dono |
|---|---|---|---|
| `<ex.: Stripe API>` | `<ex.: REST>` | `<ex.: rate limit 100 req/s; webhook com retry automático>` | `<ex.: externo>` |
| `<ex.: Redis>` | `<ex.: SDK>` | `<ex.: TTL máximo 24h; sem persistência em staging>` | `<ex.: interno — infra>` |
| `<ex.: Serviço de Auth>` | `<ex.: JWT / OAuth 2.0>` | `<ex.: token expira em 1h; refresh obrigatório via cookie httpOnly>` | `<ex.: interno — squad auth>` |

---

## Padrões

### Testes

| Item | Valor |
|---|---|
| Framework | `<ex.: Jest, pytest, JUnit, cargo test>` |
| Comando completo | `<ex.: npm test, pytest tests/, cargo test>` |
| Cobertura mínima | `<ex.: 80% linhas, ou "não definida">` |
| Estratégia | `<ex.: unit + integração; sem E2E automatizado>` |

### Estilo de código

- **Linter:** `<ex.: ESLint, Ruff, Clippy>`
- **Formatter:** `<ex.: Prettier, Black, rustfmt>`
- **Convenções de nomenclatura:** `<ex.: camelCase para funções, PascalCase para classes>`

### Error handling

`<Descrever o padrão adotado, ex.: "Erros de domínio são tipos explícitos; erros de infra são
logados e relançados como erros genéricos para a camada de API">`

### Logging

- **Formato:** `<ex.: JSON estruturado, texto simples>`
- **Nível padrão:** `<ex.: INFO em produção, DEBUG em desenvolvimento>`
- **Biblioteca:** `<ex.: pino, winston, slog, tracing>`

### Autenticação / autorização

`<Descrever o padrão, ex.: "JWT com refresh token; autorização baseada em roles no middleware"
— ou "Não aplicável">`

---

## Decisões Globais (ADRs)

<!-- Referência progressiva: liste cada ADR com título, data, status e link.
     Não inlinar o conteúdo — ADRs podem ser extensos e mudam independentemente do TRD.
     ADRs obsoletos devem ser marcados visualmente (~~riscado~~ na coluna Título). -->

| # | Título | Data | Status | Link |
|---|--------|------|--------|------|
| — | *(nenhum ADR registrado)* | — | — | — |
