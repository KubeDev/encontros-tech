---
adr_number: "002"
status: aceito
created: 2026-11-16
supersedes: ""
superseded_by: ""
---

# ADR 002: Manifestos Kubernetes em YAML puro

## Contexto

O deploy da aplicação no Kubernetes precisa de manifestos (Deployment, Service, ConfigMap,
Secret). Há ferramentas que adicionam templating ou sobreposição de ambientes sobre eles, e
a escolha define como os manifestos são escritos, revisados e aplicados.

## Alternativas Consideradas

- **YAML puro, aplicado com `kubectl apply`** — sem ferramenta adicional, legível e direto;
  não há parametrização nem variação por ambiente.
- **Kustomize** — base mais overlays por ambiente, nativo do `kubectl`; adiciona estrutura de
  diretórios e conceitos extras.
- **Helm** — chart com templates e values, versionamento de release; maior curva e mais
  indireção para uma única aplicação.

## Decisão

Manifestos Kubernetes escritos em YAML puro, sem Kustomize nem Helm. Decisão do responsável
pelo projeto: o deploy é feito a partir dos YAMLs diretamente.

## Consequências

- **Positivas:** os manifestos são lidos e aplicados sem nenhuma ferramenta além do `kubectl`;
  o que está no repositório é exatamente o que vai para o cluster.
- **Negativas:** não há parametrização — a tag da imagem e valores por ambiente são editados
  diretamente nos arquivos. Se surgir um segundo ambiente (ex.: staging), haverá duplicação.
- **Neutras / trade-offs aceitos:** o Secret com credenciais não pode ser versionado com
  valores reais; o processo de criação do Secret no cluster fica fora dos manifestos
  versionados *(premissa — confirme ou corrija)*. Se a duplicação entre ambientes aparecer, o
  caminho natural é um ADR novo adotando Kustomize.
