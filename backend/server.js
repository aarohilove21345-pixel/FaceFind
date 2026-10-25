'use strict';

const crypto = require('crypto');
const express = require('express');
const multer = require('multer');
const rateLimit = require('express-rate-limit');

const PORT = process.env.PORT || 3000;
// Secrets come only from the hosting dashboard, never from code.
const SERPAPI_KEY = process.env.SERPAPI_KEY;
const PUBLIC_URL = (process.env.PUBLIC_URL || process.env.RENDER_EXTERNAL_URL || '').replace(/\/$/, '');
// Free SerpApi plan = 250 searches per month, so cap searches per day.
const DAILY_LIMIT = Number(process.env.DAILY_LIMIT || 8);

const MAX_BYTES = 10 * 1024 * 1024;
const IMAGE_TTL_MS = 5 * 60 * 1000;
const RESULT_TTL_MS = 30 * 60 * 1000;

const app = express();
app.set('trust proxy', 1);
app.disable('x-powered-by');

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_BYTES, files: 1 },
});

const images = new Map();
const results = new Map();
const idempotency = new Map();

let currentDay = new Date().toISOString().slice(0, 10);
let usedToday = 0;

function takeSlot() {
  const today = new Date().toISOString().slice(0, 10);
  if (today !== currentDay) {
    currentDay = today;
    usedToday = 0;
  }
  if (usedToday >= DAILY_LIMIT) return false;
  usedToday += 1;
  return true;
}

function refundSlot() {
  usedToday = Math.max(0, usedToday - 1);
}

function sniffType(buf) {
  if (!buf || buf.length < 12) return null;
  if (buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  const png = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
  if (buf.subarray(0, 8).equals(png)) return 'image/png';
  if (
    buf.subarray(0, 4).toString('ascii') === 'RIFF' &&
    buf.subarray(8, 12).toString('ascii') === 'WEBP'
  ) {
    return 'image/webp';
  }
  return null;
}

setInterval(() => {
  const now = Date.now();
  for (const [k, v] of images) if (v.expires < now) images.delete(k);
  for (const [k, v] of results) if (v.expires < now) results.delete(k);
  for (const [k, v] of idempotency) if (v.expires < now) idempotency.delete(k);
}, 60 * 1000).unref();

const limiter = rateLimit({
  windowMs: 10 * 60 * 1000,
  limit: 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests. Please try again later.' },
});

app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    configured: Boolean(SERPAPI_KEY && PUBLIC_URL),
  });
});

// Temporary public link so the search engine can fetch the photo.
// The token is random, and the photo is deleted right after the scan.
app.get('/tmp/:token', (req, res) => {
  const item = images.get(req.params.token);
  if (!item || item.expires < Date.now()) {
    return res.status(404).end();
  }
  res.set('Content-Type', item.type);
  res.set('Cache-Control', 'no-store');
  res.send(item.buffer);
});

async function serpSearch(params) {
  const query = new URLSearchParams({ ...params, api_key: SERPAPI_KEY });
  const upstream = await fetch(`https://serpapi.com/search.json?${query}`, {
    signal: AbortSignal.timeout(60 * 1000),
  });
  let data = {};
  try {
    data = await upstream.json();
  } catch (_) {
    data = {};
  }
  return { ok: upstream.ok && !data.error, status: upstream.status, data };
}

