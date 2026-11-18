---
adr_number: "011"
status: aceito
created: 2026-11-18
supersedes: ""
superseded_by: ""
---

# ADR 011: Entrega em três workflows do GitHub Actions, com CD automático disparado pela CI

## Contexto

Até aqui o build da imagem, o push para o Docker Hub, a escolha da versão e o `kubectl apply`
eram manuais, e nada barrava uma PR antes da revisão. O repositório é público no GitHub e a
aplicação roda num cluster DOKS de homologação ([ADR 009](009-homologacao-otimizada-para-custo.md)).
O Terraform continua aplicado à mão, com estado local ([ADR 008](008-terraform-estado-local-aplicacao-manual.md)),
e fica fora de qualquer automação.

## Alternativas Consideradas

- **CD manual (`workflow_dispatch`, escolhendo a versão)** — controle total sobre quando a
  homologação muda; em troca, todo merge exige um passo humano e a homologação fica atrás da `main`.
- **CD automático com aprovação (GitHub Environment com revisor)** — automático até a porta;
  em troca, um aprovador por deploy e o uso de Environments, que o projeto não adota.
- **Um único workflow fazendo validação, publicação e deploy** — menos arquivos; em troca,
  mistura o que roda em PR (sem secrets, sem publicar) com o que roda na `main`.
- **Três workflows — PR valida, CI publica, CD aplica automaticamente quando a CI termina** —
  cada um com gatilho e permissões próprias; o CD não depende de ação humana.

## Decisão

Usar **GitHub Actions** com **três workflows**:

1. **PR** — em toda PR para a `main`, sem filtro de caminho: `uv run pytest` e build da imagem
   **sem push**. É o check obrigatório para o merge na `main`. Sem filtro porque um check
   obrigatório pulado por filtro de caminho fica "Pending" e bloqueia o merge **[Verificado —
   docs.github.com, Skipping workflow runs, via Context7, 2026-11-18]**.
2. **CI** — em push na `main` que altere `src/**`, `Dockerfile`, `.dockerignore`,
   `pyproject.toml`, `uv.lock` ou `k8s/**`: pytest, build e push da imagem com a tag de
   [ADR 012](012-tag-run-number-com-sobrescrita.md).
3. **CD** — disparado por `workflow_run` quando a CI termina na `main`, executando só se a
   conclusão for `success`; recebe o número da versão pelo próprio evento e aplica no cluster
   ([ADR 013](013-versao-aplicada-no-runner-sem-commit.md)) **[Verificado — docs.github.com,
   workflow_run, via Context7, 2026-11-18]**.

Decisão do responsável pelo projeto. O Terraform não entra em nenhum dos três.

## Consequências

- **Positivas:** todo merge de código na `main` chega à homologação sem passo manual; a PR só
  entra com testes e build verdes; o workflow de PR não usa secrets, então roda com segurança
  em PR de fork.
- **Negativas:** a homologação muda a cada merge de código, sem janela escolhida; mudança só em
  docs, ADRs ou Terraform não gera imagem nem deploy (intencional), e mudança em `k8s/**` gera
  imagem nova mesmo sem mudança de código. O gate é mínimo — sem lint, formatter, hadolint,
  validação de manifesto, scan nem cobertura neste ciclo.
- **Neutras / trade-offs aceitos:** o `workflow_run` só dispara se o arquivo do CD existir na
  branch padrão. O sucesso do deploy é o fim do rollout com prazo máximo; sem probes, isso prova
  só que o contêiner subiu *(premissa — confirme ou corrija)*. Um deploy por vez: o seguinte
  espera na fila *(premissa — confirme ou corrija)*. Rollback = reverter o commit numa PR, o que
  gera versão nova *(premissa — confirme ou corrija)*. Barrar o merge exige configurar a proteção
  da `main` (merge só por PR, check da PR obrigatório) no repositório *(premissa — confirme ou corrija)*.
