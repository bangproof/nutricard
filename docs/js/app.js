import {
  Glycemic, DailyValue, percentDV, formatAmount, formatPlain, scaleFacts, availableCarbohydrate,
  foodFromSeed, emptyDraft, applySuggestions, giBestMatch, giCitation, bpMatch, upcEquivalent,
  NUTRIENT_KEYS, MAX_SODIUM_FOR_BP,
} from './core.js';
import { lookupOpenFoodFacts, usdaDraftForUPC, usdaSearch, usdaDraft } from './api.js';
import { findFoodImage, photoFileToWhite } from './images.js';
import { startScanner } from './scanner.js';
import { store } from './store.js';

const SEED_VERSION = '1';

const state = {
  foods: [],
  giTable: [],
  query: '',
  currentId: null,
  servings: new Map(),
};

const $ = (sel, root = document) => root.querySelector(sel);
const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const newId = () => (crypto.randomUUID ? crypto.randomUUID() : `id-${Date.now()}-${Math.random().toString(16).slice(2)}`);

const deck = $('#deck');
const counter = $('#counter');

// ---------------------------------------------------------------------------
// Boot

async function boot() {
  const [seeds, gi] = await Promise.all([
    fetch('data/SeedFoods.json').then((r) => r.json()),
    fetch('data/GIReference.json').then((r) => r.json()),
  ]);
  state.giTable = gi;

  let foods = [];
  try {
    foods = await store.all();
    if (localStorage.getItem('seedVersion') !== SEED_VERSION) {
      const have = new Set(foods.map((f) => f.id));
      const fresh = seeds.map(foodFromSeed).filter((f) => !have.has(f.id));
      await store.putMany(fresh);
      foods = foods.concat(fresh);
      localStorage.setItem('seedVersion', SEED_VERSION);
    }
  } catch {
    // Private browsing or storage blocked: run from the bundled foods without saving.
    foods = seeds.map(foodFromSeed);
    toast('Storage is unavailable, so foods you add won’t be saved.');
  }
  setFoods(foods);
  state.currentId = sortedFoods()[0]?.id ?? null;
  render();
  backfillImages();
}

function setFoods(foods) {
  state.foods = foods;
}

function sortedFoods() {
  return [...state.foods].sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
}

function visibleFoods() {
  const q = state.query.trim().toLowerCase();
  const list = sortedFoods();
  if (!q) return list;
  return list.filter((f) =>
    f.name.toLowerCase().includes(q) || (f.brand ?? '').toLowerCase().includes(q) || upcEquivalent(f.upc, q));
}

// ---------------------------------------------------------------------------
// Card deck

function render() {
  const list = visibleFoods();
  if (!list.some((f) => f.id === state.currentId)) state.currentId = list[0]?.id ?? null;

  $('#pager').hidden = list.length === 0;
  $('#menuBtn').disabled = list.length === 0;

  if (state.foods.length === 0) {
    deck.innerHTML = emptyState('No foods yet', 'Scan a UPC barcode or enter a food name to build your database.', '');
    return;
  }
  if (list.length === 0) {
    deck.innerHTML = emptyState(`No results for “${esc(state.query)}”`, 'Add it to your database.', state.query);
    return;
  }
  deck.innerHTML = list.map((f) => `<section class="slide" data-id="${esc(f.id)}">${cardHTML(f)}</section>`).join('');
  scrollToCurrent(false);
  updateCounter();
}

function emptyState(title, text, query) {
  return `<div class="empty">
    <div class="empty-icon">🍽️</div>
    <h2>${title}</h2>
    <p>${text}</p>
    <button class="btn primary" data-act="add-name" data-query="${esc(query)}">${query ? `Add “${esc(query)}”` : 'Enter a Food Name'}</button>
    <button class="btn" data-act="add-scan">Scan UPC Barcode</button>
  </div>`;
}

