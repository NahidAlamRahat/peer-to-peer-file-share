// PeerTransfer Service Worker — handles only the in-browser download stream.
// PWA caching is intentionally omitted to avoid interfering with Flutter's
// asset loading pipeline.

const map = new Map();

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
        const meta = map.get(data.id);
        if (meta) {
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
        console.log('Stream cancelled by user:', reason);
        if (clientPort) {
          clientPort.postMessage(JSON.stringify({ type: 'cancelled', id: data.id }));
        }
        map.delete(data.id);
      }
    }, { highWaterMark: 1024 * 1024 * 16 });

    map.set(data.id, {
      stream,
      controller,
      filename: data.filename,
      mimeType: data.mimeType || 'application/octet-stream',
      fileSize: data.fileSize || 0,
      isPaused: false,
      pauseTimer: null,
      clientPort: clientPort
    });

    if (clientPort) {
      clientPort.postMessage('started');
    }

  } else if (data.type === 'chunk') {
    const meta = map.get(data.id);
    if (meta && meta.controller) {
      meta.controller.enqueue(new Uint8Array(data.data));

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

  // Only intercept our download stream requests — everything else passes through.
  if (!url.pathname.includes('/pt-download-stream/')) return;

  const id = url.pathname.split('/').pop();
  const meta = map.get(id);

  if (meta) {
    const headers = new Headers({
      'Content-Type': meta.mimeType,
      'Content-Disposition': 'attachment; filename="' + encodeURIComponent(meta.filename) + '"'
    });
    if (meta.fileSize > 0) {
      headers.set('Content-Length', String(meta.fileSize));
    }
    event.respondWith(new Response(meta.stream, { headers }));
  } else {
    event.respondWith(new Response("Stream not found or expired", { status: 404 }));
  }
});
