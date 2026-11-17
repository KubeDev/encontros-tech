# Template ADR

Estrutura padrão do ADR (Architecture Decision Record) gerado pela skill `escrever-trd` no **Modo Decision**. Um ADR registra **uma** decisão técnica relevante e é **imutável** depois de `aceito`.

## Quando criar um ADR

Uma decisão merece ADR quando é **durável, de blast radius amplo e cara de reverter**:

| Característica | ADR? |
|---|---|
| Sobrevive à feature, afeta outras features ou o sistema, custosa de reverter | ✅ ADR (`docs/adrs/`) |
| Local à feature e difícil de reverter | ❌ PLAN da fatia (`.sdd/`, via `sdd-especificar`) |
| Local à feature e reversível | ❌ nenhum registro — decide-se construindo |

Exemplos de ADR: escolha de banco, estratégia de autenticação, padrão arquitetural (hexagonal, event-driven), biblioteca estruturante, convenção de API.

## Semântica dos campos de controle

**`status`** — ciclo de vida da decisão:

- `proposto` — registrada, ainda não ratificada
- `aceito` — decisão valendo; **o ADR congela e vira registro histórico imutável**
- `obsoleto` — substituída por outra decisão (superseded) ou abandonada

Um ADR `aceito` não é editado. A **única** alteração permitida é flipar o `status` para `obsoleto` quando outro ADR o substitui. Revisar uma decisão = criar um ADR novo com `supersedes` apontando para o antigo.

**`supersedes` / `superseded_by`** — encadeiam a substituição:

- O ADR novo declara `supersedes: "NNN"` (o que ele substitui)
- O ADR antigo recebe `superseded_by: "NNN"` e `status: obsoleto`
- Na seção "Decisões Globais" do TRD, ADR obsoleto é renderizado como `~~título~~` — nunca removido

**Numeração** — `NNN` sequencial de 3 dígitos, igual à convenção dos PRDs. O próximo número é o maior em `docs/adrs/` + 1; se vazio, `001`.

---

```markdown
---
adr_number: "NNN"
status: proposto | aceito | obsoleto
created: YYYY-MM-DD
supersedes: ""        # ADR que este substitui (ex.: "004"), ou vazio
superseded_by: ""     # preenchido quando outro ADR substitui este
---

# ADR NNN: [Título da decisão]

## Contexto

[Problema, restrições e forças em jogo que exigem a decisão. Por que precisamos
decidir isso agora? O que está em tensão?]

## Alternativas Consideradas

- **[Opção A]** — [prós e contras]
- **[Opção B]** — [prós e contras]
- **[Opção C]** *(se houver)* — [prós e contras]

## Decisão

[O que foi decidido e a razão que pesou mais. Uma escolha clara, não um leque.]

## Consequências

- **Positivas:** [o que melhora com esta decisão]
- **Negativas:** [o custo aceito, o que fica pior ou mais restrito]
- **Neutras / trade-offs aceitos:** [implicações que não são bônus nem ônus]
```