function cardHTML(food) {
  const servings = state.servings.get(food.id) ?? 1;
  const facts = scaleFacts(food, servings);
  const avail = availableCarbohydrate(facts);
  const heart = food.lowersBloodPressure
    ? '<span class="heart" role="img" aria-label="May help lower blood pressure">♥</span>' : '';
  return `<article class="card">
    <div class="photo" data-photo="${esc(food.id)}">${photoHTML(food)}</div>
    <header class="food-head">
      <h2>${esc(food.name)} ${heart}</h2>
      ${food.brand ? `<div class="sub">${esc(food.brand)}</div>` : ''}
      ${food.upc ? `<div class="sub mono">▮▯▮ ${esc(food.upc)}</div>` : ''}
    </header>
    <div class="serving">
      <div>
        <b>${servings === 1 ? '1 serving' : `${formatPlain(servings)} servings`}</b>
        <small>1 serving = ${esc(food.servingDescription)}</small>
      </div>
      <div class="stepper">
        ${servings !== 1 ? `<button class="link-btn" data-act="reset" data-id="${esc(food.id)}">Reset</button>` : ''}
        <button data-act="minus" data-id="${esc(food.id)}" aria-label="Fewer servings" ${servings <= 0.5 ? 'disabled' : ''}>−</button>
        <button data-act="plus" data-id="${esc(food.id)}" aria-label="More servings" ${servings >= 10 ? 'disabled' : ''}>+</button>
      </div>
    </div>
    ${labelHTML(food, facts, servings)}
    ${glycemicHTML(food, avail, servings)}
    ${food.lowersBloodPressure ? bpHTML(food) : ''}
  </article>`;
}

function photoHTML(food) {
  if (food.image) return `<img src="${food.image}" alt="${esc(food.name)}">`;
  const spinner = food.imageFailed ? '' : '<i class="spinner"></i>';
  return `<div class="placeholder"><span>${esc(food.emoji || '🍽️')}</span>${spinner}</div>`;
}

function row(name, amount, unit, { dv, bold, indent, last } = {}) {
  const pct = dv ? percentDV(amount, dv) : null;
  return `<div class="row${indent ? ' indent' : ''}${last ? ' last' : ''}">
    <span>${bold ? `<b>${name}</b>` : name} ${amount == null ? '—' : formatAmount(amount) + unit}</span>
    <b>${pct == null ? '' : pct + '%'}</b>
  </div>`;
}

function labelHTML(food, f, servings) {
  const size = servings === 1 ? food.servingDescription : `${formatPlain(servings)} × ${food.servingDescription}`;
  return `<div class="label">
    <div class="label-title">Nutrition Facts</div>
    <div class="rule r1"></div>
    <div class="size"><b>Serving size</b><b>${esc(size)}</b></div>
    <div class="rule r9"></div>
    <div class="aps">${servings === 1 ? 'Amount per serving' : `Amount for ${formatPlain(servings)} servings`}</div>
    <div class="cal"><span>Calories</span><span>${Math.round(f.calories ?? 0)}</span></div>
    <div class="rule r5"></div>
    <div class="dvh">% Daily Value*</div>
    ${row('Total Fat', f.totalFat, 'g', { dv: DailyValue.totalFat, bold: true })}
    ${row('Saturated Fat', f.saturatedFat, 'g', { dv: DailyValue.saturatedFat, indent: true })}
    ${row('Trans Fat', f.transFat, 'g', { indent: true })}
    ${row('Cholesterol', f.cholesterol, 'mg', { dv: DailyValue.cholesterol, bold: true })}
    ${row('Sodium', f.sodium, 'mg', { dv: DailyValue.sodium, bold: true })}
    ${row('Total Carbohydrate', f.totalCarbohydrate, 'g', { dv: DailyValue.totalCarbohydrate, bold: true })}
    ${row('Dietary Fiber', f.dietaryFiber, 'g', { dv: DailyValue.dietaryFiber, indent: true })}
    ${row('Total Sugars', f.totalSugars, 'g', { indent: true })}
    ${row('Protein', f.protein, 'g', { bold: true, last: true })}
    <div class="rule r9"></div>
    ${row('Potassium', f.potassium, 'mg', { dv: DailyValue.potassium, last: true })}
    <div class="rule r5"></div>
    <p class="fine">* The % Daily Value tells you how much a nutrient in a serving of food contributes to a daily diet. 2,000 calories a day is used for general nutrition advice.</p>
  </div>`;
}

function tile(title, value, level, caption) {
  const pill = level ? `<span class="pill ${level}">${level[0].toUpperCase() + level.slice(1)}</span>` : '';
  return `<div class="tile"><div class="k">${title}</div><div class="v"><span>${value}</span>${pill}</div><small>${caption}</small></div>`;
}

