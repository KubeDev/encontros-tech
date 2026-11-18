---
name: kubernetes-practices
description: "Boas práticas e padrões de qualidade para manifests Kubernetes (YAML) na perspectiva de app developer. Use esta skill sempre que estiver escrevendo, revisando ou modificando arquivos YAML com `kind:` (Deployment, Service, Pod, ConfigMap, Secret, Ingress, HPA, PodDisruptionBudget) ou `apiVersion:` de APIs K8s (apps/, networking.k8s.io/, autoscaling/, policy/, v1 core), arquivos em diretórios `k8s/`, `manifests/` ou `kubernetes/`, ou executando comandos `kubectl`. Cobre labels, deployments, services, probes, resource limits, ConfigMaps/Secrets, HPA, security context e ingress. Ativar mesmo quando o usuário não pedir explicitamente por 'boas práticas' — basta a tarefa envolver manifests K8s. Não cobre Helm, Kustomize, cluster operator (RBAC, network policies, admission controllers) nem instalação de cluster."
---

# Kubernetes Practices

Guia prescritivo de boas práticas para manifests Kubernetes na perspectiva de app developer (quem deploya apps em clusters existentes). Aplique estas convenções diretamente ao código sem explicar cada decisão — o objetivo é consistência, disponibilidade e eficiência, não ensinar conceitos.

## Quando aprofundar

Os guias em `references/` aprofundam o "porquê" das práticas e cobrem casos do mundo real. Carregue sob demanda quando:

| Cenário | Reference |
|---|---|
| Escrevendo primeiro Deployment, entendendo como Pod/Service/Deployment se conectam, ou Service não roteia tráfego | `references/anatomia-de-um-deployment.md` |
| Configurando primeiras probes, pod entra em CrashLoopBackOff, rolling update derruba tráfego, pensando em PDB | `references/probes-e-resiliencia.md` |
| Definindo requests/limits, pod fica em Pending, OOMKilled aparece, configurando HPA, organizando namespaces | `references/recursos-e-scheduling.md` |
| Injetando primeira variável, mudando ConfigMap e app não viu, montando certificados, pensando em rotação | `references/configuracao-e-secrets.md` |

## Labels e selectors

### Labels recomendadas

Use as labels padrão `app.kubernetes.io/*` — facilitam integração com ferramentas (Lens, ArgoCD, Prometheus).

- `app.kubernetes.io/name` — nome da aplicação
- `app.kubernetes.io/instance` — instância única (quando a mesma app roda múltiplas vezes)
- `app.kubernetes.io/version` — versão da app
- `app.kubernetes.io/component` — papel (api, worker, cache)
- `app.kubernetes.io/part-of` — sistema maior ao qual pertence
- `app.kubernetes.io/managed-by` — ferramenta que gerencia (Helm, ArgoCD, raw)

```yaml
metadata:
  labels:
    app.kubernetes.io/name: orders
    app.kubernetes.io/instance: orders-prod
    app.kubernetes.io/version: "1.4.2"
    app.kubernetes.io/component: api
    app.kubernetes.io/part-of: marketplace
```

### Selectors

- `selector.matchLabels` deve usar apenas labels estáveis — **nunca** inclua `version` em selectors
- Mudança de versão com `version` no selector quebra rollouts e gera pods órfãos

```yaml
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: orders
      app.kubernetes.io/component: api
  template:
    metadata:
      labels:
        app.kubernetes.io/name: orders
        app.kubernetes.io/component: api
        app.kubernetes.io/version: "1.4.2"  # só aqui, não em matchLabels
```

## Deployments

### Tags e imagens

- Nunca use `:latest` — sempre tag imutável (versão semântica ou SHA)
- `imagePullPolicy: IfNotPresent` é o default seguro para tags imutáveis

### Estratégia de rollout

- `RollingUpdate` é o default para serviços stateless — configure `maxSurge` e `maxUnavailable` conforme capacidade do cluster
- `Recreate` apenas quando o app não tolera duas versões rodando simultaneamente (migrações destrutivas, singleton)

```yaml
spec:
  replicas: 3
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0  # zero-downtime
```

### Réplicas mínimas

- Sempre 2+ réplicas para serviços críticos — resiliência a falha de nó
- Combine com `PodDisruptionBudget` para garantir disponibilidade durante drains

## Services

### Tipos de Service

- `ClusterIP` (default) — tráfego interno ao cluster, padrão para microsserviços
- `NodePort` — expõe em porta do nó; útil em dev/on-prem sem load balancer
- `LoadBalancer` — provisiona LB externo (cloud); custo por service, prefira Ingress para HTTP
- `ExternalName` — alias DNS para serviço externo

### Regras

- Use `ClusterIP` + Ingress para HTTP/HTTPS — um LB serve múltiplos hosts/paths
- Evite `LoadBalancer` direto em cada serviço HTTP — explode custo
- Nomeie portas (`name: http`) — permite referência por nome em probes e ingress

