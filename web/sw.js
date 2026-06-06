const map = new Map();

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', event => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('message', event => {
  const data = event.data;
  if (!data || !data.id) return;
  
  if (data.type === 'start') {
    let controller;
    const stream = new ReadableStream({
      start(c) {
        controller = c;
      }
    });
    map.set(data.id, {
      stream,
      controller,
      filename: data.filename,
      mimeType: data.mimeType || 'application/octet-stream'
    });
    
    // We send back an ack so the client knows it can navigate to the url safely
    if (event.ports && event.ports[0]) {
      event.ports[0].postMessage('started');
    }
  } else if (data.type === 'chunk') {
    const meta = map.get(data.id);
    if (meta && meta.controller) {
      // data.data is an ArrayBuffer or Uint8Array
      meta.controller.enqueue(new Uint8Array(data.data));
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
  // Match path containing /pt-download-stream/
  if (url.pathname.includes('/pt-download-stream/')) {
    const id = url.pathname.split('/').pop();
    const meta = map.get(id);
    if (meta) {
      const headers = new Headers({
        'Content-Type': meta.mimeType,
        // The attachment flag forces the browser's download manager to open
        'Content-Disposition': 'attachment; filename="'+ encodeURIComponent(meta.filename) +'"'
      });
      event.respondWith(new Response(meta.stream, { headers }));
    } else {
      event.respondWith(new Response("Stream not found or expired", { status: 404 }));
    }
  }
});