function glycemicHTML(food, avail, servings) {
  let body;
  const gi = food.glycemicIndex;
  if (gi != null) {
    const gl = Glycemic.load(gi, avail);
    body = `<div class="tiles">
        ${tile('Glycemic Index', gi, Glycemic.indexLevel(gi), 'Glucose = 100')}
        ${tile('Glycemic Load', Glycemic.formatLoad(gl), Glycemic.loadLevel(gl), servings === 1 ? 'Per 1 serving' : `Per ${formatPlain(servings)} servings`)}
      </div>
      <p class="cap">GL = GI × ${formatAmount(avail)} g available carbohydrate ÷ 100</p>`;
  } else if (avail < Glycemic.minimumTestableCarbohydrate) {
    body = `<div class="tiles">
        ${tile('Glycemic Index', 'N/A', null, 'Too little carbohydrate')}
        ${tile('Glycemic Load', '≈ 0', 'low', 'Negligible effect')}
      </div>`;
  } else {
    body = '<p class="muted">No GI value recorded for this food yet. Look it up in the University of Sydney GI Database and add it with Edit.</p>';
  }
  return `<section class="gi">
    <h3>Glycemic Index &amp; Load</h3>
    ${body}
    ${food.glycemicNote ? `<p class="cap">${esc(food.glycemicNote)}</p>` : ''}
    <a class="src" href="${gi == null ? Glycemic.searchURL : Glycemic.sourceURL}" target="_blank" rel="noopener">🏛 Source: ${Glycemic.sourceName} — glycemicindex.com</a>
    <p class="tiny">GI: low ≤ 55 · medium 56–69 · high ≥ 70. GL: low ≤ 10 · medium 11–19 · high ≥ 20.</p>
  </section>`;
}

function bpHTML(food) {
  return `<section class="bp">
    <h3><span class="heart">♥</span> May help lower blood pressure</h3>
    ${food.bloodPressureNote ? `<p>${esc(food.bloodPressureNote)}</p>` : ''}
    <p class="tiny">General nutrition information, not medical advice. Talk to your doctor about managing blood pressure.</p>
  </section>`;
}

function rerenderCard(id) {
  const slide = deck.querySelector(`.slide[data-id="${CSS.escape(id)}"]`);
  const food = state.foods.find((f) => f.id === id);
  if (!slide || !food) return;
  const scroller = slide.querySelector('.card');
  const top = scroller?.scrollTop ?? 0;
  slide.innerHTML = cardHTML(food);
  const card = slide.querySelector('.card');
  if (card) card.scrollTop = top;
}

function currentIndex() {
  return Math.max(0, visibleFoods().findIndex((f) => f.id === state.currentId));
}

function updateCounter() {
  const list = visibleFoods();
  const i = currentIndex();
  counter.textContent = list.length ? `${i + 1} of ${list.length}` : '';
  $('#prev').disabled = i <= 0;
  $('#next').disabled = i >= list.length - 1;
}

function scrollToCurrent(smooth) {
  const i = currentIndex();
  deck.scrollTo({ left: i * deck.clientWidth, behavior: smooth ? 'smooth' : 'auto' });
}

function go(offset) {
  const list = visibleFoods();
  const i = currentIndex() + offset;
  if (i < 0 || i >= list.length) return;
  changeCurrent(list[i].id);
  scrollToCurrent(true);
}

function changeCurrent(id) {
  if (id === state.currentId) return;
  const previous = state.currentId;
  state.currentId = id;
  // Cards always return to 1 serving when you move away.
  if (previous && state.servings.has(previous)) {
    state.servings.delete(previous);
    rerenderCard(previous);
  }
  updateCounter();
}

let scrollFrame = 0;
deck.addEventListener('scroll', () => {
  cancelAnimationFrame(scrollFrame);
  scrollFrame = requestAnimationFrame(() => {
    const list = visibleFoods();
    if (!list.length || !deck.clientWidth) return;
    const i = Math.round(deck.scrollLeft / deck.clientWidth);
    if (list[i]) changeCurrent(list[i].id);
  });
}, { passive: true });

window.addEventListener('resize', () => scrollToCurrent(false));

deck.addEventListener('click', (e) => {
  const btn = e.target.closest('[data-act]');
  if (!btn) return;
  const id = btn.dataset.id;
  const s = state.servings.get(id) ?? 1;
  switch (btn.dataset.act) {
    case 'minus': state.servings.set(id, Math.max(0.5, s - 0.5)); rerenderCard(id); break;
    case 'plus': state.servings.set(id, Math.min(10, s + 0.5)); rerenderCard(id); break;
    case 'reset': state.servings.delete(id); rerenderCard(id); break;
    case 'add-name': openNameSearch(btn.dataset.query ?? ''); break;
    case 'add-scan': openScan(); break;
  }
});

