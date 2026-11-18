---
adr_number: "014"
status: aceito
created: 2026-11-18
supersedes: ""
superseded_by: ""
---

# ADR 014: Credenciais da pipeline em secrets do repositório — kubeconfig de 7 dias e `DATABASE_URL` aplicada pelo CD

## Contexto

A CI precisa publicar no Docker Hub; o CD precisa acessar o cluster DOKS e garantir o Secret
`encontros-tech-secrets` com a `DATABASE_URL`. Até aqui o Secret era criado à mão no cluster,
copiando o output do Terraform ([ADR 008](008-terraform-estado-local-aplicacao-manual.md)).
O Terraform continua manual e fora da pipeline.

Restrições verificadas:

- O kubeconfig do DOKS (do Terraform ou do `doctl`) usa token que expira em **7 dias** por
  padrão; a validade pode ser alterada (`expiry_seconds` / `--expiry-seconds`), mas a
  documentação não informa máximo **[Verificado — docs.digitalocean.com (Kubernetes API, doctl)
  e docs do provider `digitalocean_kubernetes_cluster`, via Context7, 2026-11-18]**.
- Secrets não são passados a workflows disparados por PR de fork; PRs de branches do próprio
  repositório recebem os secrets do repositório **[Verificado — docs.github.com, Using secrets,
  via Context7, 2026-11-18]**.
- Um workflow disparado por `workflow_run` acessa secrets mesmo que o anterior não acessasse
  **[Verificado — docs.github.com, workflow_run, via Context7, 2026-11-18]**.

## Alternativas Consideradas

- **Token da DigitalOcean com escopo `kubernetes:access_cluster`, gerando o kubeconfig a cada
  execução** — não expira semanalmente; em troca, o alcance no cluster segue o papel do dono do
  token e entra o `doctl` na pipeline.
- **Kubeconfig de ServiceAccount com RBAC só no namespace** — sem expiração e menor privilégio;
  em troca, ServiceAccount e RBAC criados à mão no cluster, fora dos manifestos da aplicação.
- **GitHub Environment restrito à `main`** — esconde os secrets de PRs internas; em troca, mais
  um recurso de configuração que o projeto não quer adotar.
- **Secret do banco continuando manual no cluster** — o GitHub não guarda a credencial do banco;
  em troca, a pipeline não garante o Secret.
- **Kubeconfig de 7 dias e `DATABASE_URL` como secrets do repositório; o CD cria o Secret** —
  o mais simples; em troca, renovação semanal manual e secrets visíveis a PRs internas.

## Decisão

Guardar as credenciais como **secrets do repositório** (sem Environment) e os valores não
sensíveis como **variables do repositório**:

| Tipo | Nome | Uso |
|---|---|---|
| Secret | `DOCKERHUB_TOKEN` | CI — token de acesso do Docker Hub, leitura e escrita |
| Secret | `KUBECONFIG` | CD — kubeconfig do cluster, validade padrão de 7 dias |
| Secret | `DATABASE_URL` | CD — cria ou atualiza o Secret `encontros-tech-secrets` antes do Deployment |
| Variable | `DOCKERHUB_USERNAME` | CI |
| Variable | `IMAGE_NAME` | CI e CD |

O kubeconfig **mantém a validade padrão de 7 dias** e é renovado à mão pelo operador
(`doctl kubernetes cluster kubeconfig show <cluster>`) *(premissa — confirme ou corrija)*.
A `DATABASE_URL` sai de `terraform output -raw database_url` e é copiada à mão para o secret do
GitHub; o CD passa a ser quem cria o Secret no cluster. Isso substitui o passo manual "colocar a
`DATABASE_URL` no Secret do Kubernetes" descrito no ADR 008; o restante do ADR 008 continua
valendo. Decisão do responsável pelo projeto.

## Consequências

- **Positivas:** nenhuma credencial no repositório nem na imagem; o Secret do banco passa a ser
  garantido a cada deploy; sem ferramenta extra (`doctl`) na pipeline.
- **Negativas:** o CD **falha quando o kubeconfig expira**, até alguém renovar o secret — toda
  semana. O kubeconfig dá acesso de admin ao cluster inteiro, não só ao namespace. Uma PR de
  branch do próprio repositório que altere um workflow consegue ler `KUBECONFIG` e `DATABASE_URL`
  — risco aceito com operador único. A credencial do banco passa a existir também no GitHub.
- **Neutras / trade-offs aceitos:** se o banco for recriado, o secret `DATABASE_URL` precisa ser
  atualizado à mão. Mudar só a `DATABASE_URL` não reinicia os pods: o valor novo vale quando eles
  forem recriados (o CD não força restart) *(premissa — confirme ou corrija)*. A `SECRET_KEY`
  fixa no código continua fora do inventário ([ADR 004](004-porte-sem-alteracao-de-codigo.md)).
