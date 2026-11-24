const maxBytes = 1_900_000;
const revisionPattern = /^"[0-9a-f-]{36}"$/;
const headers = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET, PUT, DELETE, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type, If-Match, If-None-Match',
  'Access-Control-Expose-Headers': 'ETag',
  'Cache-Control': 'no-store',
  'X-Content-Type-Options': 'nosniff',
};

function response(status, body = null, extra = {}) {
  return new Response(body, { status, headers: { ...headers, ...extra } });
}

async function boundedBody(request) {
  if (!request.body || Number(request.headers.get('Content-Length')) > maxBytes) return null;
  const reader = request.body.getReader();
  const buffer = new Uint8Array(maxBytes);
  let length = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) return length >= 28 ? buffer.buffer.slice(0, length) : null;
      if (length + value.byteLength > maxBytes) {
        await reader.cancel();
        return null;
      }
      buffer.set(value, length);
      length += value.byteLength;
    }
  } finally {
    reader.releaseLock();
  }
}

async function accountHash(token) {
  const data = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(token));
  return Array.from(new Uint8Array(data), byte => byte.toString(16).padStart(2, '0')).join('');
}

export default {
  async fetch(request, env) {
    const { pathname } = new URL(request.url);
    if (pathname === '/health' && request.method === 'GET') return response(204);
    if (pathname !== '/v1/state') return response(404);
    if (request.method === 'OPTIONS') return response(204);

    const token = /^Bearer ([A-Za-z0-9_-]{43})$/i.exec(request.headers.get('Authorization') ?? '')?.[1];
    if (!token) return response(401);
    const key = await accountHash(token);
    const create = request.headers.get('If-None-Match') === '*';
    const match = request.headers.get('If-Match') ?? '';

    try {
      const ip = request.headers.get('CF-Connecting-IP');
      if (ip && env.RATE_LIMITER) {
        const { success } = await env.RATE_LIMITER.limit({ key: ip, delta: create ? 12 : 1 });
        if (!success) return response(429, null, { 'Retry-After': '60' });
      }
      switch (request.method) {
        case 'GET': {
          const row = await env.DB.prepare(
            'SELECT revision, ciphertext FROM account_state WHERE account_hash = ?'
          ).bind(key).first();
          return row
            ? response(200, Uint8Array.from(row.ciphertext), {
                'Content-Type': 'application/octet-stream',
                ETag: row.revision,
              })
            : response(404);
        }
        case 'PUT': {
          if (!create && !revisionPattern.test(match)) return response(428);
          if (request.headers.get('Content-Type') !== 'application/octet-stream') return response(415);
          const body = await boundedBody(request);
          if (!body) return response(413);
          const revision = `"${crypto.randomUUID()}"`;
          const result = create
            ? await env.DB.prepare(`INSERT INTO account_state (account_hash, revision, ciphertext)
                VALUES (?, ?, ?) ON CONFLICT (account_hash) DO NOTHING`).bind(key, revision, body).run()
            : await env.DB.prepare(`UPDATE account_state SET revision = ?, ciphertext = ?
                WHERE account_hash = ? AND revision = ?`).bind(revision, body, key, match).run();
          return result.meta.changes === 1
            ? response(create ? 201 : 204, null, { ETag: revision })
            : response(412);
        }
        case 'DELETE': {
          if (!revisionPattern.test(match)) return response(428);
          const result = await env.DB.prepare('DELETE FROM account_state WHERE account_hash = ? AND revision = ?')
            .bind(key, match).run();
          return response(result.meta.changes === 1 ? 204 : 412);
        }
        default:
          return response(405, null, { Allow: 'GET, PUT, DELETE, OPTIONS' });
      }
    } catch {
      console.error('Periodify sync storage request failed');
      return response(503);
    }
  },
};
