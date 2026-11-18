# Configuração e secrets

> **Quando ler:** ao injetar primeira variável de ambiente em um pod, quando você tem certificado/chave para montar, quando descobre que mudar ConfigMap não atualizou a app, quando alguém menciona "rotação" e você não sabe o que fazer.

## Índice

1. [ConfigMap vs Secret: a diferença que importa](#configmap-vs-secret-a-diferença-que-importa)
2. [Três jeitos de injetar config no pod](#três-jeitos-de-injetar-config-no-pod)
3. [Por que mudar ConfigMap não reinicia o pod](#por-que-mudar-configmap-não-reinicia-o-pod)
4. [Secret não é criptografia](#secret-não-é-criptografia)
5. [Estratégias para rotação](#estratégias-para-rotação)
6. [Onde guardar manifests de Secret (ou não guardar)](#onde-guardar-manifests-de-secret-ou-não-guardar)
7. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## ConfigMap vs Secret: a diferença que importa

Funcionalmente, ConfigMap e Secret são quase iguais — armazenam pares chave-valor que viram envs ou arquivos no pod. A diferença principal é **convenção e tratamento**:

| Aspecto | ConfigMap | Secret |
|---|---|---|
| Conteúdo típico | URLs, feature flags, níveis de log, parâmetros não sensíveis | Senhas, tokens, chaves privadas, certificados |
| Encoding no manifest | Texto direto | Base64 (não é criptografia, só encoding) |
| `kubectl describe` mostra valor? | Sim | Não (mostra `<redacted>`) |
| Logs do K8s mostram valor? | Sim | Censurado em vários pontos |
| RBAC típico | Mais permissivo | Mais restritivo |
| Encryption at rest no etcd | Não por padrão | Não por padrão (precisa configurar) |

### A regra prática

> Se você **não quer** que apareça em `kubectl describe`, em `kubectl get -o yaml` para qualquer dev, em logs de auditoria — é Secret.
>
> Se é seguro mostrar — é ConfigMap.

### O que **nunca** deve ir em ConfigMap

- Senha de banco
- Token de API (GitHub, AWS, Stripe…)
- Chave privada (`.pem`, `.key`)
- Connection string com credenciais embutidas
- JWT secret

Iniciante coloca essas coisas em ConfigMap "porque é mais simples" e descobre depois que `kubectl describe` em CI compartilhado vazou.

## Três jeitos de injetar config no pod

### Modo 1 — Variáveis de ambiente individuais (`valueFrom`)

```yaml
spec:
  containers:
    - name: api
      env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: orders-secrets
              key: database-url
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: orders-config
              key: log-level
```

- Útil quando você quer **renomear** a variável para o que a app espera
- Útil quando você quer pegar **algumas chaves** específicas, não todas
- Verboso para muitas variáveis

### Modo 2 — Tudo de uma vez (`envFrom`)

```yaml
spec:
  containers:
    - name: api
      envFrom:
        - configMapRef:
            name: orders-config
        - secretRef:
            name: orders-secrets
```

- Cada chave do ConfigMap/Secret vira uma variável com **o mesmo nome**
- Limpo, conciso
- Risco: se o ConfigMap tem chave com nome inesperado, vira env inesperada

Use `envFrom` quando você controla o ConfigMap e a app — nomes são consistentes.

### Modo 3 — Volumes (arquivos no filesystem)

```yaml
spec:
  containers:
    - name: api
      volumeMounts:
        - name: tls
          mountPath: /etc/tls
          readOnly: true
  volumes:
    - name: tls
      secret:
        secretName: orders-tls
```

Cada chave do Secret vira um arquivo em `/etc/tls/<chave>`. Use para:

- Certificados TLS (`tls.crt`, `tls.key`)
- Chaves SSH
- Arquivos de config grandes/complexos (yaml, json) que ficariam estranhos como env
- Segredos que a app já espera ler de arquivo (Postgres, Vault agent)

### Quando usar cada um

| Cenário | Modo |
|---|---|
| Variável de ambiente única, renomeada | `valueFrom` |
| Bloco grande de variáveis controladas por você | `envFrom` |
| Certificados, chaves, arquivos | Volume |
| Mistura: variáveis comuns + um certificado | `envFrom` + volume |

## Por que mudar ConfigMap não reinicia o pod

Cenário comum: você muda `log-level` no ConfigMap, faz `kubectl apply`, e... nada acontece. App continua com nível antigo.

**K8s não dispara restart automático ao alterar ConfigMap/Secret.** Os pods existentes continuam com a versão que tinham quando subiram.

### Por que esse comportamento

K8s preza por declaratividade — você descreve o estado desejado, controllers reconciliam. Mas Pods não têm referência "live" para o ConfigMap; o conteúdo foi resolvido no momento da criação.

Para envs (`envFrom`, `valueFrom`), o conteúdo é injetado **uma vez** no início. Não há "watch" que atualize a env de um processo em execução.

Para volumes, há atualização (kubelet sincroniza periodicamente, ~1 min de delay), mas a app precisa **re-ler o arquivo** — a maioria não re-lê.

### Como forçar atualização

#### Opção 1 — Manual

```bash
kubectl rollout restart deployment/orders
```

Cria pods novos (rolling update), que pegam o ConfigMap atualizado.

#### Opção 2 — Checksum em annotation (Helm pattern)

```yaml
spec:
  template:
    metadata:
      annotations:
        checksum/config: {{ include "orders.config" . | sha256sum }}
```

Quando o conteúdo do ConfigMap muda, o hash muda, o template muda, K8s detecta mudança no Deployment, dispara rolling update automaticamente.

Sem Helm, você pode fazer isso manualmente:

```bash
kubectl annotate deployment orders \
  config-hash=$(kubectl get cm orders-config -o yaml | sha256sum)
```

#### Opção 3 — Operadores específicos

Reloader, ConfigMap Reloader (de terceiros) — observam ConfigMaps/Secrets e fazem rollout do que os usa. Útil em escala.

### Volumes têm um caminho intermediário

Se você montou ConfigMap como volume e a app **lê do disco a cada request** (raro, mas alguns proxies fazem), a mudança chega sem restart — depois de ~1min do kubelet sincronizar.

Se a app lê o arquivo **uma vez no boot** (caso comum), você ainda precisa reiniciar.

## Secret não é criptografia

O ponto que confunde iniciante:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: orders-secrets
type: Opaque
data:
  database-password: cGFzczEyMw==   # Base64 de "pass123"
```

O valor está **encodado** em Base64, não criptografado. Qualquer um com acesso ao manifest decodifica em 2 segundos:

```bash
echo "cGFzczEyMw==" | base64 -d
# pass123
```

Base64 existe para evitar caracteres binários no YAML, não para esconder.

### Onde Secret é genuinamente protegido

- **`kubectl describe`** — mostra `<redacted>`
- **Logs do API server** — censurados em maioria dos campos
- **Acesso via RBAC** — pode-se restringir `get secrets` separadamente de `get configmaps`

### Onde NÃO é protegido por padrão

- **etcd** — armazena Secret em texto-plain (Base64 decodificado é trivial). Quem acessa o backup do etcd, lê os secrets.
- **`kubectl get secret -o yaml`** — qualquer um com permissão vê o Base64.
- **Manifests no Git** — se você commitou o YAML, está lá pra sempre, mesmo apagando depois.

### Como obter proteção real

#### Encryption at rest no etcd

Configurável no API server (`encryption-provider-config`) com chave AES. Quem faz backup do etcd vê dado criptografado. Configuração de cluster operator — devs não fazem isso.

#### External secret management

Padrão moderno: K8s **não** armazena o secret. Apenas referencia.

- **Vault + agent injector**: pod tem sidecar Vault Agent que busca secret on-demand e expõe via volume tmpfs
- **AWS Secrets Manager + External Secrets Operator**: Secret no K8s é "espelho" de um secret real no AWS Secrets Manager
- **Sealed Secrets** (Bitnami): permite commitar Secret criptografado no Git, controller decripta no cluster

Para iniciante: comece com Secret nativo, RBAC apertado, encryption at rest. Quando crescer, migre para uma dessas soluções.

## Estratégias para rotação

Rotacionar = mudar o valor do secret periodicamente (boa prática contra credencial vazada).

### Cenário simples: senha de banco

1. Gere senha nova no banco (mantenha a antiga ainda válida temporariamente).
2. Atualize o Secret no K8s (`kubectl create secret ... --dry-run=client -o yaml | kubectl apply -f -`).
3. Force restart dos pods (`kubectl rollout restart`).
4. Pods novos usam senha nova.
5. Quando todos os pods estão rodando senha nova, revogue senha antiga no banco.

A janela de "duas senhas válidas" simultâneas é **essencial** para não derrubar tráfego.

### Cenário avançado: rotação automática

Vault, AWS Secrets Manager geram credenciais dinâmicas com TTL curto (15min). Pod busca credencial fresca conforme precisa. Sem necessidade de rolling restart manual.

### Periodicidade

| Tipo | Rotação típica |
|---|---|
| Senha de banco | 90 dias |
| Token de API externa | 90 dias |
| Certificado TLS | Antes de expirar (90 dias para Let's Encrypt) |
| JWT signing key | 30-90 dias |
| Credenciais dinâmicas (Vault) | 15min - horas |

Compliance pode exigir números específicos.

## Onde guardar manifests de Secret (ou não guardar)

### A pergunta clássica: "comito o YAML do Secret?"

**Não, se for plain Base64.** Você está commitando o secret em texto efetivamente claro. Histórico do Git é eterno — mesmo deletar não apaga.

### Soluções para versionar secrets em Git

#### Sealed Secrets (Bitnami)

Você gera um YAML criptografado:

```bash
echo -n "pass123" | kubectl create secret generic mysql --dry-run=client \
  --from-file=password=/dev/stdin -o yaml | \
  kubeseal -o yaml > sealed-secret.yaml
```

`sealed-secret.yaml` contém apenas valores criptografados com a chave pública do controller. Pode commitar. Só o controller no cluster (com chave privada) consegue decifrar.

#### SOPS (Mozilla)

Criptografa apenas os campos `data` do YAML usando KMS (AWS, GCP, Vault). Pode versionar normalmente; CI/CD descriptografa no momento do apply.

#### External Secrets Operator (mais moderno)

Você commita um `ExternalSecret` que **referencia** um secret externo:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: orders-secrets
spec:
  secretStoreRef:
    name: vault-backend
  target:
    name: orders-secrets
  data:
    - secretKey: database-url
      remoteRef:
        key: secret/data/orders
        property: database_url
```

O secret real fica no Vault. K8s mantém um Secret derivado, atualizado periodicamente. Você commita só o `ExternalSecret`, que não tem valor sensível.

### Solução simples para começar

Antes de tudo isso, o mínimo viável:

1. Crie secrets via `kubectl create secret` em uma máquina segura.
2. **Não** commite YAML com valores reais.
3. Commite YAML de **exemplo** (`secret.example.yaml`) com placeholders, documentando quais chaves o time precisa criar.
4. Use Vault/AWS Secrets Manager pra time real.

## Erros comuns de iniciante

### "Coloquei senha em ConfigMap por simplicidade"

`kubectl describe configmap` mostra valor para qualquer dev com permissão. Use Secret. Custo é zero.

### "Atualizei o ConfigMap mas a app continua com config antiga"

K8s não reinicia pods automaticamente. Faça `kubectl rollout restart deployment/<nome>` ou use checksum em annotation.

### "Secret tem `Opaque type` e eu não sei o que isso significa"

`type: Opaque` é o default — Secret genérico. Outros types (`kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`) ativam validação extra de campos esperados. Pra começar, sempre `Opaque`.

### "Encodei a senha em Base64 e achei que era criptografia"

Não é. `echo -n "senha" | base64 -d` decifra. Base64 é só encoding. Para proteção real, use Sealed Secrets, SOPS ou External Secrets.

### "Montei Secret como volume e a app não acha"

Conferir:
- `volumeMounts.mountPath` está correto?
- `volumes.secret.secretName` corresponde ao nome real do Secret?
- Permissões: por padrão, arquivos de Secret são `0644`. Apps que esperam permissão restrita (ex: SSH key 0600) precisam de `defaultMode: 0400`:

```yaml
volumes:
  - name: ssh
    secret:
      secretName: ssh-key
      defaultMode: 0400
```

### "Secret tem múltiplos pods e eu mudei só um pod"

Secret é referência; mudou o Secret, todos os pods que o usam veem (depois de restart). Você não muda "o Secret de um pod específico" — muda o Secret e todos os pods relacionados precisam restart.

### "Tenho senha em variável de ambiente e logs estão imprimindo"

App está logando `os.environ` ou similar. Bug da app, não do K8s. Censure logs antes de produção.

### "Commitei `secret.yaml` no Git, depois apaguei"

Histórico do Git é eterno. O secret está exposto. Solução real: revogue a credencial nesse secret, gere nova, e use sealed secrets / vault dali em diante.

### "ConfigMap com 100kb está estranho"

Há limite de ~1MB para ConfigMap (limit do etcd). Se está perto disso, repense — provavelmente deveria ser arquivo em volume persistente, não config.

---

**Princípio que resume tudo:** ConfigMap e Secret resolvem **ondes** a configuração mora — separada da imagem, declarada no cluster. Mas K8s sozinho não resolve **rotação automática** nem **verdadeira proteção** de Secret. Para apps simples, o nativo basta. Para produção séria, External Secrets Operator + Vault/AWS Secrets Manager é o caminho moderno.
