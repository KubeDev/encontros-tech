---
adr_number: "012"
status: aceito
created: 2026-11-18
supersedes: "010"
superseded_by: ""
---

# ADR 012: Tag da imagem `v<run_number>` da CI, com sobrescrita permitida

## Contexto

O [ADR 010](010-imagem-docker-hub-publico-tags-sequenciais.md) definiu o Docker Hub público e
tags sequenciais `vN` escolhidas à mão, com a regra de que uma tag publicada nunca é
sobrescrita. Com a CI publicando a imagem ([ADR 011](011-entrega-em-tres-workflows-github-actions.md)),
o N precisa sair da própria pipeline.

O `github.run_number` começa em 1 na primeira execução de cada workflow, incrementa a cada nova
execução e não muda em reexecução (`run_attempt` é que muda) **[Verificado — docs.github.com,
Contexts reference, via Context7, 2026-11-18]**. O repositório `fabricioveronez/encontros-tech`
no Docker Hub já tem as tags `v1` a `v27` (e uma `latest` antiga), publicadas à mão
**[Verificado — API do Docker Hub, 2026-11-18]**.

## Alternativas Consideradas

- **N escolhido à mão** (como no ADR 010) — controle total; em troca, passo manual a cada merge.
- **Tag git `vN` disparando a publicação** — versão explícita; em troca, passo manual e o CD
  deixa de ser automático por merge.
- **`run_number` com deslocamento (ex.: +27 ou +100) e trava que falha a CI se a tag já existir**
  — preserva a imutabilidade; em troca, mais lógica na pipeline.
- **`run_number` puro, com sobrescrita permitida** — o mais simples; em troca, colide com as
  tags existentes.

## Decisão

A CI publica a imagem no **Docker Hub, repositório público** (mantido do ADR 010), com a tag
**`v<run_number>`** do workflow de CI. **Sobrescrever uma tag existente é permitido** — a regra
de imutabilidade do ADR 010 deixa de valer. A CI não publica `latest`; a `latest` antiga fica
como está. Continuam valendo do ADR 010: sem `imagePullSecret`, sem registry no Terraform, e o
Deployment nunca referencia `latest`. Decisão do responsável pelo projeto.

## Consequências

- **Positivas:** versão sem passo manual, legível e crescente; CI e CD usam o mesmo número
  (o CD o recebe pelo evento `workflow_run`).
- **Negativas:** as primeiras execuções sobrescrevem as tags `v1` a `v26` antigas. Quando o
  `run_number` chegar a 27 — a versão hoje em execução —, o manifesto aplicado já diz `v27` e os
  nós já têm a `v27` antiga em cache (`imagePullPolicy: IfNotPresent`): o `kubectl apply` não muda
  o Deployment e o deploy termina verde **sem trocar o código**. Risco aceito. Em geral,
  sobrescrever uma tag pode deixar nós diferentes com imagens diferentes sob o mesmo nome.
- **Neutras / trade-offs aceitos:** renomear ou recriar o workflow de CI pode reiniciar a
  contagem e repetir números *(premissa — confirme ou corrija)*. O limite de pull anônimo do
  Docker Hub registrado no ADR 010 continua valendo.
