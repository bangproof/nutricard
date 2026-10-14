// Pure logic shared by the app: matching, glycemic rules, label formatting, blood-pressure knowledge.
// Mirrors the Swift implementation in Nutricard/ so the iOS and web apps behave the same.

// ---------- Text matching ----------

export function tokens(text) {
  return String(text ?? '')
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[̀-ͯ]/g, '')
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

function containsPhrase(words, phrase) {
  if (!phrase.length || phrase.length > words.length) return false;
  outer: for (let i = 0; i <= words.length - phrase.length; i++) {
    for (let j = 0; j < phrase.length; j++) {
      if (words[i + j] !== phrase[j]) continue outer;
    }
    return true;
  }
  return false;
}

/** Length of the longest matching phrase, or null when nothing matches or an exclusion is present. */
export function matchScore(text, phrases, excluding = []) {
  const words = tokens(text);
  if (excluding.some((e) => containsPhrase(words, tokens(e)))) return null;
  let best = null;
  for (const phrase of phrases) {
    const t = tokens(phrase);
    if (containsPhrase(words, t)) {
      const s = t.join(' ').length;
      if (best === null || s > best) best = s;
    }
  }
  return best;
}

// ---------- Nutrition ----------

export const DailyValue = {
  totalFat: 78,
  saturatedFat: 20,
  cholesterol: 300,
  sodium: 2300,
  totalCarbohydrate: 275,
  dietaryFiber: 28,
  potassium: 4700,
};

export function percentDV(amount, dv) {
  if (amount == null) return null;
  return Math.round((amount / dv) * 100);
}

/** Label-style amount: one decimal below 10, whole numbers above. */
export function formatAmount(value) {
  if (value === 0) return '0';
  if (value < 10) {
    const r = Math.round(value * 10) / 10;
    if (r === 0) return '<0.1';
    return Number.isInteger(r) ? String(r) : r.toFixed(1);
  }
  return String(Math.round(value));
}

export function formatPlain(value) {
  if (value == null || Number.isNaN(value)) return '';
  const r = Math.round(value * 10) / 10;
  return String(r);
}

export const NUTRIENT_KEYS = [
  'calories', 'totalFat', 'saturatedFat', 'transFat', 'cholesterol', 'sodium',
  'totalCarbohydrate', 'dietaryFiber', 'totalSugars', 'protein', 'potassium',
];

export function scaleFacts(food, factor) {
  const out = {};
  for (const k of NUTRIENT_KEYS) out[k] = food[k] == null ? null : food[k] * factor;
  return out;
}

/** Carbohydrate that raises blood glucose (total carbohydrate minus fiber). */
export function availableCarbohydrate(facts) {
  return Math.max(0, (facts.totalCarbohydrate ?? 0) - (facts.dietaryFiber ?? 0));
}

// ---------- Glycemic index / load (University of Sydney definitions) ----------

export const Glycemic = {
  sourceName: 'University of Sydney Glycemic Index Database',
  sourceURL: 'https://glycemicindex.com',
  searchURL: 'https://glycemicindex.com/gi-search/',
  minimumTestableCarbohydrate: 5,
  load: (gi, availableCarbs) => (gi * availableCarbs) / 100,
  indexLevel: (gi) => (gi <= 55 ? 'low' : gi <= 69 ? 'medium' : 'high'),
  loadLevel: (gl) => {
    const r = Math.round(gl);
    return r <= 10 ? 'low' : r < 20 ? 'medium' : 'high';
  },
  formatLoad: (gl) => (gl > 0 && gl < 0.5 ? '<1' : String(Math.round(gl))),
};

export function giBestMatch(table, text) {
  let best = null;
  for (const entry of table) {
    const s = matchScore(text, entry.match, entry.exclude ?? []);
    if (s !== null && (!best || s > best.s)) best = { entry, s };
  }
  return best?.entry ?? null;
}

export function giCitation(entry) {
  return `${entry.food} — ${Glycemic.sourceName}`;
}

// ---------- Blood pressure knowledge base ----------

/** Foods at or above 20% of the sodium Daily Value per serving are never flagged automatically. */
export const MAX_SODIUM_FOR_BP = 460;

const COMMON_EXCLUSIONS = [
  'chips', 'chip', 'fried', 'cake', 'cookie', 'cookies', 'pie', 'candy', 'pudding',
  'salted', 'pickled', 'sweetened', 'frosted', 'sugar', 'syrup', 'cream', 'creamed', 'muffin', 'bread',
];

