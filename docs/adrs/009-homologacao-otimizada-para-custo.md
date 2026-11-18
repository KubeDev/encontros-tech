---
adr_number: "009"
status: aceito
created: 2026-11-17
supersedes: ""
superseded_by: ""
---

# ADR 009: Ambiente de homologação dimensionado para custo baixo

## Contexto

O ambiente na DigitalOcean é de **homologação de um MVP**, não de produção. A prioridade
declarada é custo baixo e ambiente enxuto; disponibilidade é conveniência, não requisito. Os
padrões da plataforma puxam para o lado oposto: a partir do Kubernetes 1.36, o DOKS liga o
**control plane em alta disponibilidade por padrão**, e uma vez ligado ele **não pode ser
desligado** **[Verificado — docs do provider `digitalocean_kubernetes_cluster`, via Context7, 2026-11-17]**.

Opções disponíveis na conta **[Verificado — `doctl`, 2026-11-17]**:

- DOKS: 1.37.2, 1.36.6, 1.35.10, 1.34.13; menor nó `s-1vcpu-2gb`.
- PostgreSQL gerenciado: versões 15 a 18; menor plano `db-amd-1vcpu-1gb`, que só admite 1 nó.

## Alternativas Consideradas

- **Desenho com alta disponibilidade** — control plane HA, banco com nó standby, autoscaling de
  nós; resiste a falhas, em troca de custo fixo bem maior, sem retorno para homologação.
- **Mínimo absoluto (1 nó)** — mais barato; em troca, uma falha ou troca de nó derruba o ambiente.
- **Enxuto com 2 nós** — control plane sem HA e banco com 1 nó, mas 2 nós de trabalho.

## Decisão

Dimensionar a homologação para custo:

- Control plane **sem HA**, com `ha = false` escrito **explicitamente** no Terraform (o padrão
  é `true` e irreversível).
- **2 nós** `s-1vcpu-2gb`, sem autoscaling. Patch automático do Kubernetes ligado; versão do
  Kubernetes como variável, valor inicial `1.37.2-do.0`.
- Banco `db-amd-1vcpu-1gb`, **1 nó, sem standby**, PostgreSQL 18.
- Mantém o Service LoadBalancer (ADR 003): o IP estável para quem testa vale o custo, porque um
  `NodePort` mudaria de IP a cada troca de nó.

Os dados da homologação são descartáveis: recriar o banco não exige migração *(premissa —
confirme ou corrija)*.

## Consequências

- **Positivas:** custo fixo mínimo compatível com 2 réplicas distribuídas; com 2 nós, a
  aplicação continua no ar se um nó cair ou durante o upgrade.
- **Negativas:** sem HA no control plane, a API do cluster pode ficar indisponível durante
  manutenção (a aplicação segue rodando). Sem standby, uma falha do banco derruba o ambiente
  até a DigitalOcean recuperar o nó.
- **Neutras / trade-offs aceitos:** o banco de 1 GiB oferece 22 conexões, e o orçamento do
  ADR 005 continua valendo sem mudança. O surge upgrade cria um nó extra só durante a
  atualização. Promover este ambiente a produção pede ADR novo revendo HA do control plane e
  standby do banco.
