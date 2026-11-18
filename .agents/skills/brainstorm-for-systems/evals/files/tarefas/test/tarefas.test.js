import { test, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import { criarTarefa, listarTarefas, limparTarefas } from '../src/tarefas.js';

beforeEach(() => limparTarefas());

test('cria tarefa com título aparado', () => {
  const tarefa = criarTarefa('  comprar pão  ');
  assert.equal(tarefa.titulo, 'comprar pão');
  assert.equal(tarefa.id, 1);
});

test('recusa título vazio', () => {
  assert.throws(() => criarTarefa('   '), /título obrigatório/);
});

test('lista as tarefas criadas', () => {
  criarTarefa('a');
  criarTarefa('b');
  assert.deepEqual(listarTarefas().map((t) => t.titulo), ['a', 'b']);
});
