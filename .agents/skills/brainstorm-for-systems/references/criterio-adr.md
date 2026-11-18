# Critério de ADR

Um ADR registra uma decisão que um leitor futuro precisa entender para não desfazê-la por engano.
ADR demais afoga os que importam; por isso a régua exige as três condições juntas.

## As três condições

1. **Restringe outras decisões ou é caro reverter** (régua da lente de especificação). Se mudar
   depois obriga a refazer outras partes, é arquitetura.
2. **Surpreende sem contexto.** Um leitor olhando o código se perguntaria "por que fizeram assim?".
3. **Resultou de um trade-off real**, com alternativa descartada registrada na conversa. Sem
   alternativa, não há decisão — há um fato de stack.

Faltou uma, não é ADR.

## O que costuma qualificar

- Forma arquitetural: "ingestão e processamento se comunicam por fila, não por chamada síncrona".
- Tecnologia com lock-in: banco, barramento de mensagens, provedor de identidade, alvo de deploy —
  as que levariam semanas para trocar, não qualquer biblioteca.
- Fronteira e escopo: "dados de cliente pertencem ao módulo X; os outros referenciam só por ID".
- Desvio deliberado do caminho óbvio: "SQL manual em vez de ORM, porque Y".
- Restrição invisível no código: "não pode usar serviço gerenciado pago", "resposta abaixo de 200 ms
  por contrato com parceiro".
- Alternativa rejeitada por motivo não óbvio — para ninguém propô-la de novo daqui a seis meses.

## Para onde vai o que não qualifica

| Caso | Destino |
|---|---|
| Fato de stack sem alternativa discutida | seção Stack do TRD, no portão |
| Decisão local a uma feature | especificação da feature, mais tarde |
| Preferência reversível sem custo | lugar nenhum — decide-se construindo |
| Decisão ainda Inferida | espera a confirmação do usuário |
| Decisão Em aberto | ADR `proposto` gravado no portão, com a pendência que o destrava |
