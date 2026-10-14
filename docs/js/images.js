// Food photos on a white background.
//
// Online photos: Open Food Facts product shots, Wikimedia Commons photos taken on white, or the
// Wikipedia lead image. Candidates are scored by how white their border is and the best one wins.
// Every photo (including camera/library photos) is then cleaned: a light, uniform background touching
// the edges is flood-filled to pure white, the food is cropped and centered on a white square.

const SIDE = 800;
const WORK = 720;

export function loadImage(src, { cors = true } = {}) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    if (cors) img.crossOrigin = 'anonymous';
    img.decoding = 'async';
    img.onload = () => resolve(img);
    img.onerror = () => reject(new Error('Image failed to load'));
    img.src = src;
  });
}

function canvas(w, h) {
  const c = document.createElement('canvas');
  c.width = w;
  c.height = h;
  return c;
}

/** Fraction of border pixels that are near-white (0…1), or -1 if the image can't be read. */
export function borderWhiteness(img) {
  try {
    const c = canvas(64, 64);
    const ctx = c.getContext('2d', { willReadFrequently: true });
    ctx.drawImage(img, 0, 0, 64, 64);
    const { data } = ctx.getImageData(0, 0, 64, 64);
    let white = 0;
    let total = 0;
    for (let y = 0; y < 64; y++) {
      for (let x = 0; x < 64; x++) {
        if (x > 2 && x < 61 && y > 2 && y < 61) continue;
        const i = (y * 64 + x) * 4;
        const [r, g, b] = [data[i], data[i + 1], data[i + 2]];
        total++;
        if (Math.min(r, g, b) > 222 && Math.max(r, g, b) - Math.min(r, g, b) < 24) white++;
      }
    }
    // Reject near-empty images (diagrams, blank scans): need real content in the middle.
    let content = 0;
    for (let y = 16; y < 48; y++) {
      for (let x = 16; x < 48; x++) {
        const i = (y * 64 + x) * 4;
        if (Math.min(data[i], data[i + 1], data[i + 2]) < 200) content++;
      }
    }
    if (content < 32 * 32 * 0.15) return 0;
    return white / total;
  } catch {
    return -1;
  }
}

/** Flood-fills a light, uniform background from the edges to white; crops and centers on a white square. */
export function composeOnWhite(img) {
  const scale = Math.min(1, WORK / Math.max(img.naturalWidth || img.width, img.naturalHeight || img.height));
  const w = Math.max(1, Math.round((img.naturalWidth || img.width) * scale));
  const h = Math.max(1, Math.round((img.naturalHeight || img.height) * scale));
  const work = canvas(w, h);
  const ctx = work.getContext('2d', { willReadFrequently: true });
  ctx.fillStyle = '#fff';
  ctx.fillRect(0, 0, w, h);
  ctx.drawImage(img, 0, 0, w, h);

  let box = { x: 0, y: 0, w, h };
  try {
    const image = ctx.getImageData(0, 0, w, h);
    const cleaned = whitenBackground(image);
    if (cleaned) {
      ctx.putImageData(image, 0, 0);
      box = cleaned;
    }
  } catch {
    // Cross-origin image without CORS: keep the photo as is, centered on white.
  }

  const out = canvas(SIDE, SIDE);
  const o = out.getContext('2d');
  o.fillStyle = '#fff';
  o.fillRect(0, 0, SIDE, SIDE);
  const inner = SIDE * 0.86;
  const s = Math.min(inner / box.w, inner / box.h);
  const dw = box.w * s;
  const dh = box.h * s;
  o.imageSmoothingQuality = 'high';
  o.drawImage(work, box.x, box.y, box.w, box.h, (SIDE - dw) / 2, (SIDE - dh) / 2, dw, dh);
  return out.toDataURL('image/jpeg', 0.86);
}

