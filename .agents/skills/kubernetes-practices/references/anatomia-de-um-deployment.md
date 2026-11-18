# Anatomia de um Deployment

> **Quando ler:** ao escrever seu primeiro Deployment, quando você vê manifest pronto e não sabe explicar cada parte, quando o pod sobe mas o Service não roteia tráfego, quando o rolling update está fazendo coisa estranha.

## Índice

1. [O modelo mental: Pod, ReplicaSet, Deployment, Service](#o-modelo-mental-pod-replicaset-deployment-service)
2. [Anatomia comentada de um Deployment + Service](#anatomia-comentada-de-um-deployment--service)
3. [Labels e selectors: o "cabo invisível" que conecta tudo](#labels-e-selectors-o-cabo-invisível-que-conecta-tudo)
4. [Ciclo de vida de um pod: nascimento, vida e morte](#ciclo-de-vida-de-um-pod-nascimento-vida-e-morte)
5. [Rolling update: o que acontece quando você muda a imagem](#rolling-update-o-que-acontece-quando-você-muda-a-imagem)
6. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## O modelo mental: Pod, ReplicaSet, Deployment, Service

Iniciantes em K8s costumam misturar essas quatro coisas. Vamos separar.

### Pod — a unidade básica

Um Pod é "um ou mais containers que compartilham rede e volumes, executando juntos no mesmo nó". Na prática, **um Pod ≈ uma instância da sua app**.

- Tem IP próprio (efêmero — muda quando o pod é recriado)
- Tem hostname próprio
- Pode ter múltiplos containers (raro — geralmente 1, ou 1 + sidecar)

**Você quase nunca cria Pod direto.** Pod sozinho não tem self-healing — se ele morre, ele morre. Você quer que algo o recrie.

### ReplicaSet — mantém N pods rodando

Um ReplicaSet é a entidade que fala "preciso de 3 pods iguais com este template, sempre". Se um pod morre, o ReplicaSet cria outro.

**Você quase nunca cria ReplicaSet direto.** Ele é gerenciado pelo Deployment.

### Deployment — o que você de fato escreve

Um Deployment é "ReplicaSet com superpoderes": tem histórico, suporta rolling update, rollback, paused state.

Quando você muda a imagem em um Deployment, ele cria um **novo ReplicaSet** com a imagem nova e gradualmente desliga o antigo (rolling update).

```
Deployment "api"
├── ReplicaSet "api-abc123" (versão atual, 3 pods rodando)
└── ReplicaSet "api-def456" (versão anterior, 0 pods, mantido para rollback)
```

### Service — o "DNS estável" para os pods

Como o IP do pod muda toda vez que ele é recriado, você não pode hardcodar IP. **Service** é uma abstração que dá:

- Um nome DNS estável (`api.default.svc.cluster.local`, ou só `api` no mesmo namespace)
- Um IP virtual interno (`ClusterIP`) que load-balanceia entre os pods saudáveis
- Resolução automática: quando um pod morre, ele sai do Service. Quando um pod novo sobe e fica `Ready`, ele entra.

### Como tudo se conecta

```
Cliente (outro pod, ou Ingress)
        ↓
    Service "api"  (IP virtual: 10.96.0.42)
        ↓ (selector aponta para os pods certos)
   ┌────┴────┬─────────┐
   ↓         ↓         ↓
 Pod-1     Pod-2     Pod-3   ← gerenciados pelo ReplicaSet
                              ← criado pelo Deployment
```

## Anatomia comentada de um Deployment + Service

Vamos ler um manifest completo, linha por linha. App: API HTTP simples ouvindo na porta 8080.

```yaml
apiVersion: apps/v1
kind: Deployment
```

`apps/v1` é o grupo da API que contém Deployment, ReplicaSet, StatefulSet, DaemonSet. Versão estável desde K8s 1.9.

```yaml
metadata:
  name: orders
  namespace: marketplace
  labels:
    app.kubernetes.io/name: orders
    app.kubernetes.io/component: api
    app.kubernetes.io/version: "1.4.2"
```

- `name` — identificador único dentro do namespace.
- `namespace` — isolamento. **Sempre defina** — sem isso, vai pra `default`, que é antipattern em produção.
- `labels` — tags de classificação. Usadas por Services, NetworkPolicies, monitoring. Use as labels padrão `app.kubernetes.io/*` por questão de interoperabilidade (Lens, ArgoCD, Prometheus reconhecem).

```yaml
spec:
  replicas: 3
```

Quantos pods queremos. Para serviços críticos, 2+ — sempre. Um pod só significa downtime garantido em qualquer manutenção.

```yaml
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
```

Como atualizar:
- `RollingUpdate` (default) — substitui pods gradualmente
- `Recreate` — derruba todos, sobe novos (downtime). Use só quando duas versões não podem coexistir (migração destrutiva)
- `maxSurge: 1` — pode ter até 1 pod a mais durante atualização (4 pods em vez de 3)
- `maxUnavailable: 0` — nenhum pod pode ficar indisponível durante a atualização (zero-downtime)

Combinação `maxSurge: 1` + `maxUnavailable: 0` = zero-downtime mas mais lento. Se quiser mais rápido e tolerar perda momentânea, `maxUnavailable: 1`.

```yaml
  selector:
    matchLabels:
      app.kubernetes.io/name: orders
      app.kubernetes.io/component: api
```

**O selector é fundamental.** Diz para o Deployment: "os pods que você gerencia são os que têm essas labels".

Regra crítica: **nunca inclua `version` no `matchLabels`**. Por quê?

- Quando você muda `version: 1.4.2` → `version: 1.4.3`, o Deployment quer atualizar.
- Mas o selector `version: 1.4.2` não vai mais bater com os pods novos `version: 1.4.3`.
- O Deployment fica confuso, cria pods novos que ele "não reconhece como dele", e os antigos viram órfãos.

Resultado: rollout quebrado, pods antigos rodando para sempre, manualmente ter que limpar.

```yaml
  template:
```

Aqui começa a "receita" do pod. Cada pod gerenciado pelo Deployment é uma cópia desse template.

```yaml
    metadata:
      labels:
        app.kubernetes.io/name: orders
        app.kubernetes.io/component: api
        app.kubernetes.io/version: "1.4.2"   # ← OK aqui, NÃO no selector acima
```

As labels do template precisam **conter** o que o selector exige (caso contrário, Deployment não reconhece o pod). Pode ter labels extras (como `version`), que ajudam para monitoring e queries.

```yaml
    spec:
      containers:
        - name: api
          image: ghcr.io/myorg/orders:1.4.2
```

- `name` — identificador do container dentro do pod. Use `kubectl logs pod -c api`.
- `image` — versão pinada. Nunca `:latest`. Tag imutável (versão semver ou SHA) é o padrão.

```yaml
          ports:
            - name: http
              containerPort: 8080
              protocol: TCP
```

`name: http` — nomeia a porta. Permite que Service e probes referenciem por nome (`port: http`) em vez de número, deixando manifests mais limpos.

```yaml
          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              memory: "256Mi"
```

- `requests` — quanto o scheduler **garante** para o pod. Se o nó não tem 100m de CPU + 128Mi de memória disponíveis, o pod não é colocado lá.
- `limits` — teto. Se o pod ultrapassar memória, é killed (OOMKilled). Se ultrapassar CPU, sofre throttling.
- Sem `requests`, scheduler trata como "BestEffort" — pode colocar em nó já saturado.

```yaml
          livenessProbe:
            httpGet:
              path: /livez
              port: http
            periodSeconds: 10
            failureThreshold: 3
```

Veja `references/probes-e-resiliencia.md` para profundidade. Resumo:
- Liveness verifica se o processo está vivo. Falhar = restart.

```yaml
          readinessProbe:
            httpGet:
              path: /readyz
              port: http
            periodSeconds: 5
            failureThreshold: 2
```

- Readiness verifica se o pod pode receber tráfego. Falhar = sair do Service (sem restart).

```yaml
          envFrom:
            - configMapRef:
                name: orders-config
            - secretRef:
                name: orders-secrets
```

Importa todas as chaves do ConfigMap e Secret como variáveis de ambiente. Veja `references/configuracao-e-secrets.md`.

```yaml
          securityContext:
            runAsNonRoot: true
            runAsUser: 1001
            readOnlyRootFilesystem: true
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
```

Restringe o que o container pode fazer:
- `runAsNonRoot: true` + `runAsUser: 1001` — não roda como root.
- `readOnlyRootFilesystem: true` — `/` é read-only. Se a app precisa escrever, monte volume em path específico.
- `allowPrivilegeEscalation: false` — não pode virar root via setuid.
- `capabilities.drop: ["ALL"]` — remove todas as capabilities Linux. Reabra com `add` se precisar.

```yaml
---
apiVersion: v1
kind: Service
metadata:
  name: orders
  namespace: marketplace
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: orders
    app.kubernetes.io/component: api
  ports:
    - name: http
      port: 80
      targetPort: http
```

- `type: ClusterIP` — só acessível dentro do cluster. Para expor pra fora, use Ingress (separado).
- `selector` — encontra pods pela label. Note que **o selector do Service é independente** do selector do Deployment. Você poderia ter um Service que seleciona pods de múltiplos Deployments.
- `targetPort: http` — usa o nome da porta declarada no container. Se o número mudar lá, aqui não precisa mudar.

## Labels e selectors: o "cabo invisível" que conecta tudo

K8s não tem "links explícitos" entre objetos. Tudo conecta por **labels e selectors** — um sistema de etiquetas livres.

```
Deployment.spec.selector.matchLabels = { name: orders, component: api }
                ↓ (deve "casar")
Pod.metadata.labels = { name: orders, component: api, version: 1.4.2 }
                ↑ (deve "casar")
Service.spec.selector = { name: orders, component: api }
```

Se a label do pod muda, o Service "para de ver" o pod automaticamente — sem reconfigurar nada.

### As labels padrão `app.kubernetes.io/*`

Convenção do K8s para labels — usar isso ajuda integração com ferramentas:

| Label | O quê |
|---|---|
| `app.kubernetes.io/name` | Nome da app |
| `app.kubernetes.io/instance` | Instância única (mesma app rodando múltiplas vezes) |
| `app.kubernetes.io/version` | Versão (NÃO incluir em `matchLabels` de Deployment) |
| `app.kubernetes.io/component` | Papel: `api`, `worker`, `cache` |
| `app.kubernetes.io/part-of` | Sistema maior (`marketplace`) |
| `app.kubernetes.io/managed-by` | `helm`, `argocd`, `raw` |

### Por que `version` em `matchLabels` quebra rollout

Já mencionado, mas vale repetir com diagrama:

```
Antes (versão 1):
Deployment.selector = { name: orders, version: "1" }
Pods existentes:    [ pod-A: {name: orders, version: "1"} ]   ✓ casa

Você muda template para version: "2" e aplica:
Pods novos criados:  [ pod-B: {name: orders, version: "2"} ]
Selector ainda é:    { name: orders, version: "1" }           ✗ não casa com pod-B
```

O Deployment não reconhece pod-B como seu. O ReplicaSet novo trabalha em paralelo, mas o controle do Deployment fica inconsistente. Em rollouts subsequentes, comportamento imprevisível.

**Regra:** `selector.matchLabels` usa só labels **estáveis** — coisas que nunca mudam para a mesma app. `name`, `component`, talvez `instance`. Versão fica fora.

## Ciclo de vida de um pod: nascimento, vida e morte

Compreender essas fases ajuda muito a debugar.

### Nascimento

1. Você aplica o Deployment.
2. Deployment cria/atualiza o ReplicaSet.
3. ReplicaSet pede ao API server: "preciso de mais um pod".
4. Scheduler escolhe um nó com recursos suficientes.
5. Kubelet do nó puxa a imagem (se não tiver cache).
6. Kubelet cria o container, define rede e volumes.
7. Container começa a rodar.
8. **Startup probe** (se houver) — kubelet espera passar antes de começar liveness.
9. **Liveness probe** começa a rodar — se falhar, container é reiniciado.
10. **Readiness probe** começa — pod fica `Ready` quando passa.
11. Service incluiu o IP do pod no endpoints.
12. Tráfego começa a chegar.

### Vida

- Liveness rodando periodicamente. Se falhar X vezes seguidas, container restart (kubelet).
- Readiness rodando. Se falhar, pod sai do Service (não recebe tráfego), mas continua existindo.
- Recursos monitorados. Se ultrapassar memória, OOMKilled (vira restart).

### Morte (graceful)

Quando você faz `kubectl delete pod` ou rolling update remove o pod:

1. **Pod marcado como `Terminating`** no API server.
2. Pod **sai do Service imediatamente** (endpoints atualizados).
3. Tráfego novo deixa de chegar.
4. **`preStop` hook executa**, se definido — boa hora para drenar conexões, avisar deps.
5. Kubelet envia **SIGTERM** ao processo principal.
6. Processo deve fazer graceful shutdown (terminar requests pendentes, fechar conexões, salvar estado).
7. **Grace period** — default 30s. Tempo para o processo sair sozinho.
8. Se ainda estiver rodando após o grace period, kubelet envia **SIGKILL**. Sem chance de cleanup.

```yaml
spec:
  terminationGracePeriodSeconds: 60
  containers:
    - name: api
      lifecycle:
        preStop:
          exec:
            command: ["sh", "-c", "sleep 5"]
```

`preStop: sleep 5` é truque comum: dá tempo para o load balancer atualizar antes de o app parar de aceitar conexões.

### Por que isso importa em apps reais

App que não trata SIGTERM = conexões abertas são derrubadas no SIGKILL = clientes recebem `connection reset`. Usuário vê erro.

App que trata SIGTERM corretamente = drenagem limpa, zero erros visíveis para usuário.

Lembre-se da forma exec no Dockerfile (`CMD ["node", "app.js"]`, não `CMD node app.js`) — sem ela, sinais não chegam ao processo certo.

## Rolling update: o que acontece quando você muda a imagem

Cenário: Deployment com 3 réplicas rodando `1.4.2`. Você muda para `1.4.3` e `kubectl apply`.

Passo a passo (com `maxSurge: 1, maxUnavailable: 0`):

```
T=0 (estado inicial):
ReplicaSet 1.4.2: [pod-A, pod-B, pod-C]   3/3 ready
ReplicaSet 1.4.3: []                       0/0

T=1 (Deployment cria novo RS, escala +1):
ReplicaSet 1.4.2: [pod-A, pod-B, pod-C]   3/3 ready
ReplicaSet 1.4.3: [pod-D]                  0/1 (subindo)

T=2 (pod-D fica Ready):
ReplicaSet 1.4.2: [pod-A, pod-B, pod-C]   3/3 ready
ReplicaSet 1.4.3: [pod-D]                  1/1 ready
   → 4 pods servindo tráfego (surge de 1)

T=3 (Deployment escala RS antigo -1):
ReplicaSet 1.4.2: [pod-B, pod-C]           2/2 ready (pod-A em terminating)
ReplicaSet 1.4.3: [pod-D]                  1/1 ready

T=4 (cria mais um novo):
ReplicaSet 1.4.2: [pod-B, pod-C]           2/2 ready
ReplicaSet 1.4.3: [pod-D, pod-E]           1/2 (subindo)

... e assim por diante até:

T=N:
ReplicaSet 1.4.2: []                       0/0 (mantido para rollback)
ReplicaSet 1.4.3: [pod-D, pod-E, pod-F]    3/3 ready
```

### Rollback

```bash
kubectl rollout undo deployment/orders
```

Volta para o último ReplicaSet que tinha pods. K8s mantém histórico configurável (`revisionHistoryLimit`, default 10).

### O que pode dar errado num rolling update

| Sintoma | Causa provável |
|---|---|
| Pods novos travam em `0/1 Running` para sempre | Probe não passa. App quebrada na nova versão? `kubectl describe pod`, `kubectl logs` |
| Erro de imagem `ErrImagePull` ou `ImagePullBackOff` | Tag errada, registry inacessível, secret de pull faltando |
| Rollout travado em "X of Y updated" | Provavelmente PDB bloqueando ou quota esgotada |
| Service para de responder durante o rollout | `maxUnavailable` muito alto, ou app sem readiness probe |

## Erros comuns de iniciante

### "Apliquei o Deployment, pod sobe, mas Service não responde"

Possibilidades:
- **Selector do Service não casa com labels do pod.** Confira `kubectl get svc -o yaml` e `kubectl get pods --show-labels`.
- **Pod não está `Ready`.** Service só roteia para pods Ready. Se readiness não passa, pod não entra. `kubectl get pods` (coluna READY).
- **Porta errada.** `targetPort` do Service tem que casar com `containerPort` do pod (ou o nome, se usar nome).

### "Mudei o ConfigMap mas a app não viu a mudança"

Mudanças em ConfigMap/Secret **não disparam restart automático** dos pods que os usam. Soluções:
- Faça `kubectl rollout restart deployment/orders` manualmente
- Use checksum em annotation do template para forçar rollout (Helm: `checksum/config: {{ ... | sha256sum }}`)

### "Pod fica em CrashLoopBackOff"

App está caindo logo depois de subir. `kubectl logs pod/<nome> --previous` mostra a saída do container que crashou. Causas típicas:
- Variável de ambiente faltando
- Dependência (banco) não acessível
- Erro de configuração na imagem

### "Memory limit muito baixo, OOMKilled toda hora"

`kubectl describe pod` mostra `Last State: Terminated, Reason: OOMKilled`. Aumente `limits.memory`, OU descubra leak na app.

### "kubectl exec funciona em dev e em staging, mas em prod o pod tem `readOnlyRootFilesystem: true`"

`kubectl exec` funciona, mas comandos que tentam escrever em `/` falham. Isso é correto — produção é mais restritiva. Você precisa montar `/tmp` como `emptyDir` ou usar volume específico para qualquer escrita.

### "Rolei direto pra produção sem usar staging porque Deployment tem rolling update"

Rolling update protege contra **erros de runtime** (zero downtime durante a troca), não contra **erros de design** (a versão nova faz coisa errada com o banco). Sempre tem que ter staging.

---

**Princípio que resume tudo:** um Deployment não é "uma app rodando". É **a especificação de um estado desejado**, e o K8s faz tudo para reconciliar a realidade com a especificação. Quanto mais explícito você for nas labels, selectors, probes e recursos, mais previsível o sistema fica em cima desse loop de reconciliação.
