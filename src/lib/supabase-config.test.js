import test from 'node:test';
import assert from 'node:assert/strict';
import { timeoutFetch, UPSTREAM_TIMEOUT_MS } from './supabase-config.js';

test('gives up on a hanging upstream instead of waiting forever', async () => {
  const server = (await import('node:http')).createServer(() => { /* never responds */ });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  const url = `http://127.0.0.1:${server.address().port}/`;
  try {
    await assert.rejects(timeoutFetch(150)(url), (err) => err.name === 'TimeoutError');
  } finally {
    server.close();
  }
});

test('a caller-supplied signal wins over the default timeout', async () => {
  const controller = new AbortController();
  controller.abort();
  await assert.rejects(
    timeoutFetch(150)('http://127.0.0.1:1/', { signal: controller.signal }),
    (err) => err.name === 'AbortError'
  );
});

test('the default bound is short enough to survive an edge middleware limit', () => {
  assert.ok(UPSTREAM_TIMEOUT_MS > 0 && UPSTREAM_TIMEOUT_MS <= 10_000);
});