export const BP_FACTS = [
  { id: 'beet', match: ['beet', 'beets', 'beetroot', 'beetroots'],
    description: 'Beets are one of the richest sources of dietary nitrate. Your body converts nitrate into nitric oxide, which helps widen and relax blood vessels. Clinical trials show beetroot juice and whole beets can lower systolic blood pressure within hours, and the effect holds with regular intake.' },
  { id: 'spinach', match: ['spinach'],
    description: 'Spinach is rich in dietary nitrates that your body converts to nitric oxide, which helps widen and relax blood vessels. It also supplies potassium and magnesium, both of which support healthy blood pressure.' },
  { id: 'kale', match: ['kale'],
    description: 'Kale provides dietary nitrates, potassium and magnesium. Nitrates are converted to nitric oxide, which relaxes and widens blood vessels, while potassium helps your body excrete excess sodium.' },
  { id: 'collard', match: ['collard', 'collards', 'collard greens'],
    description: 'Collard greens are a nitrate-rich leafy green. Dietary nitrate is converted to nitric oxide, helping blood vessels relax and widen. Collards also add potassium, calcium and fiber.' },
  { id: 'arugula', match: ['arugula', 'rocket', 'roquette'],
    description: 'Arugula (rocket) is among the most nitrate-dense vegetables. Your body turns that nitrate into nitric oxide, which helps blood vessels relax and can lower blood pressure.' },
  { id: 'chard', match: ['chard', 'swiss chard'],
    description: 'Swiss chard provides dietary nitrates plus potassium and magnesium — a combination that helps blood vessels relax and offsets the effects of sodium.' },
  { id: 'celery', match: ['celery'],
    description: 'Celery contains dietary nitrates and potassium. Nitrates are converted to nitric oxide, which helps relax blood vessel walls.' },
  { id: 'banana', match: ['banana', 'bananas'], exclude: ['split'],
    description: 'Bananas are a good source of potassium, which helps your kidneys flush out excess sodium and eases tension in blood vessel walls. Potassium-rich diets are linked to lower blood pressure.' },
  { id: 'sweet-potato', match: ['sweet potato', 'sweet potatoes', 'potatoes sweet', 'potato sweet', 'yam', 'yams'], exclude: ['fries', 'casserole'],
    description: 'Sweet potatoes are rich in potassium and fiber. Potassium counterbalances sodium and helps relax blood vessel walls, supporting lower blood pressure.' },
  { id: 'pulses', match: ['lentil', 'lentils', 'chickpea', 'chickpeas', 'garbanzo', 'beans kidney', 'kidney beans', 'black beans', 'beans black', 'pinto beans', 'beans pinto', 'navy beans', 'white beans'], exclude: ['baked beans', 'refried', 'hummus'],
    description: 'Pulses such as lentils, chickpeas and beans deliver potassium, magnesium and fiber. Clinical trials show that eating pulses regularly modestly lowers blood pressure, and they are a staple of the DASH eating plan.' },
  { id: 'oats', match: ['oat', 'oats', 'oatmeal', 'oat porridge', 'porridge oats', 'rolled oats', 'steel cut oats'], exclude: ['bar', 'granola', 'instant flavored', 'milk'],
    description: 'Whole-grain oats contain beta-glucan, a soluble fiber linked to modest reductions in blood pressure, and are a core part of the DASH eating plan.' },
  { id: 'berries', match: ['blueberry', 'blueberries', 'strawberries', 'strawberry', 'raspberries', 'blackberries', 'berries'], exclude: ['jam', 'jelly', 'preserves', 'yogurt'],
    description: 'Blueberries and other berries are rich in anthocyanins, flavonoids that support nitric oxide production and help keep arteries flexible. Regular intake is associated with lower blood pressure.' },
  { id: 'oily-fish', match: ['salmon', 'mackerel', 'sardine', 'sardines', 'herring', 'trout'], exclude: ['smoked', 'lox'],
    description: 'Salmon and other oily fish provide the omega-3 fats EPA and DHA, which can lower blood pressure, reduce inflammation and help keep blood vessels flexible.' },
  { id: 'pistachio', match: ['pistachio', 'pistachios'],
    description: 'Pistachios provide potassium, magnesium and unsaturated fats. Clinical trials suggest eating unsalted pistachios regularly can lower blood pressure.' },
  { id: 'garlic', match: ['garlic'], exclude: ['salt', 'butter'],
    description: 'Garlic contains allicin and other sulfur compounds that boost nitric oxide production and help relax blood vessels. Studies show modest blood pressure reductions, especially in people with hypertension.' },
  { id: 'low-fat-dairy', match: ['skim milk', 'milk skim', 'nonfat milk', 'milk nonfat', 'low fat milk', 'lowfat milk', 'milk lowfat', 'plain yogurt', 'yogurt plain', 'greek yogurt', 'yogurt greek'], exclude: ['chocolate', 'flavored', 'vanilla', 'strawberry'],
    description: 'Low-fat dairy supplies calcium, potassium and magnesium and is part of the DASH eating plan, which is proven to lower blood pressure.' },
  { id: 'pomegranate', match: ['pomegranate', 'pomegranates'],
    description: 'Pomegranate is rich in polyphenol antioxidants. Trials of pomegranate juice show it can reduce systolic blood pressure.' },
];

