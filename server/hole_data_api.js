const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = Number(process.env.PORT || 8787);
const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = path.join(DATA_DIR, 'hole-data.json');

function ensureStore() {
  if (!fs.existsSync(DATA_DIR)) {
    fs.mkdirSync(DATA_DIR, { recursive: true });
  }
  if (!fs.existsSync(DATA_FILE)) {
    fs.writeFileSync(
      DATA_FILE,
      JSON.stringify({ courses: [], contributions: [], holeFacts: [] }, null, 2),
    );
  }
}

function readStore() {
  ensureStore();
  return JSON.parse(fs.readFileSync(DATA_FILE, 'utf8'));
}

function writeStore(store) {
  ensureStore();
  fs.writeFileSync(DATA_FILE, JSON.stringify(store, null, 2));
}

function sendJson(res, statusCode, body) {
  res.writeHead(statusCode, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    'access-control-allow-headers': 'content-type',
  });
  res.end(JSON.stringify(body));
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = '';
    req.on('data', (chunk) => {
      raw += chunk;
      if (raw.length > 128 * 1024) {
        reject(new Error('Payload too large'));
        req.destroy();
      }
    });
    req.on('end', () => resolve(raw ? JSON.parse(raw) : {}));
    req.on('error', reject);
  });
}

function normalizeInt(value, min, max) {
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < min || parsed > max) return null;
  return parsed;
}

function contributionKey(item) {
  return `${item.courseId}|${item.courseCode}|${item.holeNo}`;
}

function aggregateFacts(contributions) {
  const groups = new Map();
  for (const item of contributions) {
    const key = contributionKey(item);
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(item);
  }

  return [...groups.entries()].map(([key, rows]) => {
    const [courseId, courseCode, holeNoText] = key.split('|');
    const distances = rows.map((row) => row.distanceM).sort((a, b) => a - b);
    const medianIndex = Math.floor(distances.length / 2);
    const distanceM = distances.length % 2
      ? distances[medianIndex]
      : Math.round((distances[medianIndex - 1] + distances[medianIndex]) / 2);
    const parCounts = rows.reduce((counts, row) => {
      counts[row.par] = (counts[row.par] || 0) + 1;
      return counts;
    }, {});
    const par = Number(
      Object.entries(parCounts).sort((a, b) => b[1] - a[1])[0][0],
    );
    const scoreSamples = rows.flatMap((row) => row.anonymousScores || []);
    const averageScore = scoreSamples.length
      ? Math.round((scoreSamples.reduce((sum, score) => sum + score, 0) / scoreSamples.length) * 10) / 10
      : null;
    const difficultyOverPar = averageScore == null
      ? null
      : Math.round((averageScore - par) * 10) / 10;

    return {
      courseId,
      courseCode,
      holeNo: Number(holeNoText),
      distanceM,
      par,
      averageScore,
      difficultyOverPar,
      scoreSampleCount: scoreSamples.length,
      sampleCount: rows.length,
      confidence: rows.length >= 5 ? 'trusted' : 'draft',
      updatedAt: new Date().toISOString(),
    };
  });
}

function validateContribution(body) {
  const facts = Array.isArray(body.facts) ? body.facts : [];
  return facts.map((item) => {
    const courseId = String(item.courseId || '').trim();
    const courseCode = String(item.courseCode || '').trim().toUpperCase();
    const holeNo = normalizeInt(item.holeNo, 1, 9);
    const distanceM = normalizeInt(item.distanceM, 1, 300);
    const par = normalizeInt(item.par, 3, 5);
    const anonymousScores = Array.isArray(item.anonymousScores)
      ? item.anonymousScores
        .map((score) => normalizeInt(score, 1, 20))
        .filter((score) => score != null)
      : [];
    if (!courseId || !['A', 'B', 'C', 'D'].includes(courseCode)) return null;
    if (holeNo == null || distanceM == null || par == null) return null;
    return {
      courseId,
      courseCode,
      holeNo,
      distanceM,
      par,
      anonymousScores,
      clientIdHash: String(body.clientIdHash || 'anonymous').slice(0, 80),
      createdAt: new Date().toISOString(),
    };
  }).filter(Boolean);
}

async function handleRequest(req, res) {
  if (req.method === 'OPTIONS') {
    sendJson(res, 204, {});
    return;
  }

  const url = new URL(req.url, `http://${req.headers.host}`);
  const store = readStore();

  if (req.method === 'GET' && url.pathname === '/health') {
    sendJson(res, 200, { ok: true });
    return;
  }

  if (req.method === 'GET' && url.pathname === '/hole-facts') {
    const courseId = url.searchParams.get('courseId');
    const facts = courseId
      ? store.holeFacts.filter((item) => item.courseId === courseId)
      : store.holeFacts;
    sendJson(res, 200, { facts });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/contributions') {
    const body = await readBody(req);
    const rows = validateContribution(body);
    if (rows.length === 0) {
      sendJson(res, 400, { error: 'No valid hole facts supplied' });
      return;
    }
    store.contributions.push(...rows);
    store.holeFacts = aggregateFacts(store.contributions);
    writeStore(store);
    sendJson(res, 201, { accepted: rows.length, facts: store.holeFacts });
    return;
  }

  if (req.method === 'POST' && url.pathname === '/courses') {
    const body = await readBody(req);
    const name = String(body.name || '').trim();
    const address = String(body.address || '').trim();
    if (!name || !address) {
      sendJson(res, 400, { error: 'name and address are required' });
      return;
    }
    const course = {
      id: `user-${Date.now()}`,
      name,
      region: String(body.region || '직접등록').trim(),
      address,
      phone: String(body.phone || '').trim(),
      holeCount: normalizeInt(body.holeCount, 1, 108) || 0,
      source: 'user',
      createdAt: new Date().toISOString(),
    };
    store.courses.push(course);
    writeStore(store);
    sendJson(res, 201, { course });
    return;
  }

  sendJson(res, 404, { error: 'Not found' });
}

const server = http.createServer((req, res) => {
  handleRequest(req, res).catch((error) => {
    sendJson(res, 500, { error: error.message });
  });
});

server.listen(PORT, () => {
  console.log(`Park golf hole data API listening on http://localhost:${PORT}`);
});
