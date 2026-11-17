# TRD — tarefas

## Stack

- Node.js ≥ 22, ES modules, sem dependências de runtime.
- Testes: `node --test` (comando: `npm test`).

## Arquitetura

- Padrão arquitetural: módulo único de domínio (`src/tarefas.js`) exportando funções puras sobre um armazenamento em memória.
- Estrutura de pastas dominante: `src/` para código, `test/` para testes.

## Requisitos Não-Funcionais

- Uso local, um usuário, volume pequeno (centenas de tarefas).

## Dependências Externas

Nenhuma.

## Padrões

- **Testes:** um arquivo `test/<capacidade>.test.js` por capacidade do domínio; nome do teste diz o comportamento.
- **Error handling:** entrada inválida lança `Error` com mensagem em português.

## Decisões Globais

| # | Título | Data | Status | Link |
|---|---|---|---|---|
| 001 | Armazenamento em memória | 2026-09-01 | aceito | [ADR-001](adrs/001-armazenamento-em-memoria.md) |