export function bpFact(id) {
  return BP_FACTS.find((f) => f.id === id) ?? null;
}

export function bpMatch(text, sodiumPerServing = null) {
  if (sodiumPerServing != null && sodiumPerServing >= MAX_SODIUM_FOR_BP) return null;
  let best = null;
  for (const fact of BP_FACTS) {
    const s = matchScore(text, fact.match, [...(fact.exclude ?? []), ...COMMON_EXCLUSIONS]);
    if (s !== null && (!best || s > best.s)) best = { fact, s };
  }
  return best?.fact ?? null;
}

// ---------- Foods ----------

export function foodFromSeed(seed) {
  const fact = seed.bloodPressureID ? bpFact(seed.bloodPressureID) : null;
  const food = {
    id: 'seed-' + tokens(seed.name).join('-'),
    name: seed.name,
    brand: null,
    upc: null,
    emoji: seed.emoji,
    servingDescription: seed.servingDescription,
    servingGrams: seed.servingGrams ?? null,
    glycemicIndex: seed.glycemicIndex ?? null,
    glycemicNote: seed.glycemicNote ?? null,
    lowersBloodPressure: !!fact,
    bloodPressureNote: fact?.description ?? null,
    image: null,
    imageSourceURL: null,
    imageSearchTerm: seed.wikiTitle ?? null,
    isSeed: true,
    dateAdded: Date.now(),
  };
  for (const k of NUTRIENT_KEYS) food[k] = seed[k] ?? null;
  return food;
}

export function emptyDraft(name = '') {
  const d = {
    id: null, name, brand: '', upc: '', emoji: '🍽️', servingDescription: '1 serving', servingGrams: null,
    glycemicIndex: null, glycemicNote: '', lowersBloodPressure: false, bloodPressureNote: '',
    image: null, imageSourceURL: null, imageSearchTerm: null,
  };
  for (const k of NUTRIENT_KEYS) d[k] = null;
  return d;
}

/** Fills GI and blood-pressure fields from the references when they are still empty. */
export function applySuggestions(draft, giTable) {
  const text = `${draft.name} ${draft.brand ?? ''}`;
  if (draft.glycemicIndex == null) {
    const entry = giBestMatch(giTable, text);
    if (entry) {
      draft.glycemicIndex = entry.gi;
      draft.glycemicNote = giCitation(entry);
    }
  }
  if (!draft.lowersBloodPressure) {
    const fact = bpMatch(text, draft.sodium);
    if (fact) {
      draft.lowersBloodPressure = true;
      draft.bloodPressureNote = fact.description;
    }
  }
  return draft;
}

// ---------- UPC ----------

export function upcEquivalent(a, b) {
  if (!a || !b) return false;
  const strip = (s) => String(s).replace(/\D/g, '').replace(/^0+/, '');
  const x = strip(a);
  return x.length > 0 && x === strip(b);
}

export function upcVariants(code) {
  const d = String(code).replace(/\D/g, '');
  const v = [d];
  if (d.length === 13 && d.startsWith('0')) v.push(d.slice(1));
  if (d.length === 12) v.push('0' + d);
  return v;
}

export function prettify(text) {
  const t = String(text ?? '').trim();
  if (t !== t.toUpperCase() || !/[A-Za-z]/.test(t)) return t;
  const lower = t.toLowerCase();
  return lower.charAt(0).toUpperCase() + lower.slice(1);
}
