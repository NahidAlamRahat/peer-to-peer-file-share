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
    }, { highWaterMark: 1024 * 1024 * 5 }); // 5MB buffer to absorb jitter
    map.set(data.id, {
      stream,
      controller,
      filename: data.filename,
      mimeType: data.mimeType || 'application/octet-stream',
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
      // We use a 500ms debounce to avoid false positives when the browser
      // is simply a little slow to read — which happens during normal fast downloads.
      if (meta.controller.desiredSize <= 0 && !meta.isPaused && !meta.pauseTimer) {
        meta.pauseTimer = setTimeout(() => {
          meta.pauseTimer = null;
          // Re-check: is it still full after 500ms? Then it's a real pause.
          if (meta.controller.desiredSize <= 0 && !meta.isPaused) {
            meta.isPaused = true;
            if (meta.clientPort) meta.clientPort.postMessage(JSON.stringify({ type: 'pause', id: data.id }));
          }
        }, 500);
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
