---
name: escrever-trd
description: >
  Cria e mantém o TRD (Technical Requirements Document) em `docs/trd.md` — stack, arquitetura,
  requisitos não-funcionais, dependências externas, padrões e decisões globais do projeto.
  Também cria ADRs (Architecture Decision Records) no Modo Decision: registra uma decisão
  técnica em `docs/adrs/` e atualiza a seção Decisões Globais. O TRD é o contexto técnico
  consultado pelas skills do fluxo sdd (`sdd-especificar` em diante).

  Use ao criar um TRD, documentar a stack, registrar padrões de arquitetura, começar projeto
  novo sem TRD, quando a stack mudou, ou quando o `sdd-especificar` pedir contexto técnico por falta
  de `docs/trd.md` — mesmo sem usar o termo "TRD". Use o Modo Decision quando o usuário quiser
  "registrar uma decisão", "criar um ADR", ou disser "decidimos usar/trocar X por Y" — é
  decisão técnica/arquitetural, distinta de decisão de produto (que fica no PRD).
---

# Escrever TRD

Cria e mantém o TRD (Technical Requirements Document) em `docs/trd.md`. O TRD é o documento
técnico global do projeto: único, mantido, consultado pelas skills do fluxo sdd. Cobre o que é global e estável — stack, arquitetura, requisitos
não-funcionais, dependências externas, padrões e decisões. Requisitos de uma feature
específica ficam no PRD; detalhes de uma decisão pontual ficam em ADRs.

A skill analisa o projeto automaticamente, enriquece com busca externa e só entrevista o
usuário para o que ainda ficou em aberto — o objetivo é minimizar atrito e maximizar o que
se pode deduzir sem perguntar.

## Entrada

O usuário pode invocar esta skill:

- Sem argumentos: a skill detecta o modo automaticamente pela presença de `docs/trd.md`
- "atualizar", "editar", "o TRD mudou", "stack mudou": confirma modo edição
- "criar", "novo TRD": confirma modo criação

## Modos

A detecção de **Criação vs Edição** é automática pela presença de `docs/trd.md` — o usuário
não precisa especificar. O **Modo Decision** é acionado por intenção explícita (registrar
decisão / criar ADR) e sobrepõe a detecção automática.

- **Criação** — `docs/trd.md` não existe: analisa o projeto, enriquece com busca externa,
  conduz mini-entrevista apenas para lacunas, gera o TRD com 6 seções a partir do
  `references/template-trd.md`.
- **Edição** — `docs/trd.md` existe: re-analisa o projeto, compara com o TRD atual,
  conduz entrevista focada apenas no que divergiu, e atualiza preservando o que está correto.
- **Decision** — registra uma decisão técnica como ADR em `docs/adrs/NNN-slug.md` (imutável
  após `aceito`) e atualiza a seção "Decisões Globais" do TRD. Acionado por pedido explícito
  ("registra a decisão de…", "cria um ADR"); independe de o TRD já existir.

## Fluxo de Execução

### Modo Criação

Roda quando `docs/trd.md` não existe. O objetivo é gerar um TRD completo com o mínimo
de fricção: a maior parte do conteúdo deve vir da análise automática e do enriquecimento;
a entrevista cobre apenas as lacunas reais.

#### Passo 0 — Projeto sem código (a partir de documento de origem)

Quando o projeto ainda não tem código — tipicamente logo depois de um brainstorm de sistema
(`brainstorm-for-systems`) — não há arquivo para analisar. A fonte é o **documento de origem**
(a consolidação do brainstorm ou outro documento que o usuário indicar): extraia dele Stack,
Arquitetura, Requisitos Não-Funcionais e Dependências Externas, pule o Passo 1, aplique o
enriquecimento externo (Passo 2) às dependências citadas e entreviste só as lacunas. Itens que o
documento marca como Verificados entram com a fonte e a data da consulta.

#### Passo 1 — Análise automática do projeto

Antes de fazer qualquer pergunta, inspecione estes arquivos e padrões. Quanto mais for
inferido aqui, menor será a entrevista — e uma entrevista curta é o sinal de que a skill
está funcionando bem.

**Stack:**
- `package.json` / lockfiles → linguagem, runtime, dependências principais, framework, ferramentas de teste
- `tsconfig.json` → configuração TypeScript, sistema de módulos, target
- `pyproject.toml` / `requirements.txt` / `setup.py` → stack Python
- `go.mod` → stack Go
- `Cargo.toml` → stack Rust
- `Makefile`, `justfile` → comandos de build e teste

