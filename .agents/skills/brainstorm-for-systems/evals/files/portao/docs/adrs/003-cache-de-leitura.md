---
status: proposto
date: 2026-09-14
---

# ADR 003: Cache de leitura da lista de tarefas

## Contexto

A listagem poderia ficar lenta com muitos lembretes associados.

## Alternativas Consideradas

- Sem cache: leitura direta do armazenamento.

## Decisão

Manter um cache de leitura invalidado a cada escrita.

## Consequências

Mais um ponto de inconsistência para manter.
