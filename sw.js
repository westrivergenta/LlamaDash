// ラマダッシュ Service Worker：オフラインで遊べるようにファイルを保存する
// ゲームを更新して公開したら、この番号を必ず上げてください（v2, v3 …）。
const VERSION = 'v1';
const APP_CACHE = 'llama-dash-app-' + VERSION;
const FONT_CACHE = 'llama-dash-fonts';
const ASSETS = [
  './',
  './index.html',
  './config.js',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
  './icons/favicon-32.png'
];

self.addEventListener('install', event => {
  event.waitUntil(caches.open(APP_CACHE).then(c => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys()
      .then(keys => Promise.all(keys.filter(k => k.startsWith('llama-dash-app-') && k !== APP_CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);

  // Google Fonts：保存済みを使い、裏で更新
  if (url.hostname === 'fonts.googleapis.com' || url.hostname === 'fonts.gstatic.com') {
    event.respondWith(staleWhileRevalidate(req, FONT_CACHE));
    return;
  }
  // ランキングなど他サイトへの通信は触らない
  if (url.origin !== self.location.origin) return;

  // ページを開くとき：オフラインなら保存済みの index.html
  if (req.mode === 'navigate') {
    event.respondWith(
      fetch(req).then(res => { putCache(APP_CACHE, './index.html', res.clone()); return res; })
        .catch(() => caches.match('./index.html', {ignoreSearch: true}))
    );
    return;
  }
  event.respondWith(staleWhileRevalidate(req, APP_CACHE));
});

function putCache(name, key, res) {
  if (res && (res.ok || res.type === 'opaque')) caches.open(name).then(c => c.put(key, res)).catch(() => {});
}
async function staleWhileRevalidate(req, name) {
  const cached = await caches.match(req, {ignoreSearch: true});
  const network = fetch(req).then(res => { putCache(name, req, res.clone()); return res; }).catch(() => cached);
  return cached || network;
}