function whitenBackground(image) {
  const { data, width: w, height: h } = image;
  // Estimate background from the border.
  let sr = 0, sg = 0, sb = 0, n = 0;
  const border = [];
  for (let x = 0; x < w; x++) border.push(x, (h - 1) * w + x);
  for (let y = 1; y < h - 1; y++) border.push(y * w, y * w + w - 1);
  for (const p of border) {
    sr += data[p * 4]; sg += data[p * 4 + 1]; sb += data[p * 4 + 2]; n++;
  }
  const bg = [sr / n, sg / n, sb / n];
  let dev = 0;
  for (const p of border) {
    dev += Math.abs(data[p * 4] - bg[0]) + Math.abs(data[p * 4 + 1] - bg[1]) + Math.abs(data[p * 4 + 2] - bg[2]);
  }
  dev /= n;
  const lum = 0.299 * bg[0] + 0.587 * bg[1] + 0.114 * bg[2];
  // Only clean plain, light backgrounds (studio / tabletop shots). Busy scenes are left alone.
  if (lum < 165 || dev > 45) return null;

  const tol = 46 + dev;
  const seen = new Uint8Array(w * h);
  const queue = new Int32Array(w * h);
  let head = 0, tail = 0;
  const close = (p) =>
    Math.abs(data[p * 4] - bg[0]) + Math.abs(data[p * 4 + 1] - bg[1]) + Math.abs(data[p * 4 + 2] - bg[2]) < tol * 1.6 &&
    Math.min(data[p * 4], data[p * 4 + 1], data[p * 4 + 2]) > lum - 70;
  for (const p of border) {
    if (!seen[p] && close(p)) { seen[p] = 1; queue[tail++] = p; }
  }
  while (head < tail) {
    const p = queue[head++];
    const x = p % w;
    const y = (p - x) / w;
    const nb = [x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1];
    for (const q of nb) {
      if (q >= 0 && !seen[q] && close(q)) { seen[q] = 1; queue[tail++] = q; }
    }
  }
  if (tail < w * h * 0.05) return null; // Hardly any background found.

  let minX = w, minY = h, maxX = -1, maxY = -1;
  for (let p = 0; p < w * h; p++) {
    if (seen[p]) {
      data[p * 4] = data[p * 4 + 1] = data[p * 4 + 2] = 255;
    } else {
      const x = p % w;
      const y = (p - x) / w;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < minX || (maxX - minX) * (maxY - minY) < w * h * 0.03) return null;
  return { x: minX, y: minY, w: maxX - minX + 1, h: maxY - minY + 1 };
}

// ---------- Finding photos online ----------

async function json(url) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(String(res.status));
  return res.json();
}

/** Wikimedia Commons photos that were shot on a white background. */
async function commonsCandidates(term) {
  const params = new URLSearchParams({
    action: 'query', format: 'json', formatversion: '2', origin: '*',
    generator: 'search', gsrnamespace: '6', gsrlimit: '6',
    gsrsearch: `${term} isolated white background filetype:bitmap`,
    prop: 'imageinfo', iiprop: 'url', iiurlwidth: '640',
  });
  try {
    const data = await json(`https://commons.wikimedia.org/w/api.php?${params}`);
    return (data.query?.pages ?? [])
      .sort((a, b) => (a.index ?? 0) - (b.index ?? 0))
      .map((p) => p.imageinfo?.[0]?.thumburl)
      .filter((u) => u && /\.jpe?g$/i.test(u));
  } catch {
    return [];
  }
}

/** Lead image of a Wikipedia article (by exact title, or the top search hit). */
async function wikipediaLead(title, query) {
  const params = new URLSearchParams({
    action: 'query', format: 'json', formatversion: '2', origin: '*',
    prop: 'pageimages', piprop: 'thumbnail', pithumbsize: '800', redirects: '1',
  });
  if (title) params.set('titles', title);
  else {
    params.set('generator', 'search');
    params.set('gsrsearch', query);
    params.set('gsrlimit', '1');
  }
  try {
    const data = await json(`https://en.wikipedia.org/w/api.php?${params}`);
    return data.query?.pages?.find((p) => p.thumbnail)?.thumbnail.source ?? null;
  } catch {
    return null;
  }
}

/** "Collard greens, cooked" → "Collard greens" */
function searchTerm(name) {
  return String(name).split(/[,(]/)[0].trim() || name;
}

/** Finds the best photo for a food and returns it as a white-background JPEG data URL (or null). */
export async function findFoodImage({ name, imageSourceURL, imageSearchTerm }) {
  if (imageSourceURL) {
    try {
      return composeOnWhite(await loadImage(imageSourceURL));
    } catch { /* fall through to other sources */ }
  }
  const term = searchTerm(name);
  const [commons, lead] = await Promise.all([commonsCandidates(term), wikipediaLead(imageSearchTerm, term)]);
  const urls = [...commons.slice(0, 4), lead].filter(Boolean);

  let best = null;
  for (const url of urls) {
    let img;
    try { img = await loadImage(url); } catch { continue; }
    const score = borderWhiteness(img);
    // Give the encyclopedia lead image a small edge: it's the most reliably on-topic.
    const adjusted = url === lead ? score + 0.15 : score;
    if (!best || adjusted > best.score) best = { img, score: adjusted };
    if (score > 0.92) break;
  }
  if (!best) return null;
  try {
    return composeOnWhite(best.img);
  } catch {
    return null;
  }
}

/** Processes a photo the user took or picked. */
export async function photoFileToWhite(file) {
  const url = URL.createObjectURL(file);
  try {
    return composeOnWhite(await loadImage(url, { cors: false }));
  } finally {
    URL.revokeObjectURL(url);
  }
}
