const tarefas = [];
let proximoId = 1;

export function criarTarefa(titulo) {
  if (!titulo || !titulo.trim()) {
    throw new Error('título obrigatório');
  }
  const tarefa = { id: proximoId++, titulo: titulo.trim(), criadaEm: new Date() };
  tarefas.push(tarefa);
  return tarefa;
}

export function listarTarefas() {
  return [...tarefas];
}

export function limparTarefas() {
  tarefas.length = 0;
  proximoId = 1;
}