$('#prev').addEventListener('click', () => go(-1));
$('#next').addEventListener('click', () => go(1));
document.addEventListener('keydown', (e) => {
  if (!$('#sheet').hidden || e.target.matches('input, textarea')) return;
  if (e.key === 'ArrowLeft') go(-1);
  if (e.key === 'ArrowRight') go(1);
});

$('#search').addEventListener('input', (e) => {
  state.query = e.target.value;
  render();
});

// ---------------------------------------------------------------------------
// Menus

function actionSheet(title, actions) {
  const el = $('#actions');
  el.innerHTML = `<div class="action-panel" role="menu">
      ${title ? `<div class="action-title">${esc(title)}</div>` : ''}
      ${actions.map((a, i) => `<button role="menuitem" class="${a.destructive ? 'destructive' : ''}" data-i="${i}">${a.label}</button>`).join('')}
    </div>
    <div class="action-panel"><button class="cancel" data-i="-1">Cancel</button></div>`;
  el.hidden = false;
  el.onclick = (e) => {
    const b = e.target.closest('button');
    if (!b && e.target !== el) return;
    el.hidden = true;
    const i = b ? Number(b.dataset.i) : -1;
    if (i >= 0) actions[i].run();
  };
}

$('#addBtn').addEventListener('click', () =>
  actionSheet('Add a food', [
    { label: '▦ Scan UPC Barcode', run: openScan },
    { label: '⌕ Enter Food Name', run: () => openNameSearch(state.query.trim()) },
  ]));

$('#menuBtn').addEventListener('click', () => {
  const food = state.foods.find((f) => f.id === state.currentId);
  if (!food) return;
  actionSheet(food.name, [
    { label: '✎ Edit', run: () => openEditor({ ...food }, { existing: food }) },
    { label: '⟳ Find a New Photo', run: () => refreshPhoto(food) },
    { label: 'Delete', destructive: true, run: () => deleteFood(food) },
  ]);
});

async function deleteFood(food) {
  if (!confirm(`Delete ${food.name}?`)) return;
  const list = visibleFoods();
  const i = list.findIndex((f) => f.id === food.id);
  const neighbor = list[i + 1] ?? list[i - 1];
  state.foods = state.foods.filter((f) => f.id !== food.id);
  state.currentId = neighbor?.id ?? null;
  try { await store.remove(food.id); } catch { /* storage unavailable */ }
  render();
}

// ---------------------------------------------------------------------------
// Sheets

const sheet = $('#sheet');
let sheetCleanup = null;

function openSheet({ title, left = 'Cancel', onLeft = closeSheet, right = null, onRight = null, body, cleanup = null }) {
  sheetCleanup?.();
  sheetCleanup = cleanup;
  sheet.innerHTML = `<div class="sheet-bar">
      <button class="bar-btn" id="sheetLeft">${left}</button>
      <h2>${esc(title)}</h2>
      ${right ? `<button class="bar-btn strong" id="sheetRight">${right}</button>` : '<span class="bar-btn"></span>'}
    </div>
    <div class="sheet-body"></div>`;
  const content = $('.sheet-body', sheet);
  if (typeof body === 'string') content.innerHTML = body;
  else content.appendChild(body);
  $('#sheetLeft', sheet).onclick = onLeft;
  if (right) $('#sheetRight', sheet).onclick = onRight;
  sheet.hidden = false;
  document.body.classList.add('sheet-open');
  return content;
}

function closeSheet() {
  sheetCleanup?.();
  sheetCleanup = null;
  sheet.hidden = true;
  sheet.innerHTML = '';
  document.body.classList.remove('sheet-open');
}

function finish(food) {
  closeSheet();
  if (!food) return;
  state.query = '';
  $('#search').value = '';
  state.currentId = food.id;
  render();
}

// ----- Scan -----

