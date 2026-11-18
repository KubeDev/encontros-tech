---
adr_number: "007"
status: aceito
created: 2026-11-17
supersedes: ""
superseded_by: ""
---

# ADR 007: Rede da homologação — VPC dedicada, banco por endereço privado e acesso público aceito

## Contexto

A aplicação roda num ambiente de **homologação de um MVP** na DigitalOcean: cluster DOKS,
PostgreSQL gerenciado fora do cluster (ADR 001) e um Load Balancer criado pelo Service
(ADR 003). Esses recursos precisam de uma rede comum. Duas restrições da plataforma tornam a
escolha cara de reverter **[Verificado — docs.digitalocean.com, VPC e DOKS, via Context7, 2026-11-17]**:

- VPC é regional: só recursos da mesma região entram nela.
- Banco gerenciado e Droplets podem ser migrados para outra VPC; **cluster DOKS e Load
  Balancer não**. Trocar a VPC do cluster é recriá-lo.
- Em clusters VPC-native (padrão a partir do Kubernetes 1.31), as sub-redes de pods e de
  services são escolhidas na criação, não podem sobrepor nenhuma VPC do time e não podem ser
  ampliadas depois.

O banco gerenciado expõe um endereço público e um privado, e controla o acesso por *trusted
sources* (cluster k8s, Droplet, tag, IP/CIDR). Um banco **sem nenhuma trusted source aceita
conexões de qualquer origem** **[Verificado — docs.digitalocean.com, PostgreSQL migrate/secure, 2026-11-17]**.

## Alternativas Consideradas

- **VPC padrão da região** — nada a criar; em troca, o projeto divide a rede com qualquer
  outro recurso da conta na região, e o endereçamento não é planejado.
- **VPC dedicada ao projeto** — isolamento de rede e endereçamento próprio; exige criar a VPC
  antes do cluster.
- **Banco restrito ao cluster (trusted source `k8s`) ou a IPs fixos** — reduz a superfície de
  ataque; em troca, acesso administrativo externo (psql, ferramentas) precisa passar por dentro
  do cluster ou por IP cadastrado.
- **Banco aberto a qualquer origem** — acesso administrativo de qualquer lugar; a senha (e o
  TLS) passam a ser a única barreira.

## Decisão

Criar uma **VPC dedicada ao projeto**, na região definida por variável do Terraform
(padrão `nyc1`), com cluster DOKS VPC-native, banco gerenciado e Load Balancer dentro dela.
A aplicação conecta ao banco pelo **endereço privado** (`private_uri`), com `sslmode=require`.

O banco **não tem trusted sources** — aceita conexão de qualquer origem — e a API do cluster
fica sem `control_plane_firewall`. É um risco aceito pelo responsável do projeto porque o
ambiente é de homologação, não de produção.

## Consequências

- **Positivas:** rede isolada do resto da conta; tráfego aplicação → banco fica dentro da VPC;
  acesso administrativo ao banco e ao cluster de qualquer máquina, sem bastion nem cadastro de IP.
- **Negativas:** banco e API do cluster expostos à internet, protegidos só por credencial e
  TLS. **Este desenho não serve para produção** — um ambiente de produção pede ADR novo
  restringindo trusted sources e o control plane.
- **Neutras / trade-offs aceitos:** a região é escolhida antes de criar a infraestrutura;
  mudá-la depois significa destruir e recriar VPC, cluster, Load Balancer e banco. As
  sub-redes de pods e services usam o tamanho padrão (/16 e /19) *(premissa — confirme ou
  corrija)*, sem sobrepor nenhuma VPC do time. Se um dia o banco for restringido, a regra deve
  ser a trusted source do tipo `k8s`, e não o CIDR da VPC: em cluster VPC-native os pods recebem
  IP da sub-rede do cluster, fora do CIDR da VPC *(premissa — confirme ou corrija)*.
