import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';
import worker from './worker.mjs';

test('account state is isolated and updates require the current revision', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(new URL('./schema.sql', import.meta.url), 'utf8'));
  const env = { DB: { prepare(sql) {
    const statement = database.prepare(sql);
    return { bind(...args) {
      const values = args.map(value => value instanceof ArrayBuffer ? new Uint8Array(value) : value);
      return { first: () => statement.get(...values), run: () => ({ meta: statement.run(...values) }) };
    } };
  } } };
  const send = (method, token, headers = {}, body) => worker.fetch(new Request('https://sync.test/v1/state', {
    method,
    body,
    headers: {
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(body ? { 'Content-Type': 'application/octet-stream' } : {}),
      ...headers,
    },
  }), env);
  const token = 'A'.repeat(43);
  const opaque = new Uint8Array(80).fill(95);
  assert.equal((await send('GET')).status, 401);
  assert.equal((await send('GET', token)).status, 404);
  const created = await send('PUT', token, { 'If-None-Match': '*' }, opaque);
  assert.equal(created.status, 201);
  const revision = created.headers.get('ETag');
  assert.equal((await send('PUT', token, { 'If-None-Match': '*' }, opaque)).status, 412);
  assert.equal((await send('GET', 'B'.repeat(43))).status, 404);
  const stored = await send('GET', token);
  assert.deepEqual(new Uint8Array(await stored.arrayBuffer()), opaque);
  assert.equal(stored.headers.get('ETag'), revision);
  const updated = await send('PUT', token, { 'If-Match': revision }, opaque);
  assert.equal(updated.status, 204);
  assert.equal((await send('DELETE', token, { 'If-Match': revision })).status, 412);
  assert.equal((await send('DELETE', token, { 'If-Match': updated.headers.get('ETag') })).status, 204);
  assert.equal((await send('GET', token)).status, 404);
  database.close();
});