function openScan() {
  let stop = null;
  let busy = false;
  let active = true;
  const body = document.createElement('div');
  body.className = 'scan';
  body.innerHTML = `<div class="viewfinder"><video autoplay playsinline muted></video><div class="aim"></div></div>
    <p class="scan-status">Starting camera…</p>
    <form class="manual">
      <input type="text" inputmode="numeric" autocomplete="off" placeholder="Or type the UPC" aria-label="UPC">
      <button class="btn primary" type="submit">Look Up</button>
    </form>`;
  openSheet({
    title: 'Scan UPC',
    body,
    cleanup: () => {
      active = false;
      stop?.();
      stop = null;
    },
  });

  const status = $('.scan-status', body);
  const setStatus = (text, error = false) => {
    status.textContent = text;
    status.classList.toggle('error', error);
  };

  const lookUp = async (raw) => {
    const code = String(raw).replace(/\D/g, '');
    if (busy || code.length < 6) return;
    const existing = state.foods.find((f) => upcEquivalent(f.upc, code));
    if (existing) {
      finish(existing);
      return;
    }
    busy = true;
    navigator.vibrate?.(60);
    setStatus(`Looking up ${code}…`);
    try {
      let draft = await lookupOpenFoodFacts(code);
      let notice = 'Found in Open Food Facts. Check the values against the package label.';
      if (!draft) {
        draft = await usdaDraftForUPC(code).catch(() => null);
        notice = 'Found in USDA FoodData Central. Check the values against the package label.';
      }
      if (!draft) {
        draft = emptyDraft();
        draft.upc = code;
        notice = `UPC ${code} wasn’t found online. Enter the details from the package label.`;
      }
      openEditor(draft, { notice, isNew: true });
    } catch (err) {
      setStatus(`Lookup failed: ${err.message}`, true);
      busy = false;
    }
  };

  $('.manual', body).addEventListener('submit', (e) => {
    e.preventDefault();
    lookUp($('input', e.target).value);
  });

  startScanner($('video', body), lookUp)
    .then((s) => {
      if (!active) { s(); return; }
      stop = s;
      setStatus('Point the camera at a barcode');
    })
    .catch((err) => {
      setStatus(err?.name === 'NotAllowedError'
        ? 'Camera access was denied. Allow it in Settings, or type the UPC below.'
        : `${err?.message || 'Camera unavailable.'} Type the UPC below.`, true);
      $('.viewfinder', body).classList.add('off');
    });
}

// ----- Name search -----

function openNameSearch(initialQuery) {
  const body = document.createElement('div');
  body.className = 'name-search';
  body.innerHTML = `<form class="searchrow">
      <input type="search" enterkeyhint="search" placeholder="Food name, e.g. beets" value="${esc(initialQuery)}" aria-label="Food name">
      <button class="btn primary" type="submit">Search</button>
    </form>
    <button class="list-btn" data-manual>✎ <span></span></button>
    <p class="error" hidden></p>
    <h4>USDA FoodData Central</h4>
    <div class="results"></div>
    <details class="keybox">
      <summary>USDA API key</summary>
      <input type="text" autocomplete="off" autocapitalize="off" spellcheck="false" placeholder="Personal API key (optional)">
      <p class="tiny">Without a key the shared DEMO_KEY is used, which allows only a few searches per hour.
      <a href="https://fdc.nal.usda.gov/api-key-signup" target="_blank" rel="noopener">Get a free key</a>.</p>
    </details>`;
  openSheet({ title: 'Add by Name', body });

  const input = $('input[type=search]', body);
  const manual = $('[data-manual]', body);
  const results = $('.results', body);
  const error = $('.error', body);
  const keyInput = $('.keybox input', body);
  try { keyInput.value = localStorage.getItem('usdaAPIKey') ?? ''; } catch { /* ignore */ }
  keyInput.addEventListener('input', () => {
    try { localStorage.setItem('usdaAPIKey', keyInput.value.trim()); } catch { /* ignore */ }
  });

  const updateManual = () => {
    const q = input.value.trim();
    $('span', manual).textContent = q ? `Enter “${q}” manually` : 'Enter a food manually';
  };
  updateManual();
  input.addEventListener('input', updateManual);
  manual.onclick = () => openEditor(emptyDraft(input.value.trim()), { isNew: true, back: () => openNameSearch(input.value) });

  const search = async () => {
    const q = input.value.trim();
    if (!q) return;
    input.blur();
    error.hidden = true;
    results.innerHTML = '<div class="loading"><i class="spinner"></i> Searching…</div>';
    try {
      const foods = await usdaSearch(q);
      results.innerHTML = foods.length
        ? foods.map((f) => `<button class="result" data-fdc="${f.fdcId}">
            <span><b>${esc(f.name)}</b>${f.subtitle ? `<small>${esc(f.subtitle)}</small>` : ''}</span><i>›</i></button>`).join('')
        : '<p class="muted">No matches. Try a simpler name, or enter it manually.</p>';
    } catch (err) {
      results.innerHTML = '';
      error.textContent = `Search failed: ${err.message}`;
      error.hidden = false;
    }
  };

  $('.searchrow', body).addEventListener('submit', (e) => {
    e.preventDefault();
    search();
  });

  results.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-fdc]');
    if (!b || results.classList.contains('busy')) return;
    results.classList.add('busy');
    b.querySelector('i').outerHTML = '<i class="spinner"></i>';
    try {
      const draft = await usdaDraft(Number(b.dataset.fdc));
      const q = input.value;
      openEditor(draft, { isNew: true, back: () => openNameSearch(q) });
    } catch (err) {
      error.textContent = `Couldn’t load that food: ${err.message}`;
      error.hidden = false;
      results.classList.remove('busy');
      const spin = b.querySelector('.spinner');
      if (spin) spin.outerHTML = '<i>›</i>';
    }
  });

  if (initialQuery.trim()) search();
  else setTimeout(() => input.focus(), 250);
}

