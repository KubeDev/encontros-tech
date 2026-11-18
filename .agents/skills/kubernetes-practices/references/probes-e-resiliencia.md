# Probes e resiliência

> **Quando ler:** ao escrever os primeiros endpoints `/health`, quando o pod entra em CrashLoopBackOff sem motivo aparente, quando o rolling update derruba tráfego mesmo com `maxUnavailable: 0`, quando você está pensando em PodDisruptionBudget pela primeira vez.

## Índice

1. [Os três tipos de probe e o propósito de cada um](#os-três-tipos-de-probe-e-o-propósito-de-cada-um)
2. [`/livez` vs `/readyz`: por que separar](#livez-vs-readyz-por-que-separar)
3. [O caso clássico do restart loop em cascata](#o-caso-clássico-do-restart-loop-em-cascata)
4. [Configurando intervalos com cabeça](#configurando-intervalos-com-cabeça)
5. [PodDisruptionBudget: protegendo contra drains](#poddisruptionbudget-protegendo-contra-drains)
6. [Replicas e topologia: 1 réplica é zero](#replicas-e-topologia-1-réplica-é-zero)
7. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## Os três tipos de probe e o propósito de cada um

K8s tem 3 tipos de probe que parecem similares mas resolvem problemas distintos:

| Probe | Pergunta que responde | Falha = quê? |
|---|---|---|
| **liveness** | "O processo está vivo e funcional?" | Container é **reiniciado** |
| **readiness** | "O pod pode receber tráfego agora?" | Pod **sai do Service** (não reinicia) |
| **startup** | "O processo já terminou de subir?" | Container é **reiniciado** |

A diferença entre liveness e readiness é a parte mais mal entendida do K8s. Iniciantes frequentemente apontam ambas para o mesmo endpoint — e isso causa problemas reais que aparecem só em produção.

### Liveness: "esse processo travou?"

Liveness existe para **detectar processos travados** (deadlock, loop infinito, evento que faz o processo não atender mais). Quando ela falha por X vezes seguidas, o kubelet **mata o container e reinicia**.

Sintomas que liveness deveria detectar:
- Deadlock interno da app (todas as threads esperando umas às outras)
- Memory leak chegando a um ponto onde GC não dá mais conta
- Evento que travou o event loop (Node), worker pool (Java), main thread (Python sync)

**Liveness é uma ferramenta cirúrgica e perigosa.** Probe mal configurada vira restart loop, e pode ser pior que não ter.

### Readiness: "esse pod pode atender requests?"

Readiness existe para **remover o pod do balanceamento temporariamente**, sem matar o processo. Casos:

- App acabou de subir e está fazendo warm-up (carregar cache, conectar pool)
- Banco de dados ficou indisponível por 30 segundos
- Pool de conexões está saturado e responder agora seria erro

Quando readiness falha, o pod fica `NotReady`, o Service tira ele do balanceamento, **outros pods absorvem o tráfego**. Quando volta a passar, pod entra de volta. Sem reinício, sem perda de estado interno.

### Startup: proteção para apps que sobem devagar

Apps Java/JVM, Python com cache pesado, Rails com inicialização longa podem demorar 60s+ para subir. Liveness com `failureThreshold: 3` e `periodSeconds: 10` daria 30s antes de declarar morte — não chega.

Startup probe **substitui temporariamente** liveness e readiness durante o boot. Tem `failureThreshold` alto (ex: 30), e enquanto não passa, liveness/readiness ficam pausadas.

```yaml
startupProbe:
  httpGet:
    path: /livez
    port: http
  periodSeconds: 5
  failureThreshold: 30   # 5s × 30 = até 150s para subir
```

Use quando o tempo médio de boot do app passa de 30s.

## `/livez` vs `/readyz`: por que separar

A regra mais importante:

> Liveness e readiness **NÃO** devem bater no mesmo endpoint. E o endpoint de liveness **NUNCA** deve depender de serviços externos.

Por quê? Porque os dois respondem a perguntas diferentes:

```
/livez  →  "Eu (esse processo) estou vivo?"     (verifica APENAS coisas internas)
/readyz →  "Eu posso atender request agora?"    (pode verificar deps)
```

### Implementação típica

**`/livez`** — leve, pula tudo que é externo:

```python
@app.get("/livez")
def livez():
    # Só responde 200 se o processo está atendendo
    return {"status": "ok"}
```

Não consulta banco. Não consulta cache. Não consulta API externa. Se o processo consegue rodar essa função, ele está vivo. Ponto.

**`/readyz`** — pode (com cuidado) verificar deps essenciais:

```python
@app.get("/readyz")
def readyz():
    if not db_pool.is_healthy():
        return Response(status_code=503)
    return {"status": "ready"}
```

Se o banco caiu, sair do balanceamento é OK — outros pods também vão sair, e os healthy ainda atendem (talvez nenhum, mas pelo menos o cliente recebe 503 rápido em vez de timeout).

### O que cada uma deve testar

| Componente | Liveness | Readiness |
|---|---|---|
| Processo rodando | ✅ implícito | ✅ implícito |
| Event loop responde | ✅ | ✅ |
| Pool de threads não está exausto | ⚠️ talvez | ✅ |
| Banco de dados disponível | ❌ NUNCA | ✅ |
| Cache (Redis) disponível | ❌ NUNCA | ⚠️ talvez (se essencial) |
| API externa disponível | ❌ NUNCA | ⚠️ talvez |
| Migrations completas | ❌ | ✅ |

## O caso clássico do restart loop em cascata

Cenário real, que acontece em produção quando liveness verifica banco:

```
00:00 — Banco PostgreSQL fica indisponível por 30 segundos (manutenção, glitch de rede).
00:01 — Liveness probe da API tenta conectar ao banco. Timeout. Falha #1.
00:11 — Liveness falha #2.
00:21 — Liveness falha #3 (failureThreshold: 3).
00:22 — Kubelet reinicia o pod.
00:30 — Banco volta. Mas o pod está reiniciando.
00:35 — Pod sobe de novo, tenta conectar ao banco (que volta), passa liveness.
        Mas agora todas as réplicas reiniciaram quase juntas, perdendo conexões abertas, cache em memória, sessões.
        Tráfego continua a chegar e cai sobre pods recém-iniciados, sobrecarregando.
        Cache cold = mais carga no banco que acabou de voltar.
        Banco fica lento. Liveness começa a falhar de novo. Loop.
```

Esse é o caso real "queda do banco virou queda do serviço inteiro". Acontece porque liveness foi confundida com readiness.

A solução era simples: **só readiness deveria checar banco**. Falha do banco → pods saem do Service → 503 retornado rápido → quando banco volta, pods voltam ao Service. **Sem reinício, sem cache cold, sem cascata**.

## Configurando intervalos com cabeça

Os parâmetros que mais importam:

| Parâmetro | O quê | Padrão razoável |
|---|---|---|
| `initialDelaySeconds` | Quantos segundos esperar antes do primeiro check | 0 (use `startupProbe`) |
| `periodSeconds` | De quanto em quanto tempo checar | 10 (liveness), 5 (readiness) |
| `timeoutSeconds` | Tempo máximo da resposta antes de considerar falha | 1-3 |
| `failureThreshold` | Falhas seguidas para declarar fail | 3 (liveness), 2-3 (readiness) |
| `successThreshold` | Sucessos para considerar OK de novo | 1 |

### Por que `initialDelaySeconds` é antipattern moderno

Antes do `startupProbe` (K8s 1.16+), `initialDelaySeconds` era a forma de "esperar a app subir antes de começar liveness". Problema:

- Se você definir 60s e a app sobe em 5s, perde 55s sem proteção
- Se você definir 60s e a app demora 90s num cluster cheio, ela é morta antes de subir

**Use `startupProbe`** em vez disso — ela checa repetidamente, e quando passa, libera as outras probes.

### Para iniciante, padrão razoável

```yaml
startupProbe:
  httpGet:
    path: /livez
    port: http
  periodSeconds: 5
  failureThreshold: 30   # até 150s para subir
  timeoutSeconds: 2

livenessProbe:
  httpGet:
    path: /livez
    port: http
  periodSeconds: 10
  failureThreshold: 3
  timeoutSeconds: 2

readinessProbe:
  httpGet:
    path: /readyz
    port: http
  periodSeconds: 5
  failureThreshold: 2
  timeoutSeconds: 2
```

Calibre conforme observar comportamento real.

## PodDisruptionBudget: protegendo contra drains

Cenário: você tem 3 réplicas. Operador do cluster precisa fazer manutenção em um nó. Roda `kubectl drain node-X`. K8s evicta os pods. Em geral, você quer que **só 1 pod seja evictado por vez**, garantindo que pelo menos 2 estejam atendendo.

PodDisruptionBudget (PDB) é o "contrato" que garante isso:

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: orders
  namespace: marketplace
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: orders
      app.kubernetes.io/component: api
```

Tradução: "no mínimo 2 pods desse selector têm que estar disponíveis. Se um drain quiser tirar o terceiro, espera."

### `minAvailable` vs `maxUnavailable`

Duas formas de expressar:

```yaml
spec:
  minAvailable: 2          # ao menos 2 disponíveis
# ou
spec:
  maxUnavailable: 1        # no máximo 1 indisponível
```

São equivalentes para 3 réplicas. **Prefira `minAvailable`** — é mais previsível quando o número de réplicas muda (por HPA, por exemplo). `maxUnavailable: 1` em 2 réplicas significa só 1 disponível, geralmente não é o que você quer.

### Quando criar PDB

Regra: **toda app com `replicas: 2+` em produção deve ter PDB**.

Exceção: apps stateless triviais que toleram 0 réplicas momentaneamente. Mas se "tolera 0 réplicas", por que tem 2?

### O que PDB **não** protege

PDB protege contra **disruptions voluntárias** (drain, evict). **Não** protege contra:

- Crash do nó (perda involuntária)
- Pod morrendo por OOMKilled
- Liveness probe falhando

Para esses, você precisa de réplicas em nós/zonas diferentes (próxima seção).

## Replicas e topologia: 1 réplica é zero

> Em sistemas distribuídos, "1 réplica" = "0 réplicas durante qualquer evento".

Eventos comuns que derrubam 1 pod:

- Rolling update (você mesmo manda matar)
- Eviction (drain de nó, falta de recursos)
- Crash do nó (hardware, kernel panic, AWS EC2 retirement)
- OOMKilled
- Liveness probe failing transitoriamente

Com 1 réplica, qualquer um desses eventos = 100% downtime.

### `replicas: 2` é mínimo defensivo

Mesmo se sua carga é mínima, 2 réplicas é o piso. Custa quase nada e elimina downtime de manutenção.

### Mas só 2 réplicas + 1 nó = ainda 0

Se ambas as réplicas estão no mesmo nó e o nó cai, vão juntas. K8s tenta espalhar por default (anti-affinity automática), mas pode não conseguir em clusters pequenos.

Para garantir, use `topologySpreadConstraints`:

```yaml
spec:
  template:
    spec:
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app.kubernetes.io/name: orders
```

"Distribua os pods por hostname (= nó), com no máximo 1 de diferença entre nós". Em 3 nós com 3 réplicas: 1+1+1.

Para alta disponibilidade real:

```yaml
        - maxSkew: 1
          topologyKey: topology.kubernetes.io/zone     # AWS AZ, GCP zone
          whenUnsatisfiable: DoNotSchedule
```

Distribui entre zonas de disponibilidade. Queda de uma zona inteira (raro, mas acontece) não derruba sua app.

## Erros comuns de iniciante

### "Liveness e readiness apontam pra `/health` que verifica banco"

Já vimos. Em incidente do banco, vira restart loop. Separe `/livez` (sem deps) de `/readyz` (com deps).

### "Pod fica em `CrashLoopBackOff` e eu não sei por quê"

`CrashLoopBackOff` = container morre logo após subir, kubelet espera (com backoff exponencial) antes de tentar de novo. Investigar:

```bash
kubectl logs pod/<nome> --previous   # logs do crash anterior
kubectl describe pod/<nome>          # eventos, Last State Reason
```

Causas típicas:
- App não consegue subir (config faltando, banco inacessível, env var ausente)
- Liveness mal configurada matando antes de subir → use startupProbe
- App responde 200 em `/livez` antes de estar pronta, recebe tráfego, quebra → use readinessProbe corretamente

### "Por que o rollout zero-downtime mostrou erros 502 nos logs?"

Possíveis causas:
1. Sem `readinessProbe` — pod entra no Service antes de aceitar conexões
2. Sem `preStop` ou grace period suficiente — pod sai do Service depois de já não aceitar conexões
3. Sua app não trata SIGTERM (continua aceitando conexões depois de sinal)

Padrão para evitar:

```yaml
spec:
  terminationGracePeriodSeconds: 30
  containers:
    - name: api
      lifecycle:
        preStop:
          exec:
            command: ["sleep", "5"]
      readinessProbe: ...   # essencial
```

`preStop sleep 5` dá tempo para o load balancer / kube-proxy atualizar antes do app começar a parar.

### "Probes funcionam em dev mas falham em prod"

Causa comum: dev tem 1 réplica e ninguém percebe; prod tem 3 e race conditions aparecem. Outra: prod tem `readOnlyRootFilesystem: true` e o probe usa `curl` que tenta criar arquivo temp em `/`.

### "Coloquei PDB e meu rolling update travou"

PDB com `minAvailable: 2` em Deployment com `replicas: 2` significa "nenhum pod pode sair" — rolling update fica impossível. Suba para 3 réplicas, ou use `maxUnavailable: 1` no PDB.

### "Tenho 1 réplica em produção"

Você não tem alta disponibilidade. Se isso é OK (ambiente interno, ferramenta de uso esporádico), ok. Em qualquer serviço com SLA, mínimo 2.

---

**Princípio que resume tudo:** probes e PDB não são "boas práticas opcionais" — são **a forma como K8s entende o estado do seu app**. Sem elas, você está rodando containers num orquestrador, mas o orquestrador não sabe te ajudar. Com elas configuradas com cabeça (separadas, conservadoras, não dependendo de externos para liveness), o sistema reconcilia incidentes sozinho.
