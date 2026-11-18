---
adr_number: "013"
status: aceito
created: 2026-11-18
supersedes: ""
superseded_by: ""
---

# ADR 013: Versão aplicada só na cópia do runner, sem commit do manifesto

## Contexto

O manifesto `k8s/encontros-tech.yaml` ([ADR 002](002-manifestos-kubernetes-yaml-puro.md)) traz a
versão escrita em três lugares: a tag da imagem, o `SERVICE_VERSION` do ConfigMap e a label
`app.kubernetes.io/version`. Trocar a tag é o que dispara o rollout. Com o CD automático
([ADR 011](011-entrega-em-tres-workflows-github-actions.md)) e a versão vinda do `run_number`
([ADR 012](012-tag-run-number-com-sobrescrita.md)), o CD precisa levar a versão nova ao cluster.

## Alternativas Consideradas

- **O CD commita o manifesto atualizado de volta na `main`** — o repositório reflete o cluster;
  em troca, o commit dispararia a CI de novo, a pipeline precisaria de escrita no repositório e
  de exceção na proteção da `main`.
- **Marcador no lugar da versão, preenchido no deploy** — o arquivo não finge uma versão;
  em troca, o manifesto deixa de ser aplicável à mão como está.
- **O CD troca a versão só na cópia do runner, aplica e descarta** — sem commit, sem laço de
  disparo, sem escrita no repositório; em troca, o arquivo no repositório desatualiza.

## Decisão

O CD substitui, **na cópia do manifesto no runner**, a tag da imagem, o `SERVICE_VERSION` e a
label de versão pelo `v<run_number>` recebido da CI, aplica com `kubectl apply` e **não commita**
nada. O arquivo no repositório não é alterado pela pipeline. Decisão do responsável pelo projeto,
para não gerar uma nova execução da pipeline a cada deploy.

## Consequências

- **Positivas:** sem laço de execução; a pipeline só precisa de leitura no repositório; a
  proteção da `main` não precisa de exceção.
- **Negativas:** a versão escrita no repositório (hoje `v27`) deixa de ser a versão em execução —
  a versão real se consulta no cluster. Um `kubectl apply` manual a partir do repositório volta o
  cluster para a versão escrita no arquivo.
- **Neutras / trade-offs aceitos:** mudanças de manifesto (recursos, réplicas) continuam no
  arquivo versionado e entram no cluster no próximo CD, já que `k8s/**` dispara a CI. O comentário
  de cabeçalho do manifesto, que descreve o deploy manual, precisa ser atualizado na implementação.
