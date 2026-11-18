---
adr_number: "003"
status: aceito
created: 2026-11-16
supersedes: ""
superseded_by: ""
---

# ADR 003: Exposição da aplicação por Service do tipo LoadBalancer

## Contexto

A aplicação web precisa ser acessível de fora do cluster. No Kubernetes, as opções comuns são
um Ingress (com um controller instalado no cluster) ou um Service do tipo LoadBalancer, que
no DOKS provisiona um Load Balancer da DigitalOcean.

## Alternativas Consideradas

- **Ingress com controller** — roteamento por host/caminho, um único ponto de entrada para
  vários serviços, TLS terminado no controller; exige instalar e manter o controller.
- **Service do tipo LoadBalancer** — sem componente extra no cluster; um Load Balancer da
  DigitalOcean por Service, sem roteamento por host/caminho.

## Decisão

Expor a aplicação por um Service do tipo LoadBalancer. Decisão do responsável pelo projeto:
há uma única aplicação a expor, e o Service evita instalar e manter um controller de Ingress.

## Consequências

- **Positivas:** nenhum componente adicional no cluster; o manifesto de exposição é um único
  Service.
- **Negativas:** cada Service LoadBalancer cria um Load Balancer pago na DigitalOcean; não há
  roteamento por domínio ou caminho. Neste ciclo não há TLS público — o tráfego chega por HTTP
  *(premissa — confirme ou corrija)*.
- **Neutras / trade-offs aceitos:** se for preciso TLS, ele pode ser configurado no próprio
  Load Balancer da DigitalOcean por annotations do Service, sem Ingress. Pressupõe que o
  cluster é DOKS *(premissa — confirme ou corrija)*; em outro provedor, o comportamento do
  LoadBalancer muda.
