---
status: proposto
date: 2026-09-14
---

# ADR 002: Fila de agendamento para lembretes

## Contexto

Lembretes precisam disparar quando a tarefa vence, sem varrer o armazenamento.

## Alternativas Consideradas

- Polling a cada minuto: descartado, não escala e atrasa até 60 s.

## Decisão

Usar uma fila de agendamento com job atrasado por lembrete.

## Consequências

Introduz um processo de worker e a dependência de uma fila.
