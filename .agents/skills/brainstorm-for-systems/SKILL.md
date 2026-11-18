---
name: brainstorm-for-systems
description: Brainstorm de sistema que sai com a documentação técnica pronta — força a lente de especificação do `brainstorm`, mantém o glossário durante a conversa, acumula as decisões técnicas como ADRs candidatos e, no portão de consolidação, grava os ADRs confirmados e gera o TRD via `escrever-trd`.
disable-model-invocation: true
---

# brainstorm-for-systems

Composição de três peças: o `brainstorm` conduz a conversa, o `escrever-trd` escreve ADR e TRD, e
o glossário guarda o vocabulário do domínio. O motivo de compor em vez de só fazer brainstorm:
decisão técnica durável e termo de domínio se perdem na conversa se ninguém os acompanha. Mas
decisão gravada cedo demais é reescrita quando a conversa muda de rumo — um ADR sobre armazenamento
escrito antes de se saber onde a aplicação roda vira retrabalho. Por isso as decisões são
**acompanhadas** durante a conversa e **gravadas de uma vez no portão**, quando já estão firmes.

## Como compor

1. Invoque a skill `brainstorm` e siga-a por inteiro, com as sobreposições abaixo.
2. Invoque a skill `escrever-trd` no portão: Modo Decision para cada ADR confirmado, Modo
   Criação/Edição para o TRD.

As duas são dependências obrigatórias. Antes de começar, confira que `brainstorm` e `escrever-trd` estão disponíveis; se qualquer
uma faltar, diga qual e como instalá-la e pare — sem elas a composição não registra ADR nem TRD, e
um substituto improvisado geraria documentos fora do formato que o resto do fluxo lê.

## Sobreposições ao brainstorm

1. **Lente já confirmada.** O assunto é um sistema: carregue a lente "especificação de projeto de
   desenvolvimento" (`references/spec-desenvolvimento.md` no diretório da skill `brainstorm`) sem
   fazer a pergunta de confirmação de área.
2. **Uma exceção de escrita durante a conversa:** `docs/glossary.md`. ADR, TRD, PRD, código e
   qualquer outro arquivo esperam o portão ou o pedido explícito.
3. **Portão estendido.** A consolidação (Fase 4) também grava os ADRs confirmados e gera o TRD —
   ver `references/portao-fase4.md`.

## Abertura

O pedido de entrada costuma ser curto e ambíguo ("definir a estrutura inicial do projeto") e cabe
em leituras muito diferentes — um esqueleto com uma página, ou fundação com autenticação e ORM.
Responder à leitura errada com um turno pesado faz o usuário recomeçar a sessão.

1. **Intenção antes das leituras em lote.** Uma pergunta curta sobre o objetivo do ciclo (o que
   precisa existir quando ele terminar) antes de varrer TRD, ADRs e código. Leitura pontual para
   formular a pergunta é livre.
2. **Primeiro turno enxuto:** a pergunta de intenção e no máximo 3 perguntas. As inferências da
   Fase 1 do `brainstorm` vêm depois das respostas, quando já se sabe qual leitura vale.
3. **Ambiente e empacotamento cedo.** Quando a lente técnica se aplica, pergunte onde a aplicação
   roda em produção e como é empacotada (contêiner, compose de desenvolvimento e produção,
   migrations) no primeiro lote de perguntas técnicas: são as respostas que mais mudam decisões
   de armazenamento, deploy e estrutura, e descobri-las depois reabre o corte.

## Durante a conversa

### ADRs candidatos

Quando uma decisão técnica fica **Decidida** pelo usuário, com alternativa descartada registrada,
e passa na régua de `references/criterio-adr.md`, ela entra na lista de ADRs candidatos da
consolidação — sem arquivo ainda. Anuncie em uma linha: `ADR candidato: <título>`. Se a conversa
reverter a decisão, tire-a da lista; nada foi gravado, nada precisa ser desfeito.

Decisão que cita versão de biblioteca ou serviço (framework, ORM, provedor de autenticação) tem a
versão **Verificada** no registry (`npm view <pacote> version`, PyPI, página de releases) com a data
da consulta antes de entrar como candidata. Versão da memória do modelo erra com confiança, e o erro
só apareceria na implementação.

### Glossário

Quando um termo do domínio se resolve — o usuário escolhe um nome entre sinônimos, ou define um
conceito que é deste projeto — atualize `docs/glossary.md` naquele momento, sem acumular para
depois. Crie o arquivo só quando o primeiro termo aparecer.

Formato:

```markdown
**Termo**:
O que o termo é, em uma ou duas frases.
_Evitar_: sinônimo, outro-sinônimo
```

Entra só vocabulário do domínio; conceito genérico de programação fica de fora. Quando o usuário
usar um termo que conflita com o glossário, aponte na hora ("o glossário chama isso de X — é o
mesmo conceito?"). Termo é barato de mudar: edite direto, sem estado intermediário.

### Comandos no shell

O shell do usuário costuma ser zsh, onde uma palavra começando por `=` é expandida como comando
(`echo ====` falha com `==== not found` e derruba a linha inteira). Para separar saídas num comando
composto, use `echo '---'`, entre aspas.

## Portão (Fase 4)

Leia `references/portao-fase4.md` ao chegar na consolidação.

## Saída: documento e próxima fase

Ao fim do portão, ofereça salvar o documento do brainstorm (`docs/brainstorm-{slug}.md`, Fase 5 do
`brainstorm`) e sugira o `escrever-prd` numa **sessão nova**, com esse documento como origem. O
documento aponta para os ADRs e o TRD por link em vez de repetir o conteúdo deles — ele guarda o
raciocínio; os ADRs e o TRD guardam a decisão. Com ele, a especificação começa sem arrastar a
conversa inteira como contexto e preserva o porquê das regras.
