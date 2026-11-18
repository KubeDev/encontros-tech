---
adr_number: "001"
status: aceito
created: 2026-09-01
supersedes: ""
superseded_by: ""
---

# ADR 001: Armazenamento em memória

## Contexto

O app é pessoal e local; persistir entre execuções ainda não é requisito.

## Alternativas Consideradas

- SQLite: exigiria dependência nativa e migrações para um volume irrelevante.
- Arquivo JSON: simples, mas traz concorrência de escrita sem ganho agora.

## Decisão

Guardar as tarefas num array em memória dentro de `src/tarefas.js`.

## Consequências

Tudo se perde ao reiniciar. Quando persistência virar requisito, este ADR é substituído.
