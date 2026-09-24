// Vercel Serverless Function: /api/relay.js
// Simple SDP relay for auto-connect without manual answer QR scan.
// Stores offer/answer temporarily in a shared Map (warm instance cache).
// TTL: 5 minutes per entry.

const store = new Map(); // { code: { data, type, ts } }
const TTL_MS = 5 * 60 * 1000; // 5 minutes

function cleanup() {
  const now = Date.now();
  for (const [k, v] of store) {
    if (now - v.ts > TTL_MS) store.delete(k);
  }
}

export default function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') return res.status(200).end();

  cleanup();

  const { code, type } = req.query; // type = 'offer' | 'answer'
  if (!code || !type) return res.status(400).json({ error: 'Missing code or type' });

  const key = `${code.toUpperCase()}_${type}`;

  if (req.method === 'POST') {
    // Store SDP
    let body = '';
    req.on('data', chunk => (body += chunk));
    req.on('end', () => {
      if (!body) return res.status(400).json({ error: 'Empty body' });
      store.set(key, { data: body, ts: Date.now() });
      return res.status(200).json({ ok: true });
    });
  } else if (req.method === 'GET') {
    // Retrieve SDP (poll)
    const entry = store.get(key);
    if (!entry) return res.status(404).json({ error: 'Not found yet' });
    return res.status(200).send(entry.data);
  } else {
    return res.status(405).json({ error: 'Method not allowed' });
  }
}
