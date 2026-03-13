/**
 * Project X — Cloudflare Worker Auth Gate
 *
 * Sits in front of the Cloudflare tunnel and requires an access key
 * before proxying requests to Kotaemon or RAGFlow.
 *
 * Secrets (set with `wrangler secret put`):
 *   ACCESS_KEY  — password that protects the app
 *   BACKEND_URL — current tunnel URL (auto-updated by tunnel script)
 */

// ── HMAC cookie helpers ─────────────────────────────────────────────────────

async function hmac(message, secret) {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return btoa(String.fromCharCode(...new Uint8Array(sig)))
    .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function makeSessionCookie(secret) {
  const ts = Date.now().toString();
  const sig = await hmac(ts, secret);
  return `${ts}.${sig}`;
}

async function verifySessionCookie(cookieHeader, secret) {
  const match = (cookieHeader || '').match(/px_session=([^;]+)/);
  if (!match) return false;
  const [ts, sig] = match[1].split('.');
  if (!ts || !sig) return false;
  if (Date.now() - parseInt(ts) > 86_400_000) return false; // 24 h
  const expected = await hmac(ts, secret);
  return expected === sig;
}

// ── Login page ──────────────────────────────────────────────────────────────

function loginPage(error = '') {
  return new Response(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Project X — Access</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{
      min-height:100vh;display:flex;align-items:center;justify-content:center;
      background:#0a0a0f;font-family:'Inter',system-ui,sans-serif;color:#e2e8f0;
    }
    .card{
      background:#12121a;border:1px solid #2a2a40;border-radius:16px;
      padding:40px 48px;width:100%;max-width:400px;text-align:center;
    }
    .logo{font-size:2rem;font-weight:800;letter-spacing:-1px;margin-bottom:8px}
    .logo span{color:#6c63ff}
    .sub{color:#64748b;font-size:.9rem;margin-bottom:32px}
    label{display:block;text-align:left;font-size:.8rem;color:#64748b;margin-bottom:6px;text-transform:uppercase;letter-spacing:.05em}
    input{
      width:100%;padding:12px 16px;background:#1a1a28;border:1px solid #2a2a40;
      border-radius:8px;color:#e2e8f0;font-size:1rem;outline:none;margin-bottom:16px;
    }
    input:focus{border-color:#6c63ff}
    button{
      width:100%;padding:12px;background:linear-gradient(135deg,#6c63ff,#a78bfa);
      border:none;border-radius:8px;color:#fff;font-size:1rem;font-weight:600;
      cursor:pointer;transition:opacity .2s;
    }
    button:hover{opacity:.9}
    .error{
      background:#3f1515;border:1px solid #ef4444;border-radius:8px;
      padding:10px 14px;font-size:.85rem;color:#fca5a5;margin-bottom:16px;
    }
  </style>
</head>
<body>
  <div class="card">
    <div class="logo">Project <span>X</span></div>
    <p class="sub">Enter your access key to continue</p>
    ${error ? `<div class="error">${error}</div>` : ''}
    <form method="POST" action="/__px_auth">
      <label>Access Key</label>
      <input type="password" name="key" placeholder="••••••••••••••••" autofocus required/>
      <button type="submit">Unlock →</button>
    </form>
  </div>
</body>
</html>`, {
    status: error ? 401 : 200,
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
}

// ── Main handler ────────────────────────────────────────────────────────────

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const cookieHeader = request.headers.get('Cookie') || '';

    // ── Auth form submission ────────────────────────────────────────────────
    if (url.pathname === '/__px_auth' && request.method === 'POST') {
      let key = '';
      try {
        const body = await request.formData();
        key = (body.get('key') || '').trim();
      } catch {
        return loginPage('Bad request.');
      }

      if (key === env.ACCESS_KEY) {
        const sessionVal = await makeSessionCookie(env.ACCESS_KEY);
        return new Response(null, {
          status: 302,
          headers: {
            Location: '/',
            'Set-Cookie': `px_session=${sessionVal}; Path=/; HttpOnly; Secure; SameSite=Strict; Max-Age=86400`,
          },
        });
      }
      return loginPage('Wrong key — try again.');
    }

    // ── Gate: require valid session cookie ──────────────────────────────────
    if (!(await verifySessionCookie(cookieHeader, env.ACCESS_KEY))) {
      return loginPage();
    }

    // ── No backend configured yet ───────────────────────────────────────────
    if (!env.BACKEND_URL) {
      return new Response('Backend not configured. Run ./scripts/cloudflare-tunnel.sh first.', {
        status: 503,
        headers: { 'Content-Type': 'text/plain' },
      });
    }

    // ── Proxy to backend ────────────────────────────────────────────────────
    const backend = env.BACKEND_URL.replace(/\/$/, '');
    const targetUrl = backend + url.pathname + url.search;

    // Forward headers, replacing Host with the backend hostname
    const backendHost = new URL(backend).hostname;
    const headers = new Headers(request.headers);
    headers.set('Host', backendHost);
    // Strip auth cookie before forwarding
    const stripped = cookieHeader.replace(/px_session=[^;]+(;\s*)?/, '').trim().replace(/^;\s*/, '');
    if (stripped) headers.set('Cookie', stripped);
    else headers.delete('Cookie');

    // WebSocket upgrade — Cloudflare handles the tunnel transparently
    if (request.headers.get('Upgrade') === 'websocket') {
      const wsTarget = targetUrl.replace(/^https/, 'wss').replace(/^http/, 'ws');
      return fetch(wsTarget, { headers });
    }

    // Regular HTTP
    return fetch(targetUrl, {
      method: request.method,
      headers,
      body: ['GET', 'HEAD'].includes(request.method) ? undefined : request.body,
      redirect: 'follow',
    });
  },
};
