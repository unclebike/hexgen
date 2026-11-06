// daily.js — The Daily Dial: one seeded SPRINT a day, the same for everyone, with
// one or two modifiers that change the rules
//
// The UTC day picks everything: the deal, which triangles arrive in what order,
// and the modifiers. Modifiers never appear outside the daily. This mirrors
// Daily.swift exactly, so a day plays the same here as in the iOS app.

import { key } from './grid.js';
import { POWER_CHANCE, stepGravity } from './dropper.js';
import { findHexes } from './hexdetect.js';
import { SeededGenerator, randomElement, shuffled, unit } from './rng.js';
import { COLOR_COUNT } from './progression.js';

const VERSION = 1;
const RECORDS_KEY = 'dialhex_daily';
const KEPT_DAYS = 120;

/** Every modifier. Helps make the game easier or score more; twists make it harder or stranger. */
export const MODIFIERS = ['overtime', 'downpour', 'powerSurge', 'junkyard', 'wanted', 'comboFever', 'oneWay', 'fullSpectrum'];
const HELPS = new Set(['overtime', 'powerSurge', 'wanted', 'comboFever']);
export const isHelp = modifier => HELPS.has(modifier);

export const OVERTIME_PER_HEX = 3;   // seconds each hex adds
export const OVERTIME_CAP = 60;      // the most it can add in one game
export const WANTED_WEIGHT = 3;      // how many times over a wanted hex counts
export const SURGE_POWER_CHANCE = POWER_CHANCE * 5;
const JUNKYARD_PILE = 60;
const PILE_TRIES = 50;

/**
 * What a clear of `hexes` is worth, in hexes: each counts once, a wanted one
 * WANTED_WEIGHT times, and under COMBO FEVER the nth hex of a clear counts n
 * times over (1, 3, 6, 10 for one to four hexes).
 */
export function hexValue(hexes, wanted, modifiers) {
  let value = hexes.reduce((total, hex) => total + (hex.color === wanted ? WANTED_WEIGHT : 1), 0);
  if (modifiers.has('comboFever')) value *= (hexes.length + 1) / 2;
  return value;
}

const uint64 = n => BigInt.asUintN(64, BigInt(n));
const floorDiv = (a, b) => Math.floor(a / b);

/** A seed for `value`, apart from every other `salt`'s and this version's. */
function mix(value, salt) {
  return new SeededGenerator(value ^ (salt << 32n) ^ (BigInt(VERSION) << 56n)).next();
}

/** Every modifier, shuffled by an eight-day block's own generator. */
function shuffledModifiers(block) {
  return shuffled(MODIFIERS, new SeededGenerator(mix(uint64(block), 0xB10Cn)));
}

/**
 * Each run of eight days plays every modifier once as the day's main one, in a
 * shuffled order, and the shuffle never starts on the one the last run ended on.
 */
function primary(day) {
  const block = floorDiv(day, MODIFIERS.length);
  const order = shuffledModifiers(block);
  if (order[0] === shuffledModifiers(block - 1).at(-1)) [order[0], order[1]] = [order[1], order[0]];
  return order[day - block * MODIFIERS.length];
}

/** One day in three has two modifiers, first or second in its run of three, never third. */
function isPairDay(day) {
  const window = floorDiv(day, 3);
  return day - window * 3 === Number(mix(uint64(window), 0x9A12n) % 2n);
}

/** Days since 1970-01-01, in UTC. */
export const todayNumber = (now = Date.now()) => Math.floor(now / 86_400_000);

/** One day's Daily Dial: its day, seed, and one modifier or a help paired with a twist (help first). */
export function dailyChallenge(day) {
  const seed = mix(uint64(day), 0xD1A1n);
  const main = primary(day);
  let modifiers = [main];
  if (isPairDay(day)) {
    // A partner of the other kind, that wasn't yesterday's and won't be tomorrow's
    const neighbours = new Set([primary(day - 1), primary(day + 1)]);
    const partners = MODIFIERS.filter(m => isHelp(m) !== isHelp(main) && !neighbours.has(m));
    const partner = partners[Number(mix(uint64(day), 0x9A1En) % BigInt(partners.length))];
    modifiers = isHelp(main) ? [main, partner] : [partner, main];
  }
  return { day, seed, modifiers };
}

