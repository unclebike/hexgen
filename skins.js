// skins.js — Brand tokens, skins, and skin unlocks
//
// Everything visual comes from skins.json, which the iOS app bundles too, so
// both builds share one set of colours, marks, line weights, fonts, and copy.

const SKIN_KEY = 'dialhex_skin';
const PROGRESS_KEY = 'dialhex_progress';
const HARD_CUT_GAP = 1000 / 3; // ms; never flash more than three times a second

let tokens = null;
let base = null;    // the active skin as written in skins.json
let strobeIndex = 0;
let lastHardCut = -Infinity;

/** The active skin: colours, fonts, stroke and effect settings. */
export const skin = {};

/** Fetch skins.json and every font it names. Resolves once both are ready. */
export async function loadBrand() {
  const response = await fetch('skins.json', { cache: 'no-cache' });
  tokens = await response.json();
  await loadFonts();
  const saved = storageGet(SKIN_KEY);
  const unlocked = unlockedSkins();
  applySkin(unlocked.find(s => s.id === saved) || unlocked[0]);
}

async function loadFonts() {
  const names = new Set(tokens.skins.flatMap(s => Object.values(s.fonts)));
  await Promise.all([...names].map(async name => {
    // Our own instances ship as WOFF2; Alfa Slab One ships unmodified (see fonts/README.md)
    const file = name.startsWith('Dialhex') ? `${name}.woff2` : `${name}.ttf`;
    try {
      document.fonts.add(await new FontFace(name, `url(fonts/${file})`).load());
    } catch (e) {
      // A missing font falls back to the browser's; the game still runs
    }
  }));
}

export const copy = () => tokens.copy;
export const marks = () => tokens.marks;
export const logo = () => tokens.logo;
export const skinCount = () => tokens.skins.length;

/** The three line weights, sized from the board scale (pixels per triangle side). */
export function weights(scale) {
  const w = tokens.weights;
  return { hairline: w.hairline, hairlineAlpha: w.hairlineAlpha, line: scale * w.line, heavy: scale * w.heavy };
}

/** A CSS font string for one of the skin's three roles: display, text, digits. */
export function font(role, px) {
  return `${Math.round(px * (skin.fontScale || 1))}px "${skin.fonts[role]}"`;
}

/** '#RRGGBB' at an opacity. */
export function rgba(hex, alpha) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}

// ===== Colour =====

function channels(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [n >> 16, (n >> 8) & 255, n & 255];
}

function toHex(rgb) {
  return '#' + rgb.map(v => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, '0')).join('');
}

/** Mix toward white (amount > 0) or black (amount < 0). */
function tint(hex, amount) {
  const target = amount > 0 ? 255 : 0;
  return toHex(channels(hex).map(v => v + (target - v) * Math.abs(amount)));
}

function luminance(hex) {
  const [r, g, b] = channels(hex).map(v => {
    const c = v / 255;
    return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

function contrast(a, b) {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
}

/** Whichever of the skin's mark colour and ink stands out more on a piece. */
export function markColor(pieceHex) {
  return contrast(pieceHex, skin.mark) >= contrast(pieceHex, skin.ink) ? skin.mark : skin.ink;
}

// ===== Applying a skin =====

function applySkin(next) {
  base = next;
  strobeIndex = 0;
  Object.assign(skin, {
    id: next.id,
    background: next.background,
    empty: next.empty,
    mark: next.mark,
    fonts: next.fonts,
    fontScale: next.fontScale || 1,
    stroke: next.stroke,
    effects: next.effects,
    sound: next.sound,
  });
  applyStrobe();
  storageSet(SKIN_KEY, next.id);
  document.body.style.background = next.background;
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', next.background);
}

/** Single-hue skins derive ink and pieces from the current strobe colour. */
function applyStrobe() {
  const strobe = base.effects.strobe;
  if (strobe) {
    const hue = strobe[strobeIndex % strobe.length];
    skin.ink = hue;
    skin.pieces = base.effects.tints.map(t => tint(hue, t));
  } else {
    skin.ink = base.ink;
    skin.pieces = base.pieces;
  }
}

/**
 * A hex cleared. Skins with a strobe cut to the next hue. Returns true if the
 * screen should flash this frame (rate-limited for photosensitive players).
 */
export function hardCut(now = performance.now()) {
  if (!base.effects.strobe) return false;
  strobeIndex++;
  applyStrobe();
  if (now - lastHardCut < HARD_CUT_GAP) return false;
  lastHardCut = now;
  return true;
}

/** Back to the skin's first hue, for a new game. */
export function resetStrobe() {
  strobeIndex = 0;
  applyStrobe();
}

// ===== Unlocks =====

export function loadProgress() {
  try {
    const saved = JSON.parse(storageGet(PROGRESS_KEY));
    if (saved) return { mainWins: saved.mainWins || 0, hexes: saved.hexes || 0 };
  } catch (e) {
    // corrupted; start over
  }
  return { mainWins: 0, hexes: 0 };
}

/** One skin to start with, plus one per MAIN win and per milestone reached. */
export function unlockedCount(progress = loadProgress()) {
  const milestones = tokens.unlocks.milestones.filter(m => progress.hexes >= m).length;
  return Math.min(tokens.skins.length, 1 + progress.mainWins + milestones);
}

export function unlockedSkins() {
  return tokens.skins.slice(0, unlockedCount());
}

/**
 * Add to lifetime progress. Returns the ids of any skins this unlocked, in
 * order, so the game-over screen can announce them.
 */
export function recordProgress({ hexes = 0, mainWin = false }) {
  const progress = loadProgress();
  const before = unlockedCount(progress);
  progress.hexes += hexes;
  if (mainWin) progress.mainWins++;
  storageSet(PROGRESS_KEY, JSON.stringify(progress));
  return tokens.skins.slice(before, unlockedCount(progress)).map(s => s.id);
}

/**
 * Open every skin (the hidden 20-taps-on-the-logo shortcut). Tops progress up
 * rather than replacing it, so a real record is never lost.
 */
export function unlockAll() {
  const progress = loadProgress();
  const { milestones } = tokens.unlocks;
  progress.hexes = Math.max(progress.hexes, Math.max(0, ...milestones));
  progress.mainWins = Math.max(progress.mainWins, tokens.skins.length - 1 - milestones.length);
  storageSet(PROGRESS_KEY, JSON.stringify(progress));
}

/** Switch to the next unlocked skin, wrapping around. */
export function cycleSkin() {
  const unlocked = unlockedSkins();
  const i = unlocked.findIndex(s => s.id === skin.id);
  applySkin(unlocked[(i + 1) % unlocked.length]);
}

/** Where the active skin sits in the unlocked list, 1-based. */
export function skinPosition() {
  return unlockedSkins().findIndex(s => s.id === skin.id) + 1;
}

function storageGet(k) {
  try { return localStorage.getItem(k); } catch (e) { return null; }
}

function storageSet(k, v) {
  try { localStorage.setItem(k, v); } catch (e) { /* storage unavailable */ }
}
