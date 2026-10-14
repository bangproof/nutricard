// Network lookups: Open Food Facts (barcodes) and USDA FoodData Central (names).
import { emptyDraft, prettify, upcEquivalent, upcVariants, formatPlain } from './core.js';

async function getJSON(url) {
  let res;
  try {
    res = await fetch(url, { headers: { Accept: 'application/json' } });
  } catch {
    throw new Error('Network error — check your connection.');
  }
  if (res.status === 404) return null;
  if (res.status === 429) throw new Error('Too many requests. Wait a moment and try again (or add your own USDA API key).');
  if (res.status === 403) throw new Error('The server refused the request — check your USDA API key.');
  if (!res.ok) throw new Error(`The server returned an error (${res.status}).`);
  return res.json();
}

const num = (v) => {
  if (typeof v === 'number') return Number.isFinite(v) ? v : null;
  if (typeof v === 'string') {
    const n = parseFloat(v.replace(',', '.'));
    return Number.isFinite(n) ? n : null;
  }
  return null;
};

// ---------- Open Food Facts ----------

export function draftFromOpenFoodFacts(json, upc) {
  if (!json || json.status !== 1 || !json.product) return null;
  const p = json.product;
  const n = p.nutriments ?? {};
  const servingGrams = num(p.serving_quantity) > 0 ? num(p.serving_quantity) : null;
  const hasServing = ['energy-kcal', 'carbohydrates', 'proteins'].some((k) => num(n[`${k}_serving`]) != null);

  const amount = (key) => {
    if (hasServing) return num(n[`${key}_serving`]);
    const per100 = num(n[`${key}_100g`]);
    return per100 == null ? null : (per100 * (servingGrams ?? 100)) / 100;
  };
  const times = (v, f) => (v == null ? null : v * f);

  const d = emptyDraft(p.product_name?.trim() || `Product ${upc}`);
  d.brand = (p.brands ?? '').split(',')[0].trim();
  d.upc = upc;
  d.emoji = '🛒';
  if (hasServing || servingGrams != null) {
    d.servingDescription = p.serving_size?.trim() || (servingGrams ? `${formatPlain(servingGrams)} g` : '1 serving');
    d.servingGrams = servingGrams;
  } else {
    d.servingDescription = '100 g';
    d.servingGrams = 100;
  }
  d.calories = amount('energy-kcal') ?? times(amount('energy'), 1 / 4.184);
  d.totalFat = amount('fat');
  d.saturatedFat = amount('saturated-fat');
  d.transFat = amount('trans-fat');
  d.cholesterol = times(amount('cholesterol'), 1000);
  d.sodium = times(amount('sodium'), 1000) ?? times(amount('salt'), 400);
  d.totalCarbohydrate = amount('carbohydrates');
  d.dietaryFiber = amount('fiber');
  d.totalSugars = amount('sugars');
  d.protein = amount('proteins');
  d.potassium = times(amount('potassium'), 1000);
  d.imageSourceURL = p.image_front_url ?? p.image_url ?? null;
  return d;
}

export async function lookupOpenFoodFacts(code) {
  const fields = 'product_name,brands,serving_size,serving_quantity,nutriments,image_front_url,image_url';
  for (const v of upcVariants(code)) {
    const json = await getJSON(`https://world.openfoodfacts.org/api/v2/product/${v}.json?fields=${fields}`);
    const d = draftFromOpenFoodFacts(json, code);
    if (d) return d;
  }
  return null;
}

// ---------- USDA FoodData Central ----------

const ID = {
  energy: [1008, 2047, 2048], protein: 1003, fat: 1004, carbs: 1005, fiber: 1079, sugars: [2000, 1063],
  sodium: 1093, potassium: 1092, cholesterol: 1253, saturated: 1258, trans: 1257,
};

export function usdaKey() {
  try { return localStorage.getItem('usdaAPIKey')?.trim() || 'DEMO_KEY'; } catch { return 'DEMO_KEY'; }
}