// ----- Editor -----

const FIELDS = [
  ['calories', 'Calories', 'kcal'], ['totalFat', 'Total fat', 'g'], ['saturatedFat', 'Saturated fat', 'g'],
  ['transFat', 'Trans fat', 'g'], ['cholesterol', 'Cholesterol', 'mg'], ['sodium', 'Sodium', 'mg'],
  ['totalCarbohydrate', 'Total carbohydrate', 'g'], ['dietaryFiber', 'Dietary fiber', 'g'],
  ['totalSugars', 'Total sugars', 'g'], ['protein', 'Protein', 'g'], ['potassium', 'Potassium', 'mg'],
];

const numberInput = (field, value) =>
  `<input class="num" data-num="${field}" inputmode="decimal" autocomplete="off" placeholder="—" value="${value == null ? '' : esc(formatPlain(value))}">`;

function openEditor(draftIn, { existing = null, notice = null, isNew = false, back = null } = {}) {
  const draft = { ...emptyDraft(), ...draftIn };
  if (isNew) applySuggestions(draft, state.giTable);
  let image = draft.image ?? null;
  let processing = false;

  const body = document.createElement('form');
  body.className = 'editor';
  body.noValidate = true;
  body.innerHTML = `
    ${notice ? `<div class="notice">ⓘ ${esc(notice)}</div>` : ''}
    <h4>Photo</h4>
    <div class="group">
      <div class="ed-photo"></div>
      <div class="photo-btns">
        <label class="chip">📷 Camera<input type="file" accept="image/*" capture="environment" hidden></label>
        <label class="chip">🖼 Library<input type="file" accept="image/*" hidden></label>
        <button type="button" class="chip" data-find>⌕ Find online</button>
      </div>
    </div>
    <p class="foot photo-msg">Photos are cleaned up and placed on a white background automatically.</p>

    <h4>Food</h4>
    <div class="group">
      <input class="text" data-text="name" placeholder="Name (required)" autocapitalize="words" value="${esc(draft.name)}">
      <input class="text" data-text="brand" placeholder="Brand (optional)" value="${esc(draft.brand ?? '')}">
      <input class="text" data-text="upc" placeholder="UPC (optional)" inputmode="numeric" value="${esc(draft.upc ?? '')}">
    </div>

    <h4>Serving</h4>
    <div class="group">
      <input class="text" data-text="servingDescription" placeholder="Serving size, e.g. 1 cup (240 g)" value="${esc(draft.servingDescription)}">
      <label class="field"><span>Serving weight</span>${numberInput('servingGrams', draft.servingGrams)}<em>g</em></label>
    </div>
    <p class="foot">Cards always open at 1 serving. Enter all nutrition values below for exactly 1 serving.</p>

    <h4>Nutrition per 1 serving</h4>
    <div class="group">
      ${FIELDS.map(([k, label, unit]) => `<label class="field"><span>${label}</span>${numberInput(k, draft[k])}<em>${unit}</em></label>`).join('')}
    </div>

    <h4>Glycemic index</h4>
    <div class="group">
      <label class="field"><span>Glycemic index</span>${numberInput('glycemicIndex', draft.glycemicIndex)}<em></em></label>
      <div class="field gl-out" hidden></div>
      <button type="button" class="list-btn gi-suggest" hidden></button>
      <textarea class="text" data-text="glycemicNote" rows="2" placeholder="Tested food / source note">${esc(draft.glycemicNote ?? '')}</textarea>
      <a class="list-btn" href="${Glycemic.searchURL}" target="_blank" rel="noopener">🧭 Search the University of Sydney GI Database</a>
    </div>
    <p class="foot">Glycemic load is calculated as GI × available carbohydrate (carbohydrate − fiber) per serving ÷ 100. Leave GI empty for foods with little or no carbohydrate.</p>

    <h4>Blood pressure</h4>
    <div class="group">
      <label class="field toggle"><span><span class="heart">♥</span> May help lower blood pressure</span>
        <input type="checkbox" data-bp ${draft.lowersBloodPressure ? 'checked' : ''}></label>
      <textarea class="text bp-note" data-text="bloodPressureNote" rows="4" placeholder="Why? (shown at the bottom of the card)">${esc(draft.bloodPressureNote ?? '')}</textarea>
      <button type="button" class="list-btn bp-suggest" hidden>✨ Suggested: this food is known to support healthy blood pressure</button>
    </div>
    <p class="foot">Foods with ${MAX_SODIUM_FOR_BP} mg of sodium or more per serving aren’t suggested automatically.</p>`;

  const content = openSheet({
    title: existing ? 'Edit Food' : 'New Food',
    left: back ? '‹ Back' : 'Cancel',
    onLeft: back ?? closeSheet,
    right: 'Save',
    onRight: save,
    body,
  });

  const saveBtn = $('#sheetRight', sheet);
  const photoBox = $('.ed-photo', content);
  const photoMsg = $('.photo-msg', content);

  const showPhoto = () => {
    photoBox.innerHTML = image
      ? `<img src="${image}" alt="">`
      : `<span class="big-emoji">${esc(draft.emoji || '🍽️')}</span>`;
    if (processing) photoBox.insertAdjacentHTML('beforeend', '<div class="busy-overlay"><i class="spinner"></i> Preparing photo…</div>');
  };

  const refresh = () => {
    saveBtn.disabled = !draft.name.trim() || processing;
    // Glycemic load preview + suggestion
    const glOut = $('.gl-out', content);
    if (draft.glycemicIndex != null) {
      const gl = Glycemic.load(draft.glycemicIndex, availableCarbohydrate(draft));
      glOut.innerHTML = `<span>Glycemic load (1 serving)</span><b>${Glycemic.formatLoad(gl)} · ${Glycemic.loadLevel(gl)}</b>`;
      glOut.hidden = false;
    } else {
      glOut.hidden = true;
    }
    const text = `${draft.name} ${draft.brand ?? ''}`;
    const entry = giBestMatch(state.giTable, text);
    const giBtn = $('.gi-suggest', content);
    giBtn.hidden = !entry || entry.gi === draft.glycemicIndex;
    if (entry) {
      giBtn.textContent = `✨ Use GI ${entry.gi} — ${entry.food}`;
      giBtn.onclick = () => {
        draft.glycemicIndex = entry.gi;
        draft.glycemicNote = giCitation(entry);
        $('[data-num=glycemicIndex]', content).value = entry.gi;
        $('[data-text=glycemicNote]', content).value = draft.glycemicNote;
        refresh();
      };
    }
    $('.bp-note', content).hidden = !draft.lowersBloodPressure;
    const fact = draft.lowersBloodPressure ? null : bpMatch(text, draft.sodium);
    const bpBtn = $('.bp-suggest', content);
    bpBtn.hidden = !fact;
    bpBtn.onclick = () => {
      draft.lowersBloodPressure = true;
      draft.bloodPressureNote = fact.description;
      $('[data-bp]', content).checked = true;
      $('.bp-note', content).value = fact.description;
      refresh();
    };
  };

  content.addEventListener('input', (e) => {
    const t = e.target;
    if (t.dataset.text) draft[t.dataset.text] = t.value;
    if (t.dataset.num) {
      const v = parseFloat(t.value.replace(',', '.'));
      draft[t.dataset.num] = Number.isFinite(v) ? (t.dataset.num === 'glycemicIndex' ? Math.round(v) : v) : null;
    }
    if (t.matches('[data-bp]')) draft.lowersBloodPressure = t.checked;
    refresh();
  });
  content.addEventListener('submit', (e) => e.preventDefault());

  const setProcessing = (on) => {
    processing = on;
    showPhoto();
    refresh();
  };

  content.querySelectorAll('input[type=file]').forEach((input) => {
    input.addEventListener('change', async () => {
      const file = input.files?.[0];
      input.value = '';
      if (!file) return;
      setProcessing(true);
      try {
        image = await photoFileToWhite(file);
        draft.imageSourceURL = null;
        photoMsg.textContent = 'Photos are cleaned up and placed on a white background automatically.';
      } catch {
        photoMsg.textContent = 'That photo couldn’t be read. Try another one.';
      }
      setProcessing(false);
    });
  });

  const findOnline = async () => {
    if (!draft.name.trim() && !draft.imageSourceURL) return;
    setProcessing(true);
    const found = await findFoodImage({ name: draft.name, imageSourceURL: draft.imageSourceURL, imageSearchTerm: existing?.imageSearchTerm });
    if (found) {
      image = found;
      photoMsg.textContent = 'Photos are cleaned up and placed on a white background automatically.';
    } else {
      photoMsg.textContent = 'No photo found online. Take a photo or choose one from your library.';
    }
    setProcessing(false);
  };
  $('[data-find]', content).onclick = findOnline;

  async function save() {
    if (!draft.name.trim() || processing) return;
    const food = existing ? { ...existing } : { id: newId(), isSeed: false, dateAdded: Date.now(), imageSearchTerm: null };
    food.name = draft.name.trim();
    food.brand = draft.brand?.trim() || null;
    food.upc = String(draft.upc ?? '').replace(/\D/g, '') || null;
    food.emoji = draft.emoji || '🍽️';
    food.servingDescription = draft.servingDescription?.trim() || '1 serving';
    food.servingGrams = draft.servingGrams ?? null;
    for (const k of NUTRIENT_KEYS) food[k] = draft[k] ?? null;
    for (const k of ['calories', 'totalFat', 'sodium', 'totalCarbohydrate', 'protein']) food[k] ??= 0;
    food.glycemicIndex = draft.glycemicIndex ?? null;
    food.glycemicNote = draft.glycemicNote?.trim() || null;
    food.lowersBloodPressure = !!draft.lowersBloodPressure;
    food.bloodPressureNote = food.lowersBloodPressure ? draft.bloodPressureNote?.trim() || null : null;
    food.image = image;
    food.imageSourceURL = draft.imageSourceURL ?? null;

    state.foods = state.foods.filter((f) => f.id !== food.id).concat(food);
    try {
      await store.put(food);
    } catch {
      toast('Couldn’t save to this device’s storage.');
    }
    finish(food);
    if (!food.image) backfillImages();
  }

  showPhoto();
  refresh();
  if (!image && (draft.name.trim() || draft.imageSourceURL)) findOnline();
}