**Padrões:**
- `.eslintrc*`, `.prettierrc*`, `ruff.toml`, `clippy.toml` → linting e formatação
- `jest.config.*`, `vitest.config.*`, `pytest.ini` → framework e config de testes
- Scripts de teste em `package.json` → comando de teste

**Arquitetura:**
- Estrutura de pastas (2 níveis) → padrão arquitetural e organização
- 1-2 arquivos-fonte representativos → convenções de nomenclatura e error handling

**Dependências Externas (inferência parcial):**
- `package.json` / lockfiles → SDKs de terceiros conhecidos (ex.: `stripe`, `@sendgrid/mail`,
  `firebase-admin`) que indicam integrações externas; não liste todas as libs — só as que
  impõem contrato, rate limit ou comportamento arquitetural relevante
- `.env.example` / `.env.sample` → variáveis que referenciam URLs ou chaves de APIs externas
  (ex.: `STRIPE_SECRET_KEY`, `REDIS_URL`, `AUTH0_DOMAIN`) revelam dependências não óbvias
- `docker-compose.yml` / `docker-compose.yaml` → serviços declarados (ex.: Redis, Postgres,
  RabbitMQ) que o projeto depende em desenvolvimento
- `terraform/`, `infra/`, `k8s/` → recursos de infraestrutura que revelam dependências de cloud

**Requisitos Não-Funcionais (inferência limitada):**
- Arquivos de configuração de infraestrutura podem revelar constraints (ex.: limites de memória
  no `docker-compose`, timeouts em configs de proxy/gateway)
- Em geral, NFRs raramente ficam em arquivos — são candidatos prioritários para a entrevista

Após a análise, mapeie internamente o que foi inferido com confiança vs. o que ficou
incerto. As incertezas alimentam os passos 2 e 3.

#### Passo 2 — Enriquecimento por busca externa

Para cada dependência externa identificada no Passo 1, busque ativamente os constraints
públicos relevantes antes de perguntar ao usuário — perguntar sobre algo que a documentação
já responde é desperdício de fricção.

**Como buscar:**

Use qualquer MCP ou ferramenta disponível que permita acessar documentação ou fazer consultas
relevantes — `WebSearch`, MCPs de documentação de linguagens/frameworks, MCPs de serviços
específicos (ex.: `context7` para libs), ou qualquer outro disponível na sessão. O critério
é: a ferramenta consegue retornar informação técnica confiável sobre o serviço?

- Priorize serviços com documentação pública e estável: rate limits, SLAs, comportamentos
  padrão, timeouts, limites de conexão, quotas
- Para sistemas **internos** do projeto, não busque — essas informações vêm exclusivamente
  da entrevista com o usuário
- Se múltiplas ferramentas estão disponíveis para o mesmo serviço, prefira a mais
  especializada (ex.: MCP do serviço > WebSearch genérica)

**Como registrar:**
- Anote o resultado internamente com a fonte (ex.: `[WebSearch]`, `[context7]`, `[MCP stripe]`)
- Trate o resultado como **sugestão pré-preenchida**, nunca como fato confirmado — o usuário
  valida no preview antes de gravar
- Se a busca não retornar resultado confiável ou a documentação for ambígua, classifique
  como lacuna e inclua na entrevista normalmente

**Exemplos de constraints a buscar:**

| Serviço detectado | O que buscar |
|---|---|
| Stripe / `@stripe/stripe-js` | Rate limit por endpoint, comportamento de idempotência |
| Redis / `ioredis` | Max connections padrão, TTL máximo, comportamento em memória cheia |
| SendGrid / `@sendgrid/mail` | Rate limit de envio, limites de bounce |
| Auth0 / `auth0` | Rate limit de autenticação, expiração padrão de tokens |
| AWS S3 / `@aws-sdk/client-s3` | Limites de tamanho de objeto, rate limit de requests |
| Firebase / `firebase-admin` | Limites de leitura/escrita no Firestore, quotas |

#### Passo 3 — Mini-entrevista para lacunas

Entreviste apenas o que não foi possível inferir nem enriquecer pela busca externa. O limite
é **≤5 perguntas** (target do PRD; máximo aceitável: 8). Por quê esse limite? Se precisar
de mais perguntas, o problema está na análise e no enriquecimento, não no usuário — a
entrevista deve ser o complemento, não o caminho principal.

Dependências já enriquecidas no Passo 2 **não geram pergunta** — apenas aparecem no preview
como sugestão para confirmação. Só pergunte sobre uma dependência externa se a busca não
retornou resultado confiável.

Agrupe até 2 perguntas relacionadas por mensagem para reduzir o vai-e-vem. Prioridade:

1. Lacunas de stack (se linguagem ou runtime não ficou claro)
2. Padrão arquitetural (se a estrutura de pastas não revelou)
3. Comando de teste (se não encontrou em scripts ou config)
4. Convenções (se não há config de linting/formatação)
5. Requisitos não-funcionais principais (se nenhum indício nos arquivos de infra):
   perguntar por performance esperada, SLA e restrições de segurança em uma única
   pergunta agrupada — NFRs raramente são inferíveis e têm alto impacto em planos
6. Dependências externas não óbvias (se `.env.example` ou lockfile não revelaram, e busca
   externa não cobriu): perguntar quais APIs de terceiros ou serviços internos o projeto
   consome e se há rate limits ou contratos a respeitar
7. Localização de ADRs (se `docs/adrs/` não existe e o usuário pode ter outro path)

As prioridades 5 e 6 podem ser agrupadas numa única mensagem quando ambas faltam,
mantendo o limite de ≤5 trocas de mensagem.

#### Passo 4 — Varredura de ADRs (US03)

Escaneie `docs/adrs/` em busca de ADRs existentes. Para cada arquivo encontrado, extraia:

- **Título**: do H1 ou do nome do arquivo
- **Data**: do frontmatter ou do prefixo do nome do arquivo
- **Status**: campo `status` do frontmatter ou palavra-chave no corpo (`aceito` / `obsoleto`)
- **Link**: caminho relativo a partir de `docs/trd.md`

ADRs com status `obsoleto` são listados com marcação visual `~~título~~` — nunca removidos.
Não inlinar o conteúdo dos ADRs: eles podem ser extensos e mudam independentemente do TRD.

Se `docs/adrs/` não existir, use `*(nenhuma decisão registrada ainda)*` na seção. Se o
usuário informou outro path, escaneie esse path.

#### Passo 5 — Preview e gravação

Gere as 6 seções usando `references/template-trd.md` como estrutura canônica. Antes de
gravar, mostre um preview de cada seção ao usuário e peça confirmação. Sugestões vindas do
Passo 2 devem aparecer marcadas com a fonte para que o usuário saiba o que foi inferido vs.
buscado vs. informado manualmente.

Se `docs/` não existir, crie o diretório antes de gravar. Se o usuário cancelar, não
grave o arquivo — cancelamento não tem efeito colateral.

### Modo Edição

Roda quando `docs/trd.md` já existe. A detecção é automática — o usuário não precisa
especificar o modo. O objetivo é manter o TRD sincronizado sem jogar fora o que já está
correto: a entrevista é focada apenas no que divergiu, poupando o usuário de revalidar
o que não mudou.

#### Passo 1 — Leitura do TRD atual

Leia `docs/trd.md` integralmente. Se o arquivo existir mas estiver vazio ou corrompido
(sem seções reconhecíveis), trate como modo criação e avise o usuário.

#### Passo 2 — Re-análise e enriquecimento

Repita a análise automática com os mesmos critérios do Modo Criação (Passo 1). O resultado
é um "estado atual inferido" que será comparado com o TRD existente.

Para dependências externas **novas** detectadas nesta re-análise (presentes no projeto mas
ausentes do TRD atual), aplique o enriquecimento por busca externa (Passo 2 do Modo Criação)
antes de apresentá-las ao usuário. Dependências já documentadas no TRD não precisam ser
rebuscadas.

#### Passo 3 — Detecção de divergências

Compare o TRD com o estado inferido e classifique as divergências em todas as 6 seções
(Stack, Arquitetura, Requisitos Não-Funcionais, Dependências Externas, Padrões, Decisões Globais):

- **(a) Mudança no projeto não refletida no TRD** — ex.: framework mudou, nova dependência
  externa adicionada, novo serviço no `docker-compose`, variável de ambiente nova no `.env.example`
- **(b) Entrada no TRD que não se verifica mais no projeto** — ex.: dependência removida,
  padrão abandonado, serviço externo descontinuado
- **(c) Área ambígua** — algo diferente identificado, mas sem certeza se é mudança real ou
  variação de interpretação
- **(d) Seção ausente no TRD** — ex.: TRD criado antes de ter as seções de Requisitos
  Não-Funcionais ou Dependências Externas; nesse caso oferecer preenchê-la via entrevista focada

Se nenhuma divergência for encontrada, informe que o TRD está sincronizado e encerre sem
edições.

#### Passo 4 — Entrevista focada

Apresente as divergências e, para cada uma, ofereça a decisão: **atualizar**, **manter**
ou **ignorar**. Não recolha informações que já estão corretas no TRD — o foco é no delta,
não numa reentrevista completa. Isso preserva o trabalho que o usuário já aprovou.