function pickMatches(list) {
  const out = [];
  const seen = new Set();
  if (!Array.isArray(list)) return out;
  for (const item of list) {
    if (out.length >= 20) break;
    if (!item || typeof item.link !== 'string' || !/^https?:\/\//i.test(item.link)) continue;
    if (seen.has(item.link)) continue;
    seen.add(item.link);
    let preview = null;
    if (item.thumbnail && typeof item.thumbnail === 'object') preview = item.thumbnail.link;
    else if (typeof item.thumbnail === 'string') preview = item.thumbnail;
    else if (typeof item.image === 'string') preview = item.image;
    if (typeof preview !== 'string' || !/^https?:\/\//i.test(preview)) preview = null;
    out.push({
      platform: item.source || null,
      title: item.title || null,
      profile_url: item.link,
      preview_url: preview,
    });
  }
  return out;
}

app.post('/api/scans', limiter, upload.single('image'), async (req, res) => {
  if (!SERPAPI_KEY || !PUBLIC_URL) {
    return res.status(503).json({ error: 'The service is not configured yet.' });
  }

  // A repeated request with the same key never runs a second search.
  const idemKey = req.get('Idempotency-Key');
  if (idemKey && idempotency.has(idemKey)) {
    return res.json(idempotency.get(idemKey).body);
  }

  if (!req.file) {
    return res.status(400).json({ error: 'No photo was uploaded.' });
  }
  const type = sniffType(req.file.buffer);
  if (!type) {
    return res.status(422).json({ error: 'Unsupported image. Please use a JPG, PNG or WebP photo.' });
  }
  if (!takeSlot()) {
    return res.status(402).json({ error: 'The free daily search limit has been reached. Please try again tomorrow.' });
  }

  const ext = type === 'image/png' ? 'png' : type === 'image/webp' ? 'webp' : 'jpg';
  const key = `${crypto.randomBytes(24).toString('hex')}.${ext}`;
  images.set(key, { buffer: req.file.buffer, type, expires: Date.now() + IMAGE_TTL_MS });

  try {
    const imageUrl = `${PUBLIC_URL}/tmp/${key}`;
    let matches = [];
    let anyOk = false;
    let lastFail = null;

    // 1) Google Lens first. 2) Yandex only if Lens found nothing or failed.
    const lens = await serpSearch({ engine: 'google_lens', url: imageUrl });
    if (lens.ok) {
      anyOk = true;
      matches = pickMatches(lens.data.visual_matches);
    } else {
      lastFail = lens;
    }

    if (matches.length === 0) {
      const yandex = await serpSearch({ engine: 'yandex_images', url: imageUrl });
      if (yandex.ok) {
        anyOk = true;
        matches = pickMatches(yandex.data.image_results);
      } else {
        lastFail = yandex;
      }
    }

    if (!anyOk) {
      refundSlot();
      const msg = String((lastFail && lastFail.data && lastFail.data.error) || '').toLowerCase();
      const code = lastFail ? lastFail.status : 0;
      if (code === 429 || msg.includes('run out of searches')) {
        return res.status(402).json({ error: 'The search service has no searches left this month.' });
      }
      if (code === 401 || code === 403) {
        return res.status(502).json({ error: 'The search service rejected the request.' });
      }
      return res.status(502).json({ error: 'The search service could not process this photo.' });
    }

    const id = crypto.randomBytes(12).toString('hex');
    const body = { id, status: 'completed', matches, credits: null };
    results.set(id, { body, expires: Date.now() + RESULT_TTL_MS });
    if (idemKey) idempotency.set(idemKey, { body, expires: Date.now() + RESULT_TTL_MS });
    return res.json(body);
  } catch (err) {
    refundSlot();
    const timedOut = err && (err.name === 'TimeoutError' || err.name === 'AbortError');
    return res.status(timedOut ? 504 : 502).json({
      error: timedOut ? 'The search took too long. Please try again.' : 'The search service is unavailable. Please try again later.',
    });
  } finally {
    // The photo is removed as soon as the search is finished.
    images.delete(key);
  }
});

app.get('/api/usage', (req, res) => {
  const today = new Date().toISOString().slice(0, 10);
  if (today !== currentDay) {
    currentDay = today;
    usedToday = 0;
  }
  res.json({
    daily_limit: DAILY_LIMIT,
    used_today: usedToday,
    remaining_today: Math.max(0, DAILY_LIMIT - usedToday),
  });
});

app.get('/api/scans/:id', (req, res) => {
  const item = results.get(req.params.id);
  if (!item || item.expires < Date.now()) {
    return res.status(404).json({ error: 'This scan could not be found.' });
  }
  return res.json(item.body);
});

app.use((err, req, res, next) => {
  if (err && err.code === 'LIMIT_FILE_SIZE') {
    return res.status(413).json({ error: 'The photo is too large. Maximum size is 10 MB.' });
  }
  if (err && err.name === 'MulterError') {
    return res.status(400).json({ error: 'The upload was invalid.' });
  }
  return res.status(500).json({ error: 'Something went wrong on the server.' });
});

app.listen(PORT, () => {
  console.log(`FaceFind backend listening on port ${PORT}`);
  if (!SERPAPI_KEY || !PUBLIC_URL) {
    console.log('Warning: SERPAPI_KEY or PUBLIC_URL is not set.');
  }
});