// ---------------------------------------------------------------------------
// Photos

let backfilling = false;

async function backfillImages() {
  if (backfilling) return;
  backfilling = true;
  try {
    // Current card first, then the rest alphabetically.
    for (;;) {
      const missing = sortedFoods().filter((f) => !f.image && !f.imageFailed);
      if (!missing.length) break;
      const food = missing.find((f) => f.id === state.currentId) ?? missing[0];
      const image = await findFoodImage(food).catch(() => null);
      const live = state.foods.find((f) => f.id === food.id);
      if (!live) continue;
      if (image) {
        live.image = image;
        try { await store.put(live); } catch { /* ignore */ }
      } else {
        live.imageFailed = true; // retried next launch
      }
      updatePhoto(live);
    }
  } finally {
    backfilling = false;
  }
}

async function refreshPhoto(food) {
  const live = state.foods.find((f) => f.id === food.id);
  if (!live) return;
  const previous = live.image;
  live.image = null;
  live.imageFailed = false;
  updatePhoto(live);
  toast('Looking for a new photo…');
  const image = await findFoodImage({ ...live, imageSearchTerm: null }).catch(() => null);
  live.image = image ?? previous;
  if (!image) toast('No other photo found. Use Edit to take or choose one.');
  try { await store.put(live); } catch { /* ignore */ }
  updatePhoto(live);
}

function updatePhoto(food) {
  const box = deck.querySelector(`[data-photo="${CSS.escape(food.id)}"]`);
  if (!box) return;
  box.innerHTML = photoHTML(food);
}

// ---------------------------------------------------------------------------
// Misc

let toastTimer;
function toast(text) {
  const el = $('#toast');
  el.textContent = text;
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 3200);
}

if ('serviceWorker' in navigator && location.protocol === 'https:') {
  navigator.serviceWorker.register('sw.js').catch(() => {});
}

boot().catch((err) => {
  deck.innerHTML = `<div class="empty"><h2>Couldn’t start NutriCard</h2><p>${esc(err.message)}</p></div>`;
});
