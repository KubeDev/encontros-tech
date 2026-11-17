# Lente: especificação de projeto de desenvolvimento

Referência da área "especificação de projeto de desenvolvimento" da skill `brainstorm`. Carregada só depois que a área foi inferida e confirmada.

**O que esta lente produz:** requisitos de negócio e requisitos de arquitetura completos, com toda inferência visível e todo fato externo verificado.

**O que ela não produz:** a spec. O brainstorm é a **base para a criação** da especificação — preserva raciocínio, alternativas descartadas e pendências, exatamente o que um documento final apaga. Quem for escrever a spec depois consome isto; não recebe pronto.

O Protocolo de rigor do `SKILL.md` continua valendo item a item — nada aqui fica implícito por omissão.

---

## 1. Requisitos de negócio

O que levantar, antes de qualquer decisão técnica:

- **Problema real** — o que dói hoje, não a solução que o usuário já imaginou. Se a ideia chegou como solução, vale reformular (é o Reframing da Fase 2)
- **Quem usa** — perfis, e o que cada um precisa fazer
- **O que o sistema precisa permitir** — as capacidades, em linguagem de negócio
- **Regras de negócio** — o que é permitido, o que é proibido, o que é calculado, o que precisa ser auditável
- **O que está explicitamente fora de escopo** — tão importante quanto o que está dentro; escopo negativo não declarado é a origem mais barata de retrabalho

---

## 2. Requisitos técnicos — a régua de fronteira

Requisito técnico aqui é **arquitetura e implementação de alto nível**, nunca detalhe de código.

Dizer apenas "não descer ao código" não segura na prática — a conversa escorrega sozinha para o concreto. O critério operacional:

> **Entra o que restringe outras decisões ou é caro reverter. Sai o que apenas preenche uma decisão já tomada.**

| Entra (decisão que restringe) | Fica fora (preenchimento) |
|---|---|
| "Comunicação assíncrona entre ingestão e processamento, via fila" | desenhar endpoints, verbos, payloads |
| "Dados relacionais e transacionais, multi-tenant isolado por schema" | modelagem de tabelas, colunas, índices |
| "Autenticação delegada a um provedor de identidade externo; autorização por papel" | escolher a biblioteca, escrever o middleware |
| "O estado do job precisa sobreviver a restart" | escolher onde guardar, quando isso não restringe mais nada |
| "Precisa rodar sem serviço gerenciado pago" (restrição declarada) | estimar custo mensal, dimensionar instâncias |

Na dúvida, o teste é: **se mudar isso depois obriga a refazer outras partes, é arquitetura — registra. Se é só uma escolha local que alguém faz na hora de implementar, não registra.**

---

## 3. Checklist de não-funcionais

Sem checklist, "não deixar nada em aberto" degenera em "nada em aberto **do que eu lembrei**". Percorrer todos, e para cada um produzir um estado (Decidido, Inferido, Verificado ou Em aberto):

- **Volume e escala** — quantos usuários, quantos registros, qual o crescimento esperado
- **Tempo de resposta** — o que precisa ser imediato e o que pode ser assíncrono
- **Autenticação e autorização** — quem entra, e quem pode o quê
- **Dados sensíveis** — existe dado pessoal, financeiro ou regulado? isso restringe onde roda e quem acessa
- **Disponibilidade e tolerância a falha** — o que acontece se cair, o que não pode ser perdido, o que pode ser refeito
- **Integrações externas** — de quem o sistema depende, e o que acontece quando o terceiro falha
- **Onde roda** — ambiente, restrições de infraestrutura
- **Quem opera** — quem cuida disso depois de pronto; muda o quanto de automação e observabilidade é exigido
- **Restrições declaradas** — orçamento como limite ("sem serviço pago"), stack imposta, prazo como fato externo já dado pelo usuário

---

## 4. Rastreabilidade

**Todo requisito técnico aponta o requisito de negócio que ele serve.**

É uma checagem crítica barata: requisito técnico órfão — que não serve a nenhuma necessidade declarada — é over-engineering com nome bonito. Quando aparecer um, há dois desfechos honestos: ou o requisito de negócio existia e não foi levantado (levante), ou a decisão técnica não se justifica (corte).

---

## 5. Consulta externa — stack, versões e ferramentas

Nada sobre stack, versão de biblioteca ou ferramenta sai da memória do modelo. Data de corte de treino existe, e erro sobre versão é o tipo de erro que atravessa a spec inteira sem ser notado.

O gatilho é **volatilidade**, não assunto:

| Consultar sempre | Não consultar |
|---|---|
| Versão atual / estável / LTS de runtime, framework, banco | Conceito estável (o que é fila, o que é idempotência) |
| A biblioteca ainda é mantida? está deprecada? | Trade-off arquitetural clássico |
| O recurso existe naquela versão? | Regra de negócio do usuário |
| Compatibilidade entre as peças da stack escolhida | Qualquer coisa que o usuário já declarou |
| A ferramenta cobre mesmo o caso de uso citado | A estrutura da própria conversa |

**Ordem das fontes:** Context7 para documentação de biblioteca, framework, SDK ou CLI; busca web para o que Context7 não cobre — se o projeto ainda vive, anúncios de deprecação, comparativos, estado da comunidade.

Cada item assim registrado vira **Verificado**, com fonte e data da consulta. A data não é burocracia: é o que permite, numa retomada futura, saber o que envelheceu sem refazer tudo.

**Calibragem.** Pesquisar a fundo o que é caro reverter; para o resto, verificar o essencial e seguir. Levantar oito alternativas para uma decisão que não restringe nada queima a conversa sem melhorar a spec.

**Cuidado com a fonte.** Página de projeto vende o próprio produto e documentação de fornecedor descreve o caminho feliz. Registrar o que a fonte afirma — a escolha continua sendo do usuário, com a fonte como insumo.

---

## 6. Fora de escopo — sempre

Estes nunca são produzidos nesta lente, mesmo que a conversa puxe para lá:

- **Estimativa** de esforço, tamanho ou custo em números
- **Cronograma**, fases datadas, sequenciamento de entrega
- **Código**, pseudocódigo, trechos de implementação
- **Endpoints**, contratos de API campo a campo
- **Modelagem de tabela**, colunas, índices

Custo aparece **apenas como restrição declarada pelo usuário** ("precisa rodar barato", "sem serviço gerenciado pago") — nunca como número estimado.

Se o usuário pedir explicitamente algo desta lista, isso é saída do modo brainstorm: entregue a consolidação primeiro e trate o pedido como próxima tarefa, com a ferramenta adequada.

---

## 7. Esqueleto do documento (Fase 5)

Ordem fixa — sobrepõe o esqueleto emergente do `SKILL.md`:

```markdown
# Brainstorm — {tema}

**Lente:** especificação de projeto de desenvolvimento
**Última sessão:** {data}

## Problema

## Requisitos de negócio

## Requisitos técnicos
<!-- cada um apontando o requisito de negócio que serve -->

## Não-funcionais

## Estados
<!-- tabela: Item | Estado | Fonte/Premissa | Data -->

## Alternativas descartadas

## Pendências
<!-- cada uma com motivo e o que destrava -->
```

Cada item carrega o **raciocínio**, não só o veredito: por que essa escolha, o que foi descartado, o que a premissa assume. É essa camada que diferencia base-para-spec de spec — e é ela que torna a retomada possível.
