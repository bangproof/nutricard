// Run with: node --test tests-web/logic.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  Glycemic, matchScore, bpMatch, giBestMatch, formatAmount, percentDV, DailyValue, scaleFacts,
  availableCarbohydrate, applySuggestions, emptyDraft, foodFromSeed, bpFact, upcEquivalent, upcVariants,
} from '../docs/js/core.js';
import { draftFromOpenFoodFacts, draftFromUSDA } from '../docs/js/api.js';

const gi = JSON.parse(readFileSync(new URL('../docs/data/GIReference.json', import.meta.url)));
const seeds = JSON.parse(readFileSync(new URL('../docs/data/SeedFoods.json', import.meta.url)));

test('glycemic load uses available carbohydrate', () => {
  const avail = availableCarbohydrate({ totalCarbohydrate: 27, dietaryFiber: 3.1 });
  const gl = Glycemic.load(51, avail);
  assert.ok(Math.abs(gl - 12.19) < 0.01);
  assert.equal(Glycemic.formatLoad(gl), '12');
  assert.equal(Glycemic.loadLevel(gl), 'medium');
});

test('GI and GL levels', () => {
  assert.equal(Glycemic.indexLevel(55), 'low');
  assert.equal(Glycemic.indexLevel(56), 'medium');
  assert.equal(Glycemic.indexLevel(70), 'high');
  assert.equal(Glycemic.loadLevel(10.4), 'low');
  assert.equal(Glycemic.loadLevel(19.4), 'medium');
  assert.equal(Glycemic.loadLevel(20), 'high');
  assert.equal(Glycemic.formatLoad(0.2), '<1');
});

test('label formatting and scaling', () => {
  assert.equal(formatAmount(0), '0');
  assert.equal(formatAmount(0.34), '0.3');
  assert.equal(formatAmount(4), '4');
  assert.equal(formatAmount(18.9), '19');
  assert.equal(percentDV(2300, DailyValue.sodium), 100);
  const f = scaleFacts({ calories: 100, totalCarbohydrate: 20, dietaryFiber: 4, saturatedFat: null }, 2);
  assert.equal(f.calories, 200);
  assert.equal(availableCarbohydrate(f), 32);
  assert.equal(f.saturatedFat, null);
});

test('word matching', () => {
  assert.notEqual(matchScore('Rice, brown, long-grain, cooked', ['rice brown']), null);
  assert.equal(matchScore('Licorice', ['rice']), null);
  assert.equal(matchScore('Pistachios, salted', ['pistachios'], ['salted']), null);
  assert.notEqual(matchScore('Pistachios, unsalted', ['pistachios'], ['salted']), null);
});

test('blood pressure matches', () => {
  assert.equal(bpMatch('Beets, boiled')?.id, 'beet');
  assert.equal(bpMatch('Organic Baby Spinach')?.id, 'spinach');
  assert.equal(bpMatch('Lentils, mature seeds, cooked')?.id, 'pulses');
  assert.equal(bpMatch('Sweet potato, baked')?.id, 'sweet-potato');
  assert.equal(bpMatch('Beet sugar'), null);
  assert.equal(bpMatch('Banana chips'), null);
  assert.equal(bpMatch('Rice porridge'), null);
  assert.equal(bpMatch('White bread'), null);
  assert.notEqual(bpMatch('Spinach, canned', 300), null);
  assert.equal(bpMatch('Spinach, canned', 700), null);
});

test('GI reference table', () => {
  const g = (t) => giBestMatch(gi, t)?.gi ?? null;
  assert.equal(g('Rice, brown, long-grain, cooked'), 68);
  assert.equal(g('Rice, white, cooked'), 73);
  assert.equal(g('Apple juice, unsweetened'), 41);
  assert.equal(g('Apples, raw, with skin'), 36);
  assert.equal(g('Sweet potato, cooked, boiled'), 63);
  assert.equal(g('Potatoes, boiled'), 78);
  assert.equal(g('Milk, nonfat'), 37);
  assert.equal(g('Spinach, raw'), null);
});

test('draft suggestions', () => {
  const d = emptyDraft('Beets, cooked');
  d.sodium = 80;
  applySuggestions(d, gi);
  assert.equal(d.glycemicIndex, 64);
  assert.equal(d.lowersBloodPressure, true);
  assert.ok(d.bloodPressureNote.length > 20);
});

test('seed data is consistent', () => {
  assert.ok(seeds.length >= 20);
  const ids = new Set();
  for (const s of seeds) {
    if (s.bloodPressureID) assert.ok(bpFact(s.bloodPressureID), s.bloodPressureID);
    if (s.glycemicIndex == null) {
      assert.ok(s.totalCarbohydrate - (s.dietaryFiber ?? 0) < Glycemic.minimumTestableCarbohydrate, s.name);
    }
    const food = foodFromSeed(s);
    assert.ok(!ids.has(food.id), `duplicate id ${food.id}`);
    ids.add(food.id);
  }
  assert.ok(foodFromSeed(seeds.find((s) => s.name.startsWith('Beets'))).lowersBloodPressure);
});

test('Open Food Facts per-serving and per-100 g', () => {
  const a = draftFromOpenFoodFacts({ status: 1, product: {
    product_name: 'Oat Crunch', brands: 'Acme, Acme Foods', serving_size: '1 cup (40 g)', serving_quantity: '40',
    nutriments: { 'energy-kcal_serving': 150, sodium_serving: 0.19, sugars_serving: '6', 'energy-kcal_unit': 'kcal' },
    image_front_url: 'https://example.com/a.jpg' } }, '0123');
  assert.equal(a.name, 'Oat Crunch');
  assert.equal(a.brand, 'Acme');
  assert.equal(a.servingDescription, '1 cup (40 g)');
  assert.equal(a.calories, 150);
  assert.ok(Math.abs(a.sodium - 190) < 1e-9);
  assert.equal(a.totalSugars, 6);
  const b = draftFromOpenFoodFacts({ status: 1, product: {
    product_name: 'Beet Chips', serving_quantity: 28, serving_size: '28 g',
    nutriments: { 'energy-kcal_100g': 500, carbohydrates_100g: 50, salt_100g: 1 } } }, '1');
  assert.ok(Math.abs(b.calories - 140) < 1e-9);
  assert.ok(Math.abs(b.sodium - 112) < 1e-9);
  assert.equal(draftFromOpenFoodFacts({ status: 0 }, '1'), null);
});

test('USDA portion scaling', () => {
  const d = draftFromUSDA({
    fdcId: 1, description: 'BEETS, COOKED, BOILED, DRAINED',
    foodNutrients: [
      { nutrient: { id: 1008, unitName: 'kcal' }, amount: 44 },
      { nutrient: { id: 1093, unitName: 'mg' }, amount: 77 },
    ],
    foodPortions: [{ amount: 1, gramWeight: 170, modifier: 'cup, slices', measureUnit: { name: 'undetermined' } }],
  });
  assert.equal(d.name, 'Beets, cooked, boiled, drained');
  assert.equal(d.servingDescription, '1 cup, slices (170 g)');
  assert.ok(Math.abs(d.calories - 74.8) < 1e-9);
  assert.ok(Math.abs(d.sodium - 130.9) < 1e-9);
});

test('UPC handling', () => {
  assert.ok(upcEquivalent('0012345678905', '012345678905'));
  assert.ok(!upcEquivalent('123', '124'));
  assert.deepEqual(upcVariants('0012345678905'), ['0012345678905', '012345678905']);
});
