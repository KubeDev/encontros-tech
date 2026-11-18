---
adr_number: "006"
status: proposto
created: 2026-11-16
supersedes: ""
superseded_by: ""
---

# ADR 006: Estratégia de criação do schema e migrations

## Contexto

O schema é criado por `Base.metadata.create_all` executado no import de `src/main.py`. Com o
porte para Kubernetes (2 réplicas × 2 workers, ver ADR 005), isso roda em 4 processos a cada
deploy. Não há ferramenta de migration: `create_all` cria tabelas que faltam, mas não altera
tabelas existentes. Com banco gerenciado (ADR 001) não existe mais o caminho "entrar no
servidor e rodar SQL".

## Alternativas Consideradas

- **Manter `create_all` no import (estado atual)** — nenhuma mudança; risco de concorrência no
  primeiro deploy e mudanças futuras no modelo não chegam ao banco.
- **`create_all` executado num Job ou initContainer** — tira a criação do caminho de cada
  processo; continua sem migration de alterações. Exige alteração de código (ADR 004).
- **Alembic com migrations versionadas, executadas por um Job antes do Deployment** — trata a
  evolução do schema; adiciona dependência, um passo de deploy e exige alteração de código.

## Decisão

**Em aberto**, por escolha do responsável pelo projeto. Até a decisão, vale o estado atual:
`create_all` no import, com o risco aceito de concorrência no primeiro deploy (um pod pode
reiniciar uma vez).

**O que destrava:** decidir entre Job/initContainer com `create_all` e Alembic. A decisão
fica obrigatória na primeira mudança de modelo que altere uma tabela existente.

## Consequências

- **Positivas:** nada muda agora; o porte não depende desta decisão.
- **Negativas:** alterações de modelo em tabelas existentes não são aplicadas
  automaticamente; precisam de intervenção manual no banco gerenciado até a decisão.
- **Neutras / trade-offs aceitos:** as duas alternativas de mudança conflitam com o ADR 004
  (sem alteração de código); adotá-las significa revisar o escopo do ADR 004 para a
  inicialização do schema.