/**
 * The triangles a daily deals, in order. Every new triangle takes exactly one
 * roll, whatever the board looks like.
 */
export class DealStream {
  constructor(rng) {
    this.rng = rng;
  }

  next() {
    const { rng } = this;
    return { column: unit(rng.next()), color: rng.next(), power: unit(rng.next()), drain: (rng.next() & 1n) === 0n };
  }

  clone() {
    return new DealStream(this.rng.clone());
  }
}

/**
 * Every random choice a daily needs, each from its own generator, so one never
 * shifts another: what the player does can't change which triangles come next.
 */
export function dailyStreams(seed) {
  const root = new SeededGenerator(seed);
  const deal = new DealStream(new SeededGenerator(root.next()));
  const swaps = new SeededGenerator(root.next());
  const wanted = new SeededGenerator(root.next());
  return { deal, swaps, wanted, pileSeed: root.next() };
}

/** JUNKYARD's opening pile: dropped in by the game's own gravity, in every colour, with no hex finished. */
export function junkyardPile(grid, pileSeed) {
  const rng = new SeededGenerator(pileSeed);
  const colors = Array.from({ length: COLOR_COUNT }, (_, i) => i);
  for (let attempt = 0; attempt < PILE_TRIES; attempt++) {
    const board = randomPile(grid, colors, rng);
    if (findHexes(grid, board).length === 0) return board;
  }
  return new Map();
}

function randomPile(grid, colors, rng) {
  const board = new Map();
  for (let id = 0; id < JUNKYARD_PILE; id++) {
    const open = grid.spawnCells.filter(({ r, c }) => !board.has(key(r, c)));
    if (open.length === 0) break;
    const cell = randomElement(open, rng);
    board.set(key(cell.r, cell.c), { id, color: randomElement(colors, rng), power: null, from: null, clearT: 0 });
    // Run gravity until nothing moves
    for (let step = 0; step < grid.cells.length; step++) {
      stepGravity(grid, board);
      if (![...board.values()].some(p => p.from)) break;
    }
  }
  return board;
}

// ===== Records =====

function loadRecords() {
  try {
    return JSON.parse(localStorage.getItem(RECORDS_KEY)) || {};
  } catch (e) {
    return {};
  }
}

function saveRecords(records) {
  try {
    localStorage.setItem(RECORDS_KEY, JSON.stringify(records));
  } catch (e) { /* storage unavailable */ }
}

/** How a day's daily went: { firstTry, best, tries }, or undefined. */
export const dailyResult = day => loadRecords()[day];

/** The latest day with a result, or null. */
export function latestDailyDay() {
  const days = Object.keys(loadRecords()).map(Number);
  return days.length ? Math.max(...days) : null;
}

/** Record a finished game of `day`'s daily: was it the day's first try, and did it beat the day's best? */
export function recordDaily(score, day) {
  const records = loadRecords();
  const result = records[day];
  const best = !result || score > result.best;
  if (result) {
    result.best = Math.max(result.best, score);
    result.tries++;
  } else {
    records[day] = { firstTry: score, best: score, tries: 1 };
  }
  for (const saved of Object.keys(records)) {
    if (Number(saved) <= day - KEPT_DAYS) delete records[saved];
  }
  saveRecords(records);
  return { first: !result, best };
}

/** Days in a row with a daily played, up to `today`. Today not played yet doesn't break it. */
export function dailyStreak(today) {
  const records = loadRecords();
  let day = records[today] ? today : today - 1;
  let count = 0;
  while (records[day]) {
    count++;
    day--;
  }
  return count;
}