```yaml
apiVersion: v1
kind: Service
metadata:
  name: orders
spec:
  type: ClusterIP
  selector:
    app.kubernetes.io/name: orders
  ports:
    - name: http
      port: 80
      targetPort: http  # referência por nome
```

## Probes

### Três tipos, três propósitos

- **livenessProbe** — reinicia o pod quando o app trava (deadlock, loop). Use com cautela: probe errado causa restart loop
- **readinessProbe** — remove o pod do balanceamento quando não pode atender. Use sempre que o app tem warm-up ou dependências externas
- **startupProbe** — proteção inicial para apps lentos para subir. Desabilita liveness até passar. Use quando startup passa de 30s

### Regras

- Liveness e readiness geralmente **não** devem bater no mesmo endpoint
- Liveness: endpoint que só verifica o processo local (health interno)
- Readiness: pode verificar dependências (banco, cache) — falhar readiness é aceitável durante incidentes
- Nunca compartilhe probe que depende de serviço externo entre liveness e readiness — falha externa vira restart loop

```yaml
livenessProbe:
  httpGet:
    path: /livez
    port: http
  periodSeconds: 10
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /readyz
    port: http
  periodSeconds: 5
  failureThreshold: 2

startupProbe:
  httpGet:
    path: /livez
    port: http
  periodSeconds: 5
  failureThreshold: 30  # 2.5 min para subir
```

## Resource requests e limits

### Requests

- `requests` é o que o scheduler usa para colocar pod em nó — deve refletir uso real médio
- Sem requests, pod compete por recursos sem garantia — QoS vira BestEffort

### Limits

- `limits.memory` ativo — pod excedendo é killed (OOMKilled)
- `limits.cpu` sujeito a debate — throttling pode causar latência inesperada; alguns times omitem CPU limit deliberadamente
- Comece com limits conservadores e ajuste com métricas reais (VPA em modo "recommend")

```yaml
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    memory: "256Mi"
    # cpu limit opcional — avaliar com base em métricas
```

## ConfigMaps e Secrets

### Separação

- **ConfigMap** para configuração não sensível (URLs, feature flags, níveis de log)
- **Secret** para credenciais, tokens, chaves
- Nunca coloque senha/token em ConfigMap

### Montagem

- Prefira `envFrom` para arrays grandes de variáveis — reduz verbosidade
- Use `valueFrom` para uma variável específica
- Monte Secrets como files (`volumeMounts`) quando forem certificados, chaves ou arquivos grandes

```yaml
envFrom:
  - configMapRef:
      name: orders-config
  - secretRef:
      name: orders-secrets

env:
  - name: DATABASE_URL
    valueFrom:
      secretKeyRef:
        name: orders-secrets
        key: database-url
```

### Rotação

- Mudanças em ConfigMap/Secret **não** disparam restart automático dos pods
- Use checksum do conteúdo em annotations do template para forçar rollout em mudança

## Namespaces

- Um namespace por aplicação/time quando possível — isolamento de quotas, RBAC e políticas
- Namespaces curtos e descritivos — `orders`, `orders-staging`, `orders-prod`
- Nunca deploye em `default` em produção

## HPA (Horizontal Pod Autoscaler)

- Baseie em CPU/memória apenas quando são preditores reais de carga — para apps HTTP, latência ou RPS (via custom metrics) são melhores sinais
- `minReplicas >= 2` para serviços críticos
- `maxReplicas` com teto realista — proteção contra runaway
- `behavior.scaleDown` conservador para evitar flapping

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 3
  maxReplicas: 20
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

## PodDisruptionBudget

- Defina PDB para qualquer Deployment com `replicas >= 2` em produção
- Prefira `minAvailable` em vez de `maxUnavailable` — mais previsível durante drains

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app.kubernetes.io/name: orders
```

## Security context

- `runAsNonRoot: true` + `runAsUser: <uid>` — nunca rode como root
- `readOnlyRootFilesystem: true` quando o app não precisa escrever em `/`
- `allowPrivilegeEscalation: false`
- Drop de capabilities: `capabilities.drop: ["ALL"]`

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1001
  runAsGroup: 1001
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
```

## Ingress

- Um Ingress por aplicação ou por conjunto de rotas relacionadas
- Use host + path — evite path-only quando possível (cookies e CORS ficam frágeis)
- TLS sempre — referencie Secret com certificado

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx
  tls:
    - hosts: [api.example.com]
      secretName: api-tls
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: orders
                port:
                  name: http
```

## Anti-patterns

- `image: myapp:latest` — builds imprevisíveis e rollbacks impossíveis de auditar
- `replicas: 1` para serviços críticos sem PDB
- Probes que dependem de serviços externos — falha em cascata durante incidentes
- `securityContext` ausente — pods rodam como root por default em muitos casos
- `hostPath` volumes para storage de app — amarra pod a nó específico
- Sem `resources.requests` — scheduler pode colocar pod em nó sobrecarregado
- Senhas em ConfigMap
- Usar `default` namespace em produção
- `NodePort` exposto diretamente à internet
- `selector.matchLabels` incluindo `version` — quebra rollouts
