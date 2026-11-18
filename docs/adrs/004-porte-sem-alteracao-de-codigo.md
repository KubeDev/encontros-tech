---
adr_number: "004"
status: aceito
created: 2026-11-16
supersedes: ""
superseded_by: ""
---

# ADR 004: Porte para contêiner sem alterar o código da aplicação

## Contexto

A aplicação foi escrita para rodar com systemd num servidor. Ao portá-la para Kubernetes,
alguns pontos do código ficam mal adaptados ao novo ambiente:

- não existe endpoint de health para as probes;
- `SECRET_KEY` está fixa no código (`src/main.py`);
- o pool de conexões do SQLAlchemy usa os padrões (5 + 10 de overflow por processo), sem
  configuração;
- as métricas usam `PrometheusMetrics`, não a variante para gunicorn multiprocess;
- o schema é criado com `create_all` no import do módulo, em todo processo.

## Alternativas Consideradas

- **Ajustes mínimos no código junto com o porte** — health endpoint, `SECRET_KEY` por
  variável de ambiente, pool configurável e métricas multiprocess; resolve as lacunas, mas
  mistura mudança de comportamento da aplicação com mudança de empacotamento.
- **Porte sem alteração de código** — apenas Dockerfile, compose e manifestos; as lacunas
  viram riscos aceitos e são contornadas pela infraestrutura.

## Decisão

Portar sem alterar o código da aplicação. Toda adaptação ao Kubernetes é feita no
empacotamento e nos manifestos. Decisão do responsável pelo projeto.

## Consequências

- **Positivas:** a mudança fica restrita a infraestrutura; o comportamento da aplicação é o
  mesmo validado hoje no systemd.
- **Negativas (riscos aceitos):**
  - Probes usam `tcpSocket` na porta da aplicação — detectam processo travado no socket, mas
    não aplicação degradada. Probe HTTP em `/` foi descartada porque consulta o banco e faria
    o liveness falhar em cascata quando o banco oscilar.
  - `SECRET_KEY` continua fixa no código — risco de segurança aceito; como é igual em todas
    as réplicas, sessão e flash funcionam entre pods.
  - `/metrics` reflete só o worker que atendeu a requisição. `PROMETHEUS_MULTIPROC_DIR` **não**
    deve ser definida como variável de ambiente no contêiner, e `/tmp` precisa ser gravável
    (o código cria o diretório ali no import).
  - `create_all` no import pode concorrer entre processos no primeiro deploy; um pod pode
    reiniciar uma vez (ver ADR 006).
- **Neutras / trade-offs aceitos:** o pool de conexões não é configurável; o limite de
  conexões é controlado pela escolha do worker e da quantidade de réplicas (ver ADR 005).
  Cada ajuste descartado aqui pode entrar depois como mudança de código própria.