export async function usdaSearch(query) {
  const params = new URLSearchParams({
    query, pageSize: '25', dataType: 'Foundation,SR Legacy,Branded', api_key: usdaKey(),
  });
  const json = await getJSON(`https://api.nal.usda.gov/fdc/v1/foods/search?${params}`);
  return (json?.foods ?? []).map((f) => ({
    fdcId: f.fdcId,
    name: prettify(f.description),
    subtitle: [f.brandName ?? f.brandOwner, f.dataType].filter(Boolean).join(' · '),
    gtinUpc: f.gtinUpc ?? null,
  }));
}

export async function usdaDraft(fdcId) {
  const json = await getJSON(`https://api.nal.usda.gov/fdc/v1/food/${fdcId}?api_key=${encodeURIComponent(usdaKey())}`);
  if (!json) throw new Error('That food is no longer available.');
  return draftFromUSDA(json);
}

export async function usdaDraftForUPC(code) {
  const hit = (await usdaSearch(code)).find((f) => upcEquivalent(f.gtinUpc, code));
  if (!hit) return null;
  const d = await usdaDraft(hit.fdcId);
  d.upc = code;
  return d;
}

export function usdaServing(detail) {
  const size = num(detail.servingSize);
  const unit = String(detail.servingSizeUnit ?? '').toLowerCase();
  if (size > 0 && ['g', 'grm', 'ml', 'mlt'].includes(unit)) {
    const metric = `${formatPlain(size)} ${unit.startsWith('m') ? 'ml' : 'g'}`;
    const household = detail.householdServingFullText?.trim();
    return [household ? `${household} (${metric})` : metric, size];
  }
  const portion = (detail.foodPortions ?? []).find((p) => num(p.gramWeight) > 0);
  if (portion) {
    const words = [];
    if (num(portion.amount) > 0) words.push(formatPlain(num(portion.amount)));
    const u = portion.measureUnit?.name?.trim();
    if (u && u.toLowerCase() !== 'undetermined') words.push(u);
    const text = (portion.modifier ?? portion.portionDescription ?? '').trim();
    if (text && !/^\d+$/.test(text)) words.push(text);
    const label = words.length ? words.join(' ') : '1 serving';
    return [`${label} (${Math.round(portion.gramWeight)} g)`, portion.gramWeight];
  }
  return ['100 g', 100];
}

/** FoodData Central reports nutrients per 100 g; scale them to one serving. */
export function draftFromUSDA(detail) {
  const per100 = {};
  for (const e of detail.foodNutrients ?? []) {
    const id = e.nutrient?.id;
    const amount = num(e.amount);
    if (id == null || amount == null) continue;
    if (ID.energy.includes(id) && String(e.nutrient?.unitName).toUpperCase() === 'KJ') continue;
    per100[id] = amount;
  }
  const [servingDescription, grams] = usdaServing(detail);
  const f = grams / 100;
  const v = (id) => (per100[id] == null ? null : per100[id] * f);
  const first = (ids) => ids.map(v).find((x) => x != null) ?? null;

  const d = emptyDraft(prettify(detail.description));
  d.brand = prettify(detail.brandName ?? detail.brandOwner ?? '');
  d.upc = detail.gtinUpc ?? '';
  d.servingDescription = servingDescription;
  d.servingGrams = grams;
  d.calories = first(ID.energy);
  d.totalFat = v(ID.fat);
  d.saturatedFat = v(ID.saturated);
  d.transFat = v(ID.trans);
  d.cholesterol = v(ID.cholesterol);
  d.sodium = v(ID.sodium);
  d.totalCarbohydrate = v(ID.carbs);
  d.dietaryFiber = v(ID.fiber);
  d.totalSugars = first(ID.sugars);
  d.protein = v(ID.protein);
  d.potassium = v(ID.potassium);
  return d;
}
