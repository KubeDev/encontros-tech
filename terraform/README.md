# Infraestrutura de homologação (Terraform)

Provisiona na DigitalOcean a infraestrutura descrita no TRD e nos ADRs 007, 008 e 009:

- VPC dedicada (range de IPs alocado pela DigitalOcean)
- Cluster DOKS sem HA no control plane, 2 nós `s-1vcpu-2gb`, sem autoscaling
- PostgreSQL 18 gerenciado (`db-amd-1vcpu-1gb`, 1 nó) dentro da VPC, com o banco `encontros_tech`
- Arquivo `kubeconfig` local, nesta pasta, para acessar o cluster

O Load Balancer **não** é criado aqui: ele nasce do Service `LoadBalancer` aplicado com `kubectl`.

## Pré-requisitos

- Terraform >= 1.17
- Token da API da DigitalOcean com escrita em VPC, Kubernetes e Databases, passado na variável
  `do_token`: em `terraform.tfvars` (copie de `terraform.tfvars.example`) ou por ambiente,
  `export TF_VAR_do_token=...`

## Uso

```bash
cd terraform
terraform init
terraform plan -out=hml.tfplan
terraform apply hml.tfplan
```

Valores padrão em `variables.tf`; para mudar, copie `terraform.tfvars.example` para `terraform.tfvars`.

### Acessar o cluster

```bash
KUBECONFIG=$(terraform output -raw kubeconfig_path) kubectl get nodes
```

O token dentro do kubeconfig expira. Para renovar o arquivo, rode `terraform apply` de novo.

### DATABASE_URL para o Secret

```bash
terraform output -raw database_url
```

Usa o host **privado** da VPC com `sslmode=require`. Para acesso administrativo de fora da VPC, use
`terraform output -raw database_public_url`. Se o banco for recriado, atualize o Secret (ADR 008).

### Destruir

```bash
terraform destroy
```

O cluster usa `destroy_all_associated_resources = true`, então o Load Balancer criado pelo Service
também é removido.

## Segredos

O estado (`terraform.tfstate`), os `*.tfvars` e o `kubeconfig` contêm credenciais em texto puro e
estão no `.gitignore`. O estado é local (ADR 008): o backup é responsabilidade do operador.

## Testes

```bash
terraform test
```

Os testes usam providers mockados: não precisam de token e não criam nada.
