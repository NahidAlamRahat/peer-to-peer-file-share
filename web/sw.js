// ── Cache name — bump version to force update on all clients ─────────────────
const CACHE_NAME = 'peertransfer-v1';

// Flutter assets to cache for offline PWA support
const FLUTTER_ASSETS = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/manifest.json',
  '/favicon.png',
];

const map = new Map();

self.addEventListener('install', (event) => {
  self.skipWaiting();
  // Pre-cache core shell assets
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(FLUTTER_ASSETS).catch(() => {
        // Ignore individual asset failures — they will be cached on first fetch
      });
    })
  );
});

self.addEventListener('activate', event => {
  // Remove old caches from previous versions
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      )
    ).then(() => self.clients.claim())
  );
});

self.addEventListener('message', event => {
  // Allow index.html to force-activate a waiting SW immediately
  if (event.data && event.data.type === 'SKIP_WAITING') {
    self.skipWaiting();
    return;
  }

  const data = event.data;
  if (!data || !data.id) return;
  
  if (data.type === 'start') {
    let controller;
    const clientPort = event.ports && event.ports[0];
    const stream = new ReadableStream({
      start(c) {
        controller = c;
      },
      pull(c) {
        // Browser is reading data again (resumed or just draining buffer)
        const meta = map.get(data.id);
        if (meta) {
          // Clear any pending debounce timer — browser is clearly reading, not paused
          if (meta.pauseTimer) {
            clearTimeout(meta.pauseTimer);
            meta.pauseTimer = null;
          }
          if (meta.isPaused) {
            meta.isPaused = false;
            if (clientPort) {
              clientPort.postMessage(JSON.stringify({ type: 'resume', id: data.id }));
            }
          }
        }
      },
      cancel(reason) {
        // Triggered when user cancels download from browser UI
        console.log('Stream cancelled by user:', reason);
        if (clientPort) {
          clientPort.postMessage(JSON.stringify({ type: 'cancelled', id: data.id }));
        }
        map.delete(data.id);
      }
    }, { highWaterMark: 1024 * 1024 * 16 }); // 16MB buffer — matches 256KB WiFi chunks
    map.set(data.id, {
      stream,
      controller,
      filename: data.filename,
      mimeType: data.mimeType || 'application/octet-stream',
      fileSize: data.fileSize || 0, // 0 = unknown (no Content-Length header)
      isPaused: false,
      pauseTimer: null,
      clientPort: clientPort
    });
    
    // We send back an ack so the client knows it can navigate to the url safely
    if (clientPort) {
      clientPort.postMessage('started');
    }
  } else if (data.type === 'chunk') {
    const meta = map.get(data.id);
    if (meta && meta.controller) {
      // data.data is an ArrayBuffer or Uint8Array
      meta.controller.enqueue(new Uint8Array(data.data));
      
      // If the buffer is full, it means the browser MAY have paused.
      if (meta.controller.desiredSize <= 0 && !meta.isPaused && !meta.pauseTimer) {
        meta.pauseTimer = setTimeout(() => {
          meta.pauseTimer = null;
          if (meta.controller.desiredSize <= 0 && !meta.isPaused) {
            meta.isPaused = true;
            if (meta.clientPort) meta.clientPort.postMessage(JSON.stringify({ type: 'pause', id: data.id }));
          }
        }, 1000);
      }
    }
  } else if (data.type === 'end') {
    const meta = map.get(data.id);
    if (meta && meta.controller) {
      meta.controller.close();
      map.delete(data.id);
    }
  } else if (data.type === 'abort') {
    const meta = map.get(data.id);
    if (meta && meta.controller) {
      meta.controller.error(new Error("Aborted by client"));
      map.delete(data.id);
    }
  }
});

self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // ── P2P download stream ───────────────────────────────────────────────────
  if (url.pathname.includes('/pt-download-stream/')) {
    const id = url.pathname.split('/').pop();
    const meta = map.get(id);
    if (meta) {
      const headers = new Headers({
        'Content-Type': meta.mimeType,
        'Content-Disposition': 'attachment; filename="'+ encodeURIComponent(meta.filename) +'"'
      });
      if (meta.fileSize > 0) {
        headers.set('Content-Length', String(meta.fileSize));
      }
      event.respondWith(new Response(meta.stream, { headers }));
    } else {
      event.respondWith(new Response("Stream not found or expired", { status: 404 }));
    }
    return;
  }

  // ── PWA offline caching (network-first with cache fallback) ──────────────
  // Skip cross-origin requests (ads, analytics, CDN fonts, etc.)
  if (!url.origin.startsWith(self.location.origin)) return;

  // Skip API / WebSocket requests
  if (url.pathname.startsWith('/pt-download-stream/')) return;

  event.respondWith(
    fetch(event.request)
      .then((response) => {
        // Cache successful GET responses for Flutter assets
        if (event.request.method === 'GET' && response.status === 200) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => cache.put(event.request, clone));
        }
        return response;
      })
      .catch(() => {
        // Network failed — serve from cache (offline mode)
        return caches.match(event.request).then((cached) => {
          if (cached) return cached;
          // For navigation requests, return cached index.html
          if (event.request.mode === 'navigate') {
            return caches.match('/index.html');
          }
          return new Response('Offline', { status: 503 });
        });
      })
  );
});
