# Validação de qualidade

> **Quando ler:** antes de considerar um Dockerfile "pronto". Quando o `docker compose up` sobe sem erro mas você não confia que está tudo certo. Ao montar um gate de qualidade Docker em CI. Quando precisa provar que a imagem está sã, e não só que ela existe.

## Índice

1. [O que esta validação verifica (e o que não verifica)](#o-que-esta-validação-verifica-e-o-que-não-verifica)
2. [O princípio não-invasivo](#o-princípio-não-invasivo)
3. [Isolamento e teardown](#isolamento-e-teardown)
4. [Nível 1 — Lint do Dockerfile](#nível-1--lint-do-dockerfile)
5. [Nível 2 — Build](#nível-2--build)
6. [Nível 3 — Inspeção da imagem](#nível-3--inspeção-da-imagem)
7. [Nível 4 — Subida](#nível-4--subida)
8. [Nível 5 — Sustentação](#nível-5--sustentação)
9. [Nível 6 — Resposta](#nível-6--resposta)
10. [Adaptando ao projeto](#adaptando-ao-projeto)
11. [Erros comuns de iniciante](#erros-comuns-de-iniciante)

---

## O que esta validação verifica (e o que não verifica)

A pergunta que este gate responde é **"o artefato Docker está correto?"** — não "o código está correto?".

Concretamente, ele verifica quatro coisas:

1. O Dockerfile segue as convenções (nível 1)
2. O build reproduz (nível 2)
3. A imagem resultante está sã — non-root, sem secret, forma exec (nível 3)
4. A aplicação sobe e **se sustenta** (níveis 4–6)

O que ele **não** faz: rodar a suíte de testes do projeto. Isso é etapa anterior, de outra responsabilidade — o teste unitário de uma função não é assunto de uma skill de Docker, e um Dockerfile impecável não conserta uma regra de negócio errada.

Essa fronteira não é arbitrária, é técnica. As boas práticas desta skill mandam construir uma imagem final mínima: sem devDependencies, sem compilador, às vezes sem shell (distroless). Uma imagem assim **não tem como rodar a suíte de testes** — não há runner instalado. Tentar validar código dentro dela é lutar contra o próprio artefato que você acabou de construir bem.

> Se a sua validação precisa que a imagem de runtime tenha o test runner, a validação está errada — ou a imagem está.

## O princípio não-invasivo

**A validação não modifica o projeto.** Não adiciona serviço ao `compose.yaml`, não escreve arquivo de override, não altera o Dockerfile.

Isso não é preciosismo. Um gate que precisa mutar o projeto para funcionar:

- deixa lixo quando falha no meio (o serviço `tests:` fica lá, e alguém commita)
- valida uma configuração que **não é** a que vai para produção — você testou o compose modificado, não o real
- não pode rodar em cima de código de outra pessoa sem sujar o diff dela

Toda escolha de mecanismo nas seções abaixo decorre desse princípio: o gate observa o container **de fora**, com os comandos que o Docker já oferece.

## Isolamento e teardown

Todo o gate roda sob um **project name dedicado**:

```bash
PROJ="$(basename "$PWD")-qa"
```

É isso que torna o `down -v` seguro. Sem o `-p`, o Compose usa o nome do diretório — o mesmo projeto que o desenvolvedor usa no dia a dia — e o `-v` apagaria o volume do banco de desenvolvimento, com os dados dele dentro.

Com o project name dedicado, o `-v` destrói apenas os volumes que a própria validação criou.

O teardown roda **sempre**, inclusive quando o gate falha no meio:

```bash
trap 'docker compose -p "$PROJ" down -v --remove-orphans >/dev/null 2>&1' EXIT
```

Sem o `trap`, um `set -e` que aborta no nível 5 deixa containers de pé segurando portas — e a próxima execução falha por colisão, num erro que não tem nada a ver com o Dockerfile.

## Nível 1 — Lint do Dockerfile

O hadolint roda via container: zero instalação, mesma versão em qualquer máquina, coerente com uma skill de Docker.

```bash
docker run --rm -i \
  -v "$PWD/.hadolint.yaml:/cfg.yaml:ro" \
  hadolint/hadolint:v2.14.0 \
  hadolint --config /cfg.yaml - < Dockerfile
```

Dois detalhes que custam tempo se descobertos na marra:

- **Passe a config com `--config` explícito.** A imagem não lê `~/.config/hadolint.yaml` — montar ali não tem efeito nenhum e o lint roda com as regras default sem avisar. Montar em `/.hadolint.yaml` funciona (o `WORKDIR` da imagem é `/`), mas depende desse detalhe interno; o `--config` é explícito e não quebra quando a imagem muda.
- **Pine a tag do hadolint.** Usar `hadolint/hadolint:latest` num gate que reprova `FROM ...:latest` é incoerente — e pior, faz o resultado do lint mudar sozinho quando a imagem é atualizada.

### O `.hadolint.yaml` desta skill

O hadolint default **reprova código que estas convenções mandam escrever**. A regra `DL3008` exige pin de versão em cada pacote apt (`apt-get install curl=7.88.1-10`), e a `DL3018` faz o mesmo para apk. Esta skill pede pin da **base image**, não de cada pacote do sistema — pinar pacote a pacote quebra o build a cada atualização de segurança do repositório da distro.

Sem essa config, o gate vira ruído e as pessoas param de olhar para ele.

```yaml
# .hadolint.yaml
ignored:
  - DL3008   # pin de versão por pacote apt — a skill pina a base image
  - DL3018   # idem para apk

failure-threshold: warning

trustedRegistries:
  - docker.io
  - ghcr.io
```

`failure-threshold: warning` faz o comando sair com código ≠ 0 em warnings e errors, deixando passar os `info`. Com essa config, um Dockerfile escrito segundo esta skill sai com **exit 0**, e um que usa `latest` + `CMD` em forma shell é reprovado — que é exatamente a calibragem desejada.

## Nível 2 — Build

```bash
docker build -t "$PROJ:validacao" .
```

O build **é** o teste deste nível. Não há sutileza: se não constrói, nada mais importa e o gate para aqui.

Vale rodar sem `--no-cache` no dia a dia (rápido) e com `--no-cache` antes de publicar (prova que o build é reproduzível do zero, e não que existe uma camada em cache escondendo um `apt-get` que já não funciona mais).

## Nível 3 — Inspeção da imagem

Aqui o gate verifica se a imagem construída de fato tem as propriedades que as Partes 1 e 2 da skill prescrevem. Note que é tudo `inspect` e `history` — nenhum comando executado *dentro* do container, o que faz este nível funcionar igual em distroless.

| Critério | Comando | Reprova quando |
|---|---|---|
| non-root | `docker inspect --format '{{.Config.User}}' "$IMG"` | vazio, `root` ou `0` |
| forma exec | `docker inspect --format '{{json .Config.Entrypoint}} {{json .Config.Cmd}}' "$IMG"` | contém `/bin/sh -c` |
| secret em camada | `docker history --no-trunc "$IMG"` | casa com `password\|secret\|token\|api[_-]?key` |
| base pinada | `grep -E '^FROM .*(:latest\|^FROM [^:]+$)' Dockerfile` | há `:latest` ou tag ausente |
| tamanho | `docker image inspect --format '{{.Size}}' "$IMG"` | — **só avisa** |
| healthcheck | `docker inspect --format '{{.Config.Healthcheck}}' "$IMG"` | — **só avisa** |

Os dois últimos avisam em vez de reprovar porque não têm resposta objetiva. "Imagem grande" depende da linguagem — 69 MB é ótimo para Node e péssimo para Go. `HEALTHCHECK` é fortemente recomendado, mas há casos legítimos sem ele (job batch, sidecar). Reprovar em critério subjetivo treina as pessoas a ignorar o gate.

O `{{.Config.User}}` merece atenção: **vazio significa root.** É o caso mais comum de falha, porque não há nada de errado aparente no Dockerfile — só falta uma linha `USER`.

## Nível 4 — Subida

```bash
docker compose -p "$PROJ" up -d --wait --wait-timeout 120
```

A flag `--wait` já implementa "esperar todos os serviços ficarem healthy" nativamente. Não reimplemente isso com laço de `sleep` + `docker ps` — o Compose faz melhor e respeita as `condition:` declaradas.

Mas leia a próxima seção antes de confiar no resultado dela.

## Nível 5 — Sustentação

**Este é o coração do gate.** `up -d` sozinho é um teste fraco, e não por pouco:

> Um container em restart loop foi validado com `up -d --wait`, que imprimiu `Container api-1 Healthy` e retornou **exit 0**. O container estava com `RestartCount=7` e `status=restarting`.

Quando um serviço não declara `HEALTHCHECK`, o `--wait` considera "started" como suficiente. O container sobe, crasha, o `restart:` o reergue, e o Compose reporta sucesso. Sem o nível 5, o gate aprova uma imagem que não roda.

```bash
for c in $(docker compose -p "$PROJ" ps -aq); do
  docker inspect --format '{{.Name}} restarts={{.RestartCount}} status={{.State.Status}}' "$c"
done
```

Critério: **`RestartCount > 0` ou `status != running` reprova.**

Um detalhe que economiza uma depuração: `docker compose ps --format json` **não expõe `RestartCount`** — o campo simplesmente não está no JSON (só há `State`, `Health`, `ExitCode`). O contador só sai pelo `docker inspect` no container. Tentar lê-lo pelo `compose ps` devolve vazio, o que se parece com "zero reinícios" e faz o gate aprovar em silêncio.

Espere ~30s antes de medir. Restart loop precisa de tempo para se manifestar; medir imediatamente após o `up` pega o container no primeiro start, quando ainda parece saudável.

### Logs são sinal auxiliar, não critério

```bash
docker compose -p "$PROJ" logs --tail 200 | grep -Eic 'panic|fatal|traceback|MODULE_NOT_FOUND'
```

Útil para **explicar** a falha, ruim para **detectar** a falha:

- a janela do `--tail` engole o erro — numa verificação real, `--tail 3` devolveu zero matches num container claramente quebrado, porque a mensagem de erro estava acima da janela; com `--tail 50` apareceu
- a lista de palavras nunca cobre todas as linguagens e idiomas
- app saudável pode logar a palavra "error" legitimamente (falso positivo)

Use os logs para dizer ao usuário **por que** falhou, depois que o `RestartCount` já disse **que** falhou.

## Nível 6 — Resposta

```bash
PORTA=$(docker compose -p "$PROJ" port api 3000)
curl -fsS -o /dev/null -w '%{http_code}\n' "http://${PORTA/0.0.0.0/localhost}"
```

Duas decisões embutidas:

- **O curl sai do host, nunca de dentro do container** (`docker compose exec ... curl`). A skill manda construir imagens mínimas — distroless não tem shell, e a maioria das imagens slim não traz `curl`. Um gate que exige `curl` dentro do container está pedindo que você degrade a imagem para poder validá-la. A validação não pode exigir do container aquilo que a skill proíbe de colocar nele.
- **Traduza `0.0.0.0` para `localhost`.** O `compose port` devolve `0.0.0.0:60889`; `curl` em `0.0.0.0` funciona por acidente em Linux e falha em outros contextos. A substituição é o que torna o comando portável.

Use `port` para descobrir o mapeamento em vez de assumir a porta do `compose.yaml` — em porta efêmera (`- "3000"` sem lado esquerdo) o host recebe uma porta aleatória, e é justamente essa forma que evita colisão quando o gate roda ao lado do ambiente de dev.

## Adaptando ao projeto

Nem todo nível se aplica a todo projeto. Aplicar a lista inteira cegamente reprova projetos corretos.

| Natureza do projeto | Níveis | Observação |
|---|---|---|
| Serviço HTTP | 1–6 | caso completo |
| Worker / consumer / cron | 1–5 | não expõe porta; nível 6 não se aplica |
| CLI / job batch | 1–3 + exit code | **critério invertido** |
| Sem `compose.yaml` | 1–3 | não há o que subir |

O caso do CLI inverte o critério de sucesso: um job batch **deve** terminar. Ali, `status=exited` com `ExitCode=0` é aprovação, e um container que continua rodando é que seria suspeito. Sem essa exceção, o gate reprova todo job que funciona.

```bash
docker run --rm "$PROJ:validacao"; echo "exit=$?"
```

## Erros comuns de iniciante

### "O `down -v` apagou o banco de desenvolvimento"

Rodou sem `-p` isolado. O Compose adotou o nome do diretório — o mesmo projeto do dia a dia — e o `-v` levou junto o volume com os dados. Sempre `-p "$(basename "$PWD")-qa"`. Confira com `docker volume ls` antes e depois: a lista tem que ficar idêntica.

### "O gate falhou mas o Dockerfile está certo"

Colisão de portas. Um serviço já ocupava a porta publicada, o `up` falhou, e a mensagem não deixa claro que a causa é ambiental. Prefira porta efêmera (`- "3000"`) no cenário de validação e descubra o mapeamento com `compose port`.

### "Passou no `up -d` mas a aplicação não funciona"

Faltou o nível 5. Com `--wait` e sem `HEALTHCHECK` declarado, "started" conta como sucesso e o restart loop passa despercebido — comprovadamente, com `exit 0` e a palavra `Healthy` na tela. Cheque `RestartCount`.

### "O healthcheck nunca fica healthy"

`start_period` curto demais para o tempo de boot da app. Durante o `start_period` as falhas não contam como retry; se ele acaba antes da app subir, as tentativas seguintes queimam os `retries` e o serviço é marcado unhealthy. Veja `praticas-docker-compose.md`.

### "O hadolint reclama de tudo"

Rodou sem o `.hadolint.yaml` desta skill, ou montou a config num caminho que a imagem não lê (`~/.config/hadolint.yaml` não funciona no container). Use `--config` explícito e confirme: se um Dockerfile que segue esta skill não sai com exit 0, a config não está sendo carregada.

### "Funciona no meu gate, falha no CI"

Build com cache local escondendo um passo quebrado. Rode `docker build --no-cache` antes de publicar.
