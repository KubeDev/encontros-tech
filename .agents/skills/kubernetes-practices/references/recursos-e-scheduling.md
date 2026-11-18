# Recursos e scheduling

> **Quando ler:** ao definir `requests` e `limits` pela primeira vez e não saber que números colocar, quando seu pod fica em `Pending` e você não sabe por quê, quando OOMKilled aparece nos logs, quando você está pensando em HPA.

## Índice

1. [O que requests e limits significam de fato](#o-que-requests-e-limits-significam-de-fato)
2. [Como o scheduler decide onde colocar o pod](#como-o-scheduler-decide-onde-colocar-o-pod)
3. [QoS classes: Guaranteed, Burstable, BestEffort](#qos-classes-guaranteed-burstable-besteffort)
4. [O dilema do CPU limit](#o-dilema-do-cpu-limit)
5. [HPA: autoscaling que faz sentido](#hpa-autoscaling-que-faz-sentido)
6. [Namespaces como unidade de governança](#namespaces-como-unidade-de-governança)
7. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## O que requests e limits significam de fato

Iniciantes pensam: "request é o que vou pedir, limit é o teto". Quase. A realidade é mais sutil — e entender muda como você dimensiona.

### Requests

`resources.requests` é **o quanto o pod *garantidamente* terá disponível** no nó. O scheduler usa isso para decidir onde colocar o pod:

- Se o nó tem 4 CPUs disponíveis e seu pod pede `requests.cpu: 500m` (= 0.5 CPU), cabe.
- Se o nó tem 1 GB livre e seu pod pede `requests.memory: 2Gi`, **não** cabe — vai pra outro nó, ou fica `Pending`.

**Requests não impede o pod de usar mais.** Se você pede 100m de CPU mas o nó tem CPU ocioso, seu pod pode usar 1, 2, 4 cores temporariamente — desde que ninguém mais precise. O request só garante o **piso** durante contenção.

### Limits

`resources.limits` é **o teto absoluto**:

- `limits.memory` — pod ultrapassou? **OOMKilled**. Container morre, kubelet reinicia. Sem perdão.
- `limits.cpu` — pod usando demais? **Throttled**. Não morre, mas pode ficar muito mais lento. Aplicação não trava, fica devagar.

A assimetria é importante: ultrapassar memória mata, ultrapassar CPU desacelera.

### Por que não basta um?

Sem `requests` (BestEffort): scheduler não tem critério, pode colocar em nó já saturado. Pod pode entrar em "concorrência por recursos" e ter performance imprevisível.

Sem `limits`: pod pode "escapar" e consumir todos os recursos do nó, derrubando outros pods.

Os dois são diferentes ferramentas: requests dimensiona o **planejamento**, limits dimensiona o **comportamento de exceção**.

### Como descobrir os números certos

A pergunta sempre vem: "que número eu coloco?". Sem métricas, é chute. Estratégia:

1. **Dia 1:** chute conservador baseado em testes locais. `requests.cpu: 100m, requests.memory: 128Mi, limits.memory: 256Mi`.
2. **Suba e observe.** Use `kubectl top pods` ou Prometheus + Grafana para ver uso real.
3. **Refine semanalmente.** Olhe percentis: `requests` ≈ p50 do uso, `limits.memory` ≈ p99 + margem.
4. **Em escala**, use VPA (Vertical Pod Autoscaler) em modo `recommend` para sugerir números baseados em histórico.

Erro mais comum: copiar número de um exemplo da internet e nunca revisitar. App muda, padrão de uso muda, recursos precisam acompanhar.

## Como o scheduler decide onde colocar o pod

Quando você cria um pod (direto ou via Deployment), o scheduler:

1. **Filtra nós** que cumprem requisitos:
   - Tem `requests.cpu` + `requests.memory` disponíveis (somando o que outros pods já reservam)
   - Atende `nodeSelector`/`affinity` se definidos
   - Tem volumes acessíveis
   - Não tem `taints` que o pod não tolera
2. **Pontua os nós restantes** por critérios (espalhar, balancear uso, afinidade).
3. **Coloca o pod no nó com maior pontuação**.

Se nenhum nó passa pelo filtro, pod fica em `Pending`. `kubectl describe pod` mostra o motivo:

```
Events:
  Warning  FailedScheduling  3s  default-scheduler  0/3 nodes are available:
    1 Insufficient memory, 2 node(s) had taints that the pod didn't tolerate.
```

### Por que pods ficam em `Pending` em produção

Causas comuns:

| Mensagem | O que significa |
|---|---|
| `Insufficient cpu` / `Insufficient memory` | Cluster cheio. Considere autoscaler de nós ou reduzir requests. |
| `taints that the pod didn't tolerate` | Nós têm taints (geralmente para isolar workloads); seu pod não tolera. |
| `node(s) didn't match Pod's node affinity` | Pod tem nodeSelector/affinity que nenhum nó satisfaz. |
| `No preemption victims found for incoming pod` | Sem espaço e sem pods de prioridade menor para preempção. |

### Reservar espaço para pods do sistema

Em produção, você quase nunca quer "encher" todos os nós até 100%. Deixe folga (~20%) para:
- Pods do sistema (CNI, kube-proxy, monitoring agents)
- Bursting temporário de workloads existentes
- Tolerância a falha de um nó (cluster com 5 nós precisa caber em 4 quando um cair)

## QoS classes: Guaranteed, Burstable, BestEffort

K8s atribui automaticamente uma "classe de qualidade" ao pod baseado em como você definiu requests/limits. Isso afeta **quem morre primeiro** quando o nó fica sem memória.

### Guaranteed

`requests == limits` para CPU e memória, em todos os containers.

```yaml
resources:
  requests:
    cpu: "500m"
    memory: "256Mi"
  limits:
    cpu: "500m"      # igual ao request
    memory: "256Mi"  # igual ao request
```

K8s entende: "esse pod precisa exatamente disso. É uma reserva firme."

- Última prioridade em OOM kill (último a morrer).
- Sem oportunidade de "burst" — não usa mais que pediu.
- Bom para workloads críticos, latência sensível.

### Burstable (mais comum)

`requests` definidos, `limits` maior que `requests` ou só limits parcial.

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"
```

K8s entende: "esse pod precisa do mínimo, mas pode usar mais quando há folga."

- Prioridade média em OOM kill.
- Bom para a maioria das apps.

### BestEffort

Sem `requests` nem `limits` em nenhum container.

```yaml
resources: {}
```

K8s entende: "esse pod aceita qualquer coisa".

- Primeiro a morrer em OOM.
- Scheduler pode colocar em qualquer lugar.
- Use só para jobs experimentais, batch sem importância.

### Tabela resumo

| Classe | requests | limits | Prioridade OOM | Uso típico |
|---|---|---|---|---|
| **Guaranteed** | == limits | == requests | Última a morrer | Crítico, latência |
| **Burstable** | < limits ou só requests | qualquer | Média | Maioria das apps |
| **BestEffort** | Nenhum | Nenhum | Primeira a morrer | Jobs experimentais |

## O dilema do CPU limit

Há debate na comunidade sobre **se vale a pena pôr `limits.cpu`**. Os dois lados:

### Argumento PRÓ-limit

- Previne pod runaway de monopolizar CPU do nó
- Faz comportamento determinístico — você sabe que pod nunca vai usar mais que X
- Compliance e cost predictability

### Argumento CONTRA-limit

- Throttling do CPU em K8s (via cgroups CFS) tem comportamento contraintuitivo: pod com limit `1000m` (1 core) e burst de threads pode ser throttled mesmo se total < 1 core
- Apps multi-thread (Java, Go, Node com workers) podem ter latency spikes inesperados
- Para apps com latência sensível, limit pode causar mais problema do que resolve

### Heurística para iniciante

- **Sempre `requests.cpu`** — é o que o scheduler usa
- **`limits.memory` sempre** — leak descontrolado é pior que OOMKill controlado
- **`limits.cpu` opcional** — comece sem; adicione se observar runaway de fato

```yaml
# Padrão razoável para iniciar
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"
    # cpu limit deliberadamente ausente
```

Conforme observa, ajusta.

## HPA: autoscaling que faz sentido

Horizontal Pod Autoscaler escala **número de réplicas** baseado em métricas (CPU, memória, custom).

### O caso simples

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: orders
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: orders
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
```

Tradução: "Mantenha entre 3 e 20 réplicas, ajustando para que o uso médio de CPU fique em torno de 70% do `requests.cpu`."

### Por que CPU às vezes é métrica ruim

Para muitas apps, CPU não reflete carga real:

- API que faz IO bloqueante: tráfego dobra mas CPU mal sobe (espera em rede)
- Worker que faz crypto: CPU já fica em 100% mesmo com 1 task; mais réplicas não ajudam
- App em event loop (Node, Python async): scaling por CPU pode escalar tarde

Métricas melhores frequentemente:
- **Requisições por segundo** (RPS por pod) — via custom metrics
- **Latência (p95)** — sobe antes do CPU em apps IO-bound
- **Tamanho da fila** (workers) — sinal direto da carga

Para iniciante, comece com CPU. É o que vem out-of-the-box (metrics-server). Migre para custom metrics quando você entender o gargalo da sua app.

### `behavior` para evitar flapping

HPA agressivo escala-down rápido demais e cria oscilação:

```
12:00 — pico de tráfego, escala de 3 para 8 réplicas
12:05 — pico passa, escala de 8 para 3 (rápido)
12:06 — chegada de novo pico, escala 3 para 7
12:11 — passa, escala para 3 de novo
... pods ficam subindo e descendo, perdendo cache, gerando latência
```

Configure `behavior` para conservadorismo no scale-down:

```yaml
spec:
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300   # espera 5min de baixa antes de tirar pod
      policies:
        - type: Percent
          value: 50                     # no máximo 50% das réplicas tiradas por vez
          periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0     # escala-up rápido
      policies:
        - type: Percent
          value: 100
          periodSeconds: 60
```

Padrão: scale-up rápido (responde a tráfego), scale-down lento (evita flapping).

### `minReplicas` ≥ 2

Mesmo que HPA possa ir a 1 em horário tranquilo, mantenha `minReplicas: 2+` para resiliência. Custo de 1 réplica extra a noite vale a noite tranquila quando algo falha.

## Namespaces como unidade de governança

Namespace em K8s não é "pasta". É **unidade de isolamento** para:

- **Quotas** (`ResourceQuota`) — quanto CPU/memória/pods o time pode usar no total
- **LimitRanges** — defaults e máximos de requests/limits
- **RBAC** — quem pode fazer o quê
- **NetworkPolicies** — quem fala com quem
- **DNS** — pods veem `service.namespace.svc.cluster.local`

### Estratégias comuns

| Estratégia | Quando |
|---|---|
| Um namespace por **time** | Time pequeno, app única ou poucas |
| Um namespace por **aplicação** | Múltiplas apps por time, com configs/segredos próprios |
| Um namespace por **ambiente** + por **app** (`orders-staging`, `orders-prod`) | Multi-environment no mesmo cluster |
| Cluster separado por ambiente, namespace por app | Produção crítica |

### ResourceQuota: limite total por namespace

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: marketplace-quota
  namespace: marketplace
spec:
  hard:
    requests.cpu: "10"
    requests.memory: "20Gi"
    limits.memory: "40Gi"
    pods: "50"
```

Garante que time/app não monopoliza o cluster. Tentar criar pod além da quota retorna erro.

### LimitRange: default e máximo por pod

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: defaults
  namespace: marketplace
spec:
  limits:
    - default:
        cpu: "500m"
        memory: "512Mi"
      defaultRequest:
        cpu: "100m"
        memory: "128Mi"
      max:
        cpu: "2"
        memory: "4Gi"
      type: Container
```

- Pod sem requests/limits ganha defaults automaticamente.
- Pod tentando ultrapassar `max` é rejeitado.

Útil para garantir que ninguém esquece de definir e que ninguém pede absurdo.

### Nunca produção em `default`

Namespace `default` existe para experimentação rápida. Em produção:

- Sem isolamento natural (todo mundo cai no mesmo lugar)
- RBAC default geralmente permissivo
- Difícil aplicar políticas (NetworkPolicy, quotas) sem afetar tudo

Crie namespaces explícitos. Sempre.

## Erros comuns de iniciante

### "Pod fica em Pending e diz `Insufficient memory`"

Cluster cheio, ou seu pod pede demais. Caminhos:

- Reduzir `requests.memory` — talvez você esteja superestimando
- Verificar se o cluster tem cluster autoscaler que adicionaria nós
- Aumentar tamanho dos nós

### "OOMKilled mesmo com `limits.memory: 2Gi`"

App está realmente usando 2Gi+. Não é falha do K8s — é leak ou uso real maior que esperado. Investigue:

- `kubectl describe pod` mostra `Last State: Terminated, Reason: OOMKilled`
- Use heap dump / profiler da linguagem
- Considere se o número real é mesmo 2Gi+ ou se há leak

### "App ficou lenta depois de adicionar `limits.cpu`"

Throttling do CFS (Completely Fair Scheduler) em cgroups. Apps multi-thread com bursts curtos sofrem mais. Considere:

- Aumentar `limits.cpu`
- Remover `limits.cpu` (deixar só `requests.cpu`)
- Apps Java: setar `-XX:ActiveProcessorCount` baseado no limit

### "HPA escala para 1 réplica em horário ocioso e PDB trava"

`HPA.minReplicas: 1` + `PDB.minAvailable: 1` = bloqueia drain. Configure `HPA.minReplicas: 2+`.

### "Coloquei requests altíssimos pra garantir performance e o pod nem entra no cluster"

Requests não é "performance garantida acima de X". É "espaço reservado". Pedir 4 CPUs num cluster onde maior nó tem 4 CPUs significa pod nunca cabe (mais coisa do sistema também precisa).

### "Defini limits e requests baseado em valor do dev local"

Dev local geralmente é minúsculo comparado a produção. Carga real revela que `requests.memory: 64Mi` no dev vira `400Mi` em prod sob carga. Sempre baseie em métricas de prod (ou staging com tráfego representativo).

### "Namespace? Eu uso default mesmo, é mais fácil"

Por enquanto. Quando seu time crescer, ou outro time chegar, ou compliance pedir isolamento, vai dar trabalho retroativo. Crie namespace desde o dia 1.

---

**Princípio que resume tudo:** recursos no K8s não são "limitar para não estourar". São **a forma como você comunica para o cluster as necessidades e tolerâncias da sua app**. Bem dimensionados, o cluster aloca eficientemente, escala automaticamente, e mata o pod certo na hora certa. Mal dimensionados, ou você tem desperdício gigante (over-provisioning) ou apaga o serviço em incidentes (under-provisioning).
