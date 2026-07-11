/**
 * §11.4.170 host-rendered visual-proof harness.
 *
 * Boots a mock API (authoritative contract) + `vite preview` of the production
 * build, then captures EVERY route in BOTH light and dark themes via
 * Playwright chromium → qa/results/stream4/screenshots/*.png.
 *
 * A build that compiles is necessary but NOT sufficient — this harness proves
 * the screens actually mount and render without runtime errors (console
 * errors fail the run).
 */
import http from 'node:http';
import { spawn } from 'node:child_process';
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const OUT = new URL('../qa/results/stream4/screenshots/', import.meta.url).pathname;
const API_PORT = 7722;
const WEB_PORT = 4173;
mkdirSync(OUT, { recursive: true });

const ACCOUNTS = [
  {
    username: 'alice',
    permission: 'read_write',
    uid: 1001,
    gid: 1001,
    home_dir: '/srv/sftp/alice',
    enabled: true,
    created_at: '2026-07-01T08:00:00Z',
    updated_at: '2026-07-05T12:30:00Z',
  },
  {
    username: 'backups',
    permission: 'read_only',
    uid: 1002,
    gid: 1002,
    home_dir: '/srv/sftp/backups',
    enabled: true,
    created_at: '2026-07-02T09:00:00Z',
    updated_at: '2026-07-02T09:00:00Z',
  },
  {
    username: 'legacy',
    permission: 'read_write',
    uid: null,
    gid: null,
    home_dir: '/srv/sftp/legacy',
    enabled: false,
    created_at: '2026-06-15T10:00:00Z',
    updated_at: '2026-07-06T07:15:00Z',
  },
];

const TOKENS = {
  access_token: 'screenshot-access-token',
  refresh_token: 'screenshot-refresh-token',
  token_type: 'Bearer',
  expires_in: 3600,
};

function sendJson(res, body, status = 200) {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify(body));
}

const mockApi = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const { pathname } = url;
  if (pathname === '/api/v1/health') return sendJson(res, { status: 'ok' });
  if (pathname === '/api/v1/auth/login') return sendJson(res, TOKENS);
  if (pathname === '/api/v1/auth/refresh') return sendJson(res, TOKENS);
  if (pathname === '/api/v1/auth/me') return sendJson(res, { username: 'admin' });
  if (pathname === '/api/v1/accounts' && req.method === 'GET') return sendJson(res, ACCOUNTS);
  if (pathname === '/api/v1/accounts' && req.method === 'POST') {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const parsed = JSON.parse(body);
      if (parsed.permission === 'public' && parsed.public_acknowledged !== true) {
        return sendJson(res, { error: 'public access requires acknowledgement' }, 422);
      }
      sendJson(res, { ...parsed, created_at: '', updated_at: '' }, 201);
    });
    return;
  }
  const match = pathname.match(/^\/api\/v1\/accounts\/([^/]+)$/);
  if (match && req.method === 'GET') {
    const acc = ACCOUNTS.find((a) => a.username === decodeURIComponent(match[1]));
    return acc ? sendJson(res, acc) : sendJson(res, { error: 'not found' }, 404);
  }
  if (pathname === '/api/v1/sync') return sendJson(res, { status: 'ok', synced: ACCOUNTS.length });
  sendJson(res, { error: 'not found' }, 404);
});

function waitForServer(port, timeoutMs = 15000) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    const attempt = () => {
      const req = http.get({ port, path: '/' }, (res) => {
        res.resume();
        resolve();
      });
      req.on('error', () => {
        if (Date.now() - start > timeoutMs) reject(new Error(`server on :${port} never came up`));
        else setTimeout(attempt, 200);
      });
    };
    attempt();
  });
}

const ROUTES = [
  { name: 'login', path: '/login' },
  { name: 'dashboard', path: '/' },
  { name: 'account-new', path: '/accounts/new' },
  { name: 'account-edit', path: '/accounts/alice/edit' },
  { name: 'settings', path: '/settings' },
];
const THEMES = ['light', 'dark'];

await new Promise((resolve) => mockApi.listen(API_PORT, resolve));
const preview = spawn('npx', ['vite', 'preview', '--port', String(WEB_PORT), '--strictPort'], {
  stdio: 'ignore',
});

let failures = 0;
try {
  await waitForServer(WEB_PORT);
  const browser = await chromium.launch();
  const consoleErrors = [];

  for (const theme of THEMES) {
    for (const route of ROUTES) {
      const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
      page.on('console', (msg) => {
        if (msg.type() === 'error') consoleErrors.push(`${route.name}/${theme}: ${msg.text()}`);
      });
      page.on('pageerror', (err) => consoleErrors.push(`${route.name}/${theme}: ${err.message}`));

      await page.addInitScript(
        ([t, authed]) => {
          localStorage.setItem('sftp.theme', t);
          if (authed) {
            localStorage.setItem('sftp.access_token', 'screenshot-access-token');
            localStorage.setItem('sftp.refresh_token', 'screenshot-refresh-token');
          }
        },
        [theme, route.name !== 'login'],
      );

      await page.goto(`http://localhost:${WEB_PORT}${route.path}`, { waitUntil: 'networkidle' });
      await page.screenshot({ path: `${OUT}${route.name}-${theme}.png`, fullPage: true });
      await page.close();
      console.log(`captured ${route.name}-${theme}.png`);
    }
  }

  // Public-ack guard visual state: permission=public selected, no ack yet.
  const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
  await page.addInitScript(() => {
    localStorage.setItem('sftp.theme', 'light');
    localStorage.setItem('sftp.access_token', 'screenshot-access-token');
    localStorage.setItem('sftp.refresh_token', 'screenshot-refresh-token');
  });
  await page.goto(`http://localhost:${WEB_PORT}/accounts/new`, { waitUntil: 'networkidle' });
  await page.selectOption('#acc-permission', 'public');
  await page.screenshot({ path: `${OUT}account-new-public-guard-light.png`, fullPage: true });
  await page.close();
  console.log('captured account-new-public-guard-light.png');

  await browser.close();

  if (consoleErrors.length) {
    failures++;
    console.error('CONSOLE/PAGE ERRORS:\n' + consoleErrors.join('\n'));
  }
} finally {
  preview.kill('SIGTERM');
  mockApi.close();
}

if (failures) {
  console.error('screenshot harness FAILED — runtime errors captured');
  process.exit(1);
}
console.log(`screenshots OK → ${OUT}`);
