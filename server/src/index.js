import http from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { Tracker } from './tracker.js';
import { SOURCE_NAME, SOURCE_URL } from './espn.js';

const PORT = Number(process.env.PORT ?? 8080);
const PUBLIC_DIR = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../public');
const HEARTBEAT_MS = 20000;

const tracker = new Tracker();
const clients = new Set(); // { res, matchId }

// ───────────── Server-Sent Events fan-out ─────────────
// One poll of the data source → pushed to every connected browser / app.

function send(res, event, data) {
  res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
}

function broadcast(event, data, matchId = null) {
  for (const client of clients) {
    if (matchId && client.matchId && client.matchId !== matchId) continue;
    send(client.res, event, data);
  }
}

tracker.on('matches', (list) => broadcast('matches', list));
tracker.on('update', ({ match, scorecard }) => broadcast('update', { match, scorecard }, match.id));
tracker.on('ball', ({ matchId, ball }) => broadcast('ball', { matchId, ball }, matchId));

setInterval(() => {
  for (const { res } of clients) res.write(`: ping ${Date.now()}\n\n`);
}, HEARTBEAT_MS).unref();

async function openStream(req, res, url) {
  const matchId = url.searchParams.get('match');
  res.writeHead(200, {
    'content-type': 'text/event-stream; charset=utf-8',
    'cache-control': 'no-cache, no-transform',
    'connection': 'keep-alive',
    'x-accel-buffering': 'no',
    'access-control-allow-origin': '*',
  });
  res.write('retry: 3000\n\n');
  const client = { res, matchId };
  clients.add(client);
  tracker.viewers = clients.size;
  tracker.touch();

  send(res, 'matches', tracker.list());
  if (matchId) {
    const card = await tracker.scorecard(matchId).catch(() => null);
    if (card) send(res, 'update', { match: card.match, scorecard: card });
  }

  req.on('close', () => {
    clients.delete(client);
    tracker.viewers = clients.size;
    tracker.touch();
  });
}

// ───────────── HTTP ─────────────

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
};

function json(res, status, body, extraHeaders = {}) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'access-control-allow-origin': '*',
    ...extraHeaders,
  });
  res.end(JSON.stringify(body));
}

async function serveStatic(res, pathname) {
  let rel = pathname === '/' ? 'index.html' : decodeURIComponent(pathname).replace(/^\/+/, '');
  if (!path.extname(rel)) rel += '.html'; // clean URLs: /privacy → privacy.html (same as Vercel)
  const file = path.resolve(PUBLIC_DIR, rel);
  if (!file.startsWith(PUBLIC_DIR + path.sep)) return json(res, 403, { error: 'forbidden' });
  try {
    const body = await readFile(file);
    const ext = path.extname(file);
    res.writeHead(200, {
      'content-type': MIME[ext] ?? 'application/octet-stream',
      'cache-control': 'no-cache', // always revalidate so code updates show up immediately
      'x-content-type-options': 'nosniff',
    });
    res.end(body);
  } catch {
    json(res, 404, { error: 'not found' });
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
  const { pathname } = url;

  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET', 'access-control-max-age': '86400' });
    return res.end();
  }
  if (req.method !== 'GET' && req.method !== 'HEAD') return json(res, 405, { error: 'method not allowed' });

  try {
    if (pathname === '/api/stream') return openStream(req, res, url);

    if (pathname === '/api/matches') {
      tracker.touch();
      return json(res, 200, tracker.list());
    }

    const m = pathname.match(/^\/api\/matches\/([\w-]+)$/);
    if (m) {
      tracker.touch();
      const card = await tracker.scorecard(m[1]);
      return card ? json(res, 200, card) : json(res, 404, { error: 'match not found' });
    }

    if (pathname === '/api/health' || pathname === '/healthz') {
      return json(res, 200, { ...tracker.health(), clients: clients.size, source: SOURCE_NAME, sourceUrl: SOURCE_URL });
    }

    return serveStatic(res, pathname);
  } catch (err) {
    console.error(err);
    if (!res.headersSent) json(res, 500, { error: 'internal error' });
    else res.end();
  }
});

server.listen(PORT, () => {
  console.log(`Cricket Live on http://localhost:${PORT}  (source: ${SOURCE_NAME})`);
});
tracker.start();

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => {
    tracker.stop();
    for (const { res } of clients) res.end();
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 2000).unref();
  });
}
