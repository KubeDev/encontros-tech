---
adr_number: "010"
status: obsoleto
created: 2026-11-17
supersedes: ""
superseded_by: "012"
---

# ADR 010: Imagem publicada no Docker Hub, repositório público, com tags sequenciais

## Contexto

O cluster de homologação precisa baixar a imagem da aplicação de algum registry. A escolha
define se o manifesto precisa de credencial de pull (`imagePullSecret`), se o Terraform precisa
criar um registry e como uma versão nova chega ao cluster. Os manifestos são YAML puro editados
à mão ([ADR 002](002-manifestos-kubernetes-yaml-puro.md)), então a tag da imagem é o que
dispara o rollout: mudar a tag no Deployment é o deploy.

O Docker Hub limita o pull anônimo a **100 pulls a cada 6 horas por IPv4** (ou sub-rede IPv6
/64); conta pessoal autenticada tem 200 **[Verificado — [Docker Hub pull usage and limits](https://docs.docker.com/docker-hub/usage/pulls/), 2026-11-17]**.
Com 2 nós, cada um com IP próprio, e poucos deploys, o volume fica muito abaixo do limite.

## Alternativas Consideradas

- **DigitalOcean Container Registry (DOCR)** — mesma plataforma do cluster, integração nativa
  com o DOKS; em troca, mais um recurso no Terraform e credencial de pull no cluster.
- **GitHub Container Registry (GHCR)** — junto do código; imagem privada exigiria
  `imagePullSecret` no cluster.
- **Docker Hub, repositório público** — pull anônimo, sem credencial no cluster nem recurso no
  Terraform; a imagem fica visível para qualquer pessoa.

Para a tag:

- **`latest`** — sem edição de tag, mas `kubectl apply` não detecta mudança no Deployment:
  exige `imagePullPolicy: Always` e `kubectl rollout restart` a cada deploy, e não diz qual
  versão está rodando.
- **SHA do commit** — rastreável, porém ilegível para quem edita o YAML à mão.
- **Sequencial `v1`, `v2`, `v3`…** — legível, e cada mudança de tag no manifesto dispara o rollout.

## Decisão

Publicar a imagem no **Docker Hub, em repositório público**, com **tags sequenciais `vN`**
(`v1`, `v2`, `v3`…). Decisão do responsável pelo projeto. Regras:

- Uma tag publicada **nunca é sobrescrita**. Versão nova recebe o próximo número.
- O Deployment referencia sempre uma tag `vN`, nunca `latest`.
- Sem `imagePullSecret` no manifesto e sem registry no Terraform.

## Consequências

- **Positivas:** nenhuma credencial de registry no cluster nem no Terraform; o deploy é editar a
  tag no Deployment e aplicar; a versão em execução fica legível no próprio manifesto.
- **Negativas:** a imagem é pública — qualquer pessoa pode baixar o código de `src/`. Nada
  sensível pode entrar na imagem: credenciais chegam só pelo Secret e nenhum `.env` é copiado
  *(premissa — confirme ou corrija)*. O número da versão é controlado à mão, sem automação.
- **Neutras / trade-offs aceitos:** como a tag não é `latest`, o Kubernetes só baixa a imagem
  se ela ainda não estiver no nó. Por isso sobrescrever uma tag faria os nós rodarem versões
  diferentes sob o mesmo nome — é o motivo da regra de imutabilidade. Se o limite de pull
  anônimo virar problema (mais nós ou mais deploys), autenticar o pull com conta gratuita
  resolve sem trocar de registry.