**Tratamento de ADRs:** Referências a ADRs no TRD são preservadas por padrão — nunca
removidas sem confirmação explícita. Se um ADR referenciado não for encontrado no
repositório, marque como `*(arquivo não encontrado)*` e pergunte se deve remover a
referência. ADRs com status `obsoleto` permanecem listados com `~~título~~`.

#### Passo 5 — Preview e gravação

Mostre um resumo das alterações aprovadas (seções que mudaram vs. preservadas) antes de
gravar. O TRD é sobrescrito apenas ao final, com todas as alterações aprovadas.

Se o usuário cancelar em qualquer ponto, não grave — o arquivo original permanece intacto.
Cancelamento não tem efeito colateral: perder o TRD anterior seria pior do que refazer a
entrevista depois.

### Modo Decision

Roda quando o usuário pede para registrar uma decisão técnica ("registra a decisão de…",
"cria um ADR", "decidimos trocar X por Y"). Independe de o TRD existir — ADRs vivem em
`docs/adrs/` por conta própria. Cria um ADR a partir de `references/template-adr.md`.

#### Quando é ADR (e quando não é)

Registrar como ADR só decisão **durável, de blast radius amplo e cara de reverter** — escolha
de banco, estratégia de auth, padrão arquitetural, biblioteca estruturante, convenção de API.
Decisão **local a uma feature** não é ADR: se for difícil de reverter (nova dependência, modelo de
dados, interface entre fatias), mora no PLAN da fatia, gerado pelo `sdd-especificar`; se for
reversível (qual util reusar, como fiar um endpoint), nem precisa de registro. Se o pedido for de
decisão local, avisar e sugerir o caminho certo em vez de criar ADR.

#### Passo 1 — Numeração

Listar `docs/adrs/` (criar o diretório se não existir). O próximo ADR recebe o maior número
existente + 1, no formato `NNN` de 3 dígitos. Se não houver nenhum, começar em `001`.

#### Passo 2 — Geração draft-first

Gerar o ADR completo a partir do que o usuário descreveu, **sem entrevista longa**. Inferir
Contexto, Alternativas Consideradas e Consequências faltantes e marcar cada inferência com
`*(premissa — confirme ou corrija)*`. O `status` inicial é `aceito` quando o usuário já
decidiu, ou `proposto` quando a decisão ainda está em aberto.

#### Passo 3 — Supersedência

Se a decisão substitui uma anterior, identificar o ADR antigo:
1. No ADR novo, preencher `supersedes: "NNN"`.
2. No ADR antigo, preencher `superseded_by: "NNN"` e mudar `status` para `obsoleto` — **única
   alteração permitida num ADR `aceito`**. Não editar mais nada do ADR antigo.

#### Passo 4 — Gravação e referência no TRD

1. Gravar `docs/adrs/NNN-slug.md`.
2. Se `docs/trd.md` existe, atualizar a tabela "Decisões Globais" com a nova linha (`#`,
   título, data, status, link). ADR `obsoleto` é renderizado como `~~título~~`, nunca removido.
3. Se `docs/trd.md` não existe, informar que o ADR será indexado automaticamente na próxima
   Criação do TRD (a Varredura de ADRs do Modo Criação cobre isso).
4. Sugerir commit: `docs(adr): adiciona ADR-NNN <slug>`.

#### Imutabilidade

ADR `aceito` é imutável, exceto o `status` quando outro ADR o supersede. Revisar uma decisão
nunca é editar o ADR — é criar um novo com `supersedes` apontando para o antigo. Mesma
disciplina da imutabilidade do PRD `concluido`.

## Templates de referência

- `references/template-trd.md` — estrutura canônica do TRD gerado com as 6 seções
  obrigatórias. Consultar sempre ao gerar ou editar seções do TRD.
- `references/template-adr.md` — estrutura canônica do ADR gerado no Modo Decision.
  Consultar sempre ao criar um ADR.

## Fora do escopo

Esta skill **não**:

- Cria Epics ou PRDs (papel de `escrever-prd`)
- Gera SPEC, PLAN ou TASKS (papel do `sdd-especificar`)
- Cria ADRs fora do Modo Decision — nos modos Criação e Edição apenas referencia os ADRs já existentes em `docs/adrs/`; a criação de ADR é exclusiva do Modo Decision
- Toma decisões de negócio — lacunas são devolvidas ao usuário
- Edita `docs/trd.md` se o usuário cancelar o preview antes de gravar
