# Portão da consolidação (Fase 4)

O portão do brainstorm é onde o usuário confere de uma vez o que foi decidido. Aqui ele também
decide quais ADRs candidatos viram registro — é o que impede uma decisão revertida no meio da
conversa de virar documento.

## 1. Apresentar

Junto da consolidação normal do brainstorm (tabela `Decisão | Escolha | Justificativa | Estado`),
mostre os ADRs candidatos com o destino que o estado indica:

| Candidato | Decisão | Estado na consolidação | Destino |
|---|---|---|---|
| fila entre ingestão e processamento | fila, não chamada síncrona | Decidido | gravar `aceito` |
| provedor de identidade | — | Em aberto | gravar `proposto` + pendência |
| cache de leitura | — | revertido | não gravar |

Mostre também os termos do glossário registrados na sessão, para uma última revisão.

## 2. Gravar, depois da validação explícita do usuário

Em lote, um ADR por candidato, pelo `escrever-trd` no Modo Decision com uma frase explícita —
"registra a decisão de usar X, status aceito; alternativa descartada: Y; motivo: Z":

- **Decidido** → ADR com `status: aceito` (a partir daí imutável; revisar vira ADR novo com
  `supersedes`).
- **Em aberto** → ADR com `status: proposto` e a pendência registrada com o que a destrava.
- **Revertido** → nada a gravar.

Anuncie cada um em uma linha: `ADR-00N <status>: <título>`.

## 3. Gerar o TRD

Invoque o `escrever-trd` — Modo Criação sem `docs/trd.md`, Modo Edição com ele — passando a
consolidação como documento de origem. Projeto sem código não tem o que analisar: diga
explicitamente à skill que a fonte é a consolidação. O mapeamento:

| Da lente | Para o TRD |
|---|---|
| Requisitos técnicos (decisões que restringem) | Arquitetura e Stack |
| Checklist de não-funcionais | Requisitos Não-Funcionais |
| Integrações externas | Dependências Externas |
| ADRs aceitos | Decisões Globais (a tabela é mantida pelo `escrever-trd`) |

Item Verificado entra com a fonte e a data da consulta.

## 4. Próximos passos

Sugira, sem executar:
- salvar o documento do brainstorm (`docs/brainstorm-{slug}.md`), se ainda não existe;
- `escrever-prd` numa sessão nova, com o documento do brainstorm como origem, para formalizar os
  requisitos de negócio levantados na lente.
