// ui.js — Menus and cards: the tile menu, setup, how to play, the daily, pause, and the result
//
// These are HTML rather than canvas, so text can wrap and scroll, keyboards can
// move between buttons, and screen readers can read them. The game's canvas
// shows through underneath. Everything is rebuilt from `view` when it changes.

import {
  skin, copy, font, rgba, weights, skinCount, unlockedCount, skinLocked, skinRequirement, playableSkinId, SECONDARY,
} from './skins.js';
import { binFrame, viewSize, MENU_CONTENT_HEIGHT, tracePath, sharpLines } from './renderer.js';
import { drawArt, drawModifier } from './icons.js';
import { loadHighScores } from './scoring.js';
import { settings } from './settings.js';
import { isMuted } from './audio.js';
import { inputKind } from './input.js';
import { BOARDS, SPEEDS } from './progression.js';
import { MODIFIERS, isHelp, dailyResult, dailyStreak } from './daily.js';
import { createGame, fallProgress, binFill, CLEAR_TIME } from './gamestate.js';
import { DemoPlayer } from './demo.js';
import { key, SQRT3 } from './grid.js';

const BUILD = 'build 8';
const MODES = ['main', 'endless', 'sprint'];
const ROW_WIDTH = 300;
const GAP = 8;
const LABEL_TRACKING = 0.08;
const LABEL_SIZE = 13;
const TILE_INSET = 9;
const PREVIEW_SIZE = 190;
const PREVIEW_RESTART_FILL = 0.7;

let root = null;
let announcer = null;
let actions = {};

const view = {
  menu: false,
  reveal: false, // the menu builds in, once, as it opens
  enter: false,  // a card or the pause menu fades in, once, as it opens
  card: null,    // 'setup' | 'howTo' | 'daily'
  tab: 0,        // the how-to's open section
  pause: null,   // { hidesBoard }
  result: null,  // what the finished game earned
};

let preview = null; // the setup card's small bin, playing itself

/** Connect the UI. `actions` are the game's verbs: start, startDaily, cycleSkin, and so on. */
export function initUI(rootEl, announceEl, gameActions) {
  root = rootEl;
  announcer = announceEl;
  actions = gameActions;
  document.addEventListener('keydown', onKey);
}

/** Say something to screen readers. */
export function announce(text) {
  announcer.textContent = text;
}

// ===== Building elements =====

/** An element with attributes and children. `on*` attributes are listeners. */
function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [name, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (name.startsWith('on')) el.addEventListener(name.slice(2), value);
    else if (name === 'style') Object.assign(el.style, value);
    else if (name === 'class') el.className = value;
    else el.setAttribute(name, value === true ? '' : value);
  }
  el.append(...children.flat().filter(child => child !== null && child !== undefined && child !== false));
  return el;
}

/** A canvas of `w` × `h` CSS pixels, drawn once, hidden from screen readers. */
function canvasIcon(w, h_, draw) {
  const canvas = h('canvas', { 'aria-hidden': 'true', style: { width: `${w}px`, height: `${h_}px` } });
  const dpr = window.devicePixelRatio || 1;
  canvas.width = Math.ceil(w * dpr);
  canvas.height = Math.ceil(h_ * dpr);
  const ctx = canvas.getContext('2d');
  ctx.scale(dpr, dpr);
  sharpLines(ctx);
  draw(ctx);
  return canvas;
}

const art = (name, w, h_, value) => canvasIcon(w, h_, ctx => drawArt(ctx, name, w, h_, value));
const modifierIcon = (modifier, size) => canvasIcon(size, size, ctx => drawModifier(ctx, modifier, size, size));
const tracked = (text, size) => h('span', { class: 'tracked', style: { fontSize: `calc(${size}px * var(--font-scale))` } }, text);

/** An outlined, sharp-cornered button with a tracked label. `selected` takes the heavy weight. */
function faceButton(label, onclick, { id = label, width = 150, height = 44, selected = false, size = 14 } = {}) {
  return h('button', {
    class: `face${selected ? ' selected' : ''}`, 'data-id': id, onclick,
    style: { width: `${width}px`, height: `${height}px` },
  }, tracked(label, size));
}

// ===== Menu =====

/** Where the menu's column sits beside or under the bin, and how far it scales to fit. */
function menuPlacement() {
  const { w, h: height } = viewSize();
  const frame = binFrame('menu');
  const needed = MENU_CONTENT_HEIGHT - 30;
  const scaleFor = (width, room) => Math.max(0.6, Math.min(1.45, width / ROW_WIDTH, room / needed));
  if (w > height) {
    const left = frame.right + 16;
    return { landscape: true, left, u: scaleFor(w - left - 16, height - 24) };
  }
  const top = frame.bottom + 18;
  return { landscape: false, top, u: scaleFor(w - 32, height - top - 12) };
}

/** One size for every game tile's name: the largest the longest fits at, in this skin's font. */
function gameLabelSize(tileWidth) {
  const text = copy();
  const measure = document.createElement('canvas').getContext('2d');
  measure.font = font('display', LABEL_SIZE);
  const room = tileWidth - TILE_INSET * 2;
  const widest = Math.max(...[...MODES.map(id => text.modes[id].label), text.daily.label].map(label =>
    measure.measureText(label).width + label.length * LABEL_SIZE * LABEL_TRACKING));
  return widest > room ? Math.floor(LABEL_SIZE * room / widest * 2) / 2 : LABEL_SIZE;
}

function menu() {
  const text = copy();
  const { landscape, left, top, u } = menuPlacement();
  const unit = n => n * u;
  const rowWidth = unit(ROW_WIDTH);
  const gap = unit(GAP);
  const tileWidth = (rowWidth - gap * 2) / 3;
  const labelSize = gameLabelSize(ROW_WIDTH / 3 - GAP) * u;
  const bests = loadHighScores(settings.board);

  const modeTile = (id, order) => {
    const detail = id === 'main' && settings.board === 'big' ? text.board.mainDetail : text.modes[id].detail;
    const best = bests[id] || 0;
    return h('button', {
      class: 'face tile game', 'data-id': id, 'aria-label': [text.modes[id].label, detail, best ? `${text.best} ${best}` : ''].filter(Boolean).join(', '),
      style: { '--order': order, width: `${tileWidth}px`, height: `${unit(108)}px` }, onclick: () => actions.start(id),
    },
    art(id, unit(60), unit(34)),
    h('span', { class: 'tile-label', style: { fontSize: `${labelSize}px` } }, text.modes[id].label),
    h('span', { class: 'tile-detail', style: { fontSize: `calc(${unit(9)}px * var(--font-scale))` } }, detail),
    h('span', { class: 'tile-value', style: { fontSize: `calc(${unit(10)}px * var(--font-scale))` } }, best > 0 ? `${best}` : ' '));
  };

  const settingsTile = (id, label, icon, onclick, ariaLabel) => h('button', {
    class: 'face tile wide', 'data-id': id, 'aria-label': ariaLabel,
    style: { '--order': 6, width: `${tileWidth}px`, height: `${unit(68)}px` }, onclick,
  }, icon, h('span', { class: 'tile-small', style: { fontSize: `calc(${unit(11)}px * var(--font-scale))` } }, label));

  const lock = lockLines();
  const setupValue = `${text.speed.label} ${text.speed.levels[settings.speed]}, ${text.board.label} ${text.board.levels[settings.board]}`;
  const hint = inputKind() === 'touch' ? text.touchHint : text.keysHint;

  return h('div', {
    class: `menu ${landscape ? 'beside' : 'under'}${view.reveal ? ' reveal' : ''}`,
    style: landscape ? { left: `${left}px` } : { top: `${top}px` },
  },
  h('div', { class: 'menu-column', style: { width: `${rowWidth}px`, gap: `${gap}px` } },
    h('div', { class: 'row', style: { gap: `${gap}px` } }, MODES.map(modeTile)),
    dailyTile(rowWidth, unit(96), labelSize, u),
    h('div', { class: 'row', style: { gap: `${gap}px`, marginTop: `${unit(8)}px` } },
      settingsTile('skin', skin.id.toUpperCase(),
        art(skinLocked() ? 'lock' : 'palette', unit(32), unit(30)), actions.cycleSkin,
        `${text.skin}: ${skin.id}, ${unlockedCount()} of ${skinCount()} unlocked${lock ? `. ${lock.need}. ${lock.instead}` : ''}`),
      settingsTile('setup', text.setup.title, h('span', { class: 'pair' },
        art('gauge', unit(30), unit(30), settings.speed), art('boardGlyph', unit(30), unit(30), settings.board)),
      () => openCard('setup'), `${text.setup.title}: ${setupValue}`),
      settingsTile('howTo', text.howTo.short, art('question', unit(30), unit(30)), () => openHowTo(0), text.howTo.label)),
    lock && h('div', { class: 'lock', role: 'status' },
      h('div', {}, lock.need), h('div', { class: 'dim' }, lock.instead)),
    h('div', { class: 'hint', style: { '--order': 7 } }, hint),
    h('div', { class: 'build' }, BUILD)));
}

/** While a locked skin is previewed: what opens it, and the open skin a game would use meanwhile. */
function lockLines() {
  const need = skinRequirement();
  if (!need) return null;
  const text = copy().skinLock;
  const roads = [need.wins === 1 ? text.win : text.wins.replace('%d', need.wins)];
  if (need.hexes !== null) roads.push(text.hexes.replace('%d', need.hexes));
  return {
    need: `${text.label} · ${roads.join(text.or)}`,
    instead: text.playing.replace('%@', playableSkinId().toUpperCase()),
  };
}

const modifierNames = daily => daily.modifiers
  .map(m => copy().daily.modifiers[m].title.replace(/\.$/, ''))
  .join(copy().daily.and);

/**
 * The daily across the row: its symbol and name over today's rules on the left,
 * and on the right the day's best (with the streak under it), or before it's
 * played, the daily's own date.
 */
function dailyTile(width, height, labelSize, u) {
  const text = copy().daily;
  const daily = actions.todaysDaily();
  const result = dailyResult(daily.day);
  const streak = dailyStreak(daily.day);
  const date = new Date(daily.day * 86_400_000);
  const figure = result
    ? [h('span', { class: 'tile-detail' }, text.best.replace('%d', '').trim()),
      h('span', { class: 'tile-figure', style: { fontSize: `${18 * u}px` } }, `${result.best}`),
      streak > 1 && h('span', { class: 'tile-detail' }, text.streak.replace('%d', streak))]
    : [h('span', { class: 'tile-figure', style: { fontSize: `${18 * u}px` } }, `${date.getUTCDate()}`),
      h('span', { class: 'tile-detail' }, date.toLocaleDateString('en-GB', { month: 'short', timeZone: 'UTC' }).toLowerCase())];
  return h('button', {
    class: 'face tile daily', 'data-id': 'daily',
    'aria-label': `${text.label}. ${text.detail.replace('%@', modifierNames(daily))}${result ? `. ${text.best.replace('%d', result.best)}` : ''}`,
    style: { '--order': 4, width: `${width}px`, height: `${height}px`, padding: `0 ${14 * u}px` },
    onclick: () => openCard('daily'),
  },
  h('span', { class: 'daily-main' },
    h('span', { class: 'daily-title' },
      art('daily', 36 * u, 26 * u, daily.day),
      h('span', { class: 'tile-label', style: { fontSize: `${labelSize}px` } }, text.label)),
    h('span', { class: 'tile-rules', style: { fontSize: `calc(${10 * u}px * var(--font-scale))` } }, modifierNames(daily))),
  h('span', { class: 'daily-figure' }, figure));
}

const cardClass = (extra = '') => `card ${extra}${view.enter ? ' enter' : ''}`;

// ===== Setup =====

function openCard(card) {
  view.card = card;
  view.enter = true;
  if (card === 'setup') startPreview();
  render();
  root.querySelector('.card button, .card [tabindex]')?.focus({ preventScroll: true });
}

function closeCard() {
  const card = view.card;
  view.card = null;
  preview = null;
  render();
  root.querySelector(`[data-id="${card}"]`)?.focus({ preventScroll: true });
}

function startPreview() {
  preview = {
    game: createGame({ mode: 'endless', speed: settings.speed, board: settings.board }),
    player: new DemoPlayer(),
    canvas: null,
  };
}

/** Choices over a live preview: how big the triangles are, and how fast they fall. */
function setupCard() {
  const text = copy();
  const choice = (group, label, id, chosen, icon, hint, onclick) => h('button', {
    class: `face tile choice${chosen ? ' selected' : ''}`, 'data-id': `${group}-${id}`, 'aria-pressed': chosen ? 'true' : 'false',
    'aria-label': `${label}: ${hint}`, onclick,
    style: { height: '68px' },
  }, icon, h('span', { class: 'tile-small' }, label));

  const row = (label, ...tiles) => h('section', { class: 'setup-row' },
    h('h2', { class: 'tracked small' }, label), h('div', { class: 'row even' }, tiles));

  const summary = [text.setup.colours.replace('%d', BOARDS[settings.board].colorCount), text.speed.hints[settings.speed]];
  if (settings.board !== 'standard') summary.push(text.setup.ownBests);

  preview.canvas = canvasIcon(PREVIEW_SIZE, PREVIEW_SIZE, () => {});
  const choose = apply => value => {
    apply(value);
    startPreview();
    render();
  };

  const hand = settings.leftHanded ? text.leftHanded : text.rightHanded;
  const soundOn = !isMuted();
  return h('div', { class: cardClass(), role: 'dialog', 'aria-label': text.setup.title },
    h('div', { class: 'card-scroll scroll', tabindex: '-1' },
      h('div', { class: 'card-column setup' },
        h('h1', {}, text.setup.title),
        preview.canvas,
        row(text.board.label, ...Object.keys(BOARDS).map(id => choice('board', text.board.levels[id], id, settings.board === id,
          art('boardGlyph', 28, 28, id), text.board.hints[id], () => choose(actions.setBoard)(id)))),
        row(text.speed.label, ...Object.keys(SPEEDS).map(id => choice('speed', text.speed.levels[id], id, settings.speed === id,
          art('gauge', 28, 28, id), text.speed.hints[id], () => choose(actions.setSpeed)(id)))),
        h('p', { class: 'summary' }, summary.filter(Boolean).join(' · ')),
        row('',
          choice('hand', hand, 'toggle', false, art('hand', 28, 28, settings.leftHanded), hand, () => { actions.toggleHand(); render(); }),
          choice('sound', text.shortcuts.sound, 'toggle', false, art('speaker', 28, 28, soundOn),
            soundOn ? 'on' : 'off', () => { actions.toggleSound(); render(); })),
        faceButton(text.setup.done, closeCard, { width: 160, id: 'done' }))));
}

/** The lattice turned as in play. Every board fills the same space. */
function drawPreview(game, canvas) {
  const size = PREVIEW_SIZE;
  const ctx = canvas.getContext('2d');
  const { grid } = game;
  const n = grid.size;
  const scale = Math.min(size / (2 * n * SQRT3 / 2), size / (2 * n)) * 0.97;
  const at = ({ x, y }) => ({ x: size / 2 - y * scale, y: size / 2 + x * scale });
  ctx.clearRect(0, 0, size, size);
  sharpLines(ctx);

  const bin = grid.binOutline().map(at);
  tracePath(ctx, bin);
  ctx.fillStyle = skin.empty;
  ctx.fill();

  ctx.strokeStyle = rgba(skin.ink, weights(1).hairlineAlpha * 2);
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (const { r, c } of grid.cells) {
    const [a, b, d] = grid.cellVertices(r, c).map(at);
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.lineTo(d.x, d.y);
    ctx.closePath();
  }
  ctx.stroke();

  // Each triangle slides from where it was toward its cell; a clearing one fades out
  const fallT = fallProgress(game);
  for (const { r, c } of grid.cells) {
    const p = game.board.get(key(r, c));
    if (!p) continue;
    const center = grid.cellCenter(r, c);
    const from = p.from ? grid.cellCenter(p.from.r, p.from.c) : center;
    const middle = { x: center.x + (from.x - center.x) * (1 - fallT), y: center.y + (from.y - center.y) * (1 - fallT) };
    tracePath(ctx, grid.cellVertices(r, c).map(v => at({
      x: middle.x + (v.x - center.x) * 0.9, y: middle.y + (v.y - center.y) * 0.9,
    })));
    ctx.fillStyle = p.clearT > 0 ? rgba(skin.pieces[p.color], p.clearT / CLEAR_TIME) : skin.pieces[p.color];
    ctx.fill();
  }

  const wt = weights(scale);
  tracePath(ctx, bin);
  ctx.strokeStyle = rgba(skin.ink, SECONDARY);
  ctx.lineWidth = wt.line;
  ctx.stroke();
  tracePath(ctx, grid.dialOutline(game.cursor.k, game.cursor.j).map(at));
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = wt.heavy;
  ctx.stroke();
}

/** Run the setup card's preview. */
export function tickUI(dt) {
  if (!preview?.canvas) return;
  preview.player.update(preview.game, Math.min(0.1, dt));
  if (preview.game.phase !== 'playing' || binFill(preview.game) > PREVIEW_RESTART_FILL) {
    const { canvas } = preview;
    startPreview();
    preview.canvas = canvas;
  }
  drawPreview(preview.game, preview.canvas);
}

// ===== How to play =====

function openHowTo(tab) {
  view.tab = tab;
  openCard('howTo');
}

function showTab(tab) {
  const count = copy().howTo.sections.length;
  view.tab = (tab + count) % count;
  render();
  root.querySelector('.howto-rules')?.scrollTo(0, 0);
}

/** A rule's text with the input in hand's button names filled in. */
function filled(template) {
  const names = copy().inputs[inputKind()] ?? copy().inputs.touch;
  return template.replace(/\{(confirm|cancel|resume|sides|pick)\}/g, (_, name) => names[name]);
}

/** The rules this build has: no versus, co-op, controllers, or Apple TV remote. */
function webRules(section) {
  const kind = inputKind();
  const rules = copy().howTo.rules
    .filter(rule => rule.section === section && rule.only !== 'tvos')
    .filter(rule => !['online', 'versus', 'gamepad'].includes(rule.art));
  // The controls in your hand come first
  return section === 'controls' ? rules.sort((a, b) => (b.input === kind) - (a.input === kind)) : rules;
}

/** Wording that mentions what this build leaves out. */
const webWording = body => body.replace('the daily and versus always play at', 'the daily always plays at');

function keyTable(rows) {
  return h('table', { class: 'keys' }, h('tbody', {}, rows.map(row => h('tr', {},
    h('th', { scope: 'row' }, row.action),
    row.keys.map(keys => h('td', {}, keys.map(name => (name.startsWith('sf:') ? name.split('|')[1] ?? '' : name)).join('  ')))))));
}

function ruleRow(rule, today) {
  const size = { w: 56, h: rule.art === 'daily' ? 42 : 40 };
  return h('article', { class: 'rule' },
    h('div', { class: 'rule-art' }, art(rule.art, size.w, size.h, today)),
    h('div', { class: 'rule-text' },
      h('h3', {}, rule.title),
      h('p', {}, webWording(filled(rule.body))),
      rule.keys && keyTable(rule.keys)));
}

/** Every daily modifier, in two groups: helps, then twists. */
function modifierList() {
  const text = copy().daily;
  const group = (label, help) => h('section', { class: 'modifier-group' },
    h('h3', { class: 'tracked small dim' }, label.toUpperCase()),
    MODIFIERS.filter(m => isHelp(m) === help).map(m => h('div', { class: 'modifier' },
      modifierIcon(m, 30),
      h('div', {}, h('h4', {}, text.modifiers[m].title), h('p', {}, text.modifiers[m].detail)))));
  return [group(text.helps, true), group(text.twists, false)];
}

function howToCard() {
  const text = copy().howTo;
  const section = text.sections[view.tab];
  const today = actions.todaysDaily().day;
  return h('div', { class: cardClass('solid'), role: 'dialog', 'aria-label': text.label },
    h('header', { class: 'howto-head' },
      h('h1', {}, text.title),
      h('div', { class: 'tabs', role: 'tablist' }, text.sections.map((s, i) => h('button', {
        class: `tab${i === view.tab ? ' selected' : ''}`, role: 'tab', 'aria-selected': i === view.tab ? 'true' : 'false',
        'data-id': `tab-${i}`, onclick: () => showTab(i),
      }, s.label)))),
    h('div', { class: 'howto-rules scroll', tabindex: '0' },
      h('div', { class: 'card-column' },
        h('p', { class: 'lead' }, section.lead),
        webRules(section.id).map(rule => ruleRow(rule, today)),
        section.id === 'modes' && modifierList())),
    h('footer', { class: 'howto-foot' }, faceButton(text.done, closeCard, { id: 'done' })));
}

// ===== Daily intro =====

/** The card before a daily: today's rule changes, how a daily works, and how the day's gone so far. */
function dailyCard() {
  const text = copy().daily;
  const daily = actions.todaysDaily();
  const result = dailyResult(daily.day);
  const streak = dailyStreak(daily.day);
  const today = result && [
    text.firstTryScore.replace('%d', result.firstTry),
    text.best.replace('%d', result.best),
    streak > 1 && text.streak.replace('%d', streak),
  ].filter(Boolean).join(' · ');
  return h('div', { class: cardClass(), role: 'dialog', 'aria-label': text.introTitle },
    h('div', { class: 'card-scroll scroll', tabindex: '-1' },
      h('div', { class: 'card-column daily-intro' },
        h('header', { class: 'daily-head' }, art('daily', 48, 34, daily.day), h('h1', {}, text.introTitle)),
        h('p', { class: 'body' }, text.introBody),
        h('div', { class: 'today' }, daily.modifiers.map(m => h('div', { class: 'modifier large' },
          modifierIcon(m, 44),
          h('div', {}, h('h3', {}, text.modifiers[m].title), h('p', {}, text.modifiers[m].detail))))),
        h('ul', { class: 'points' }, text.introPoints.map(point => h('li', {}, point))),
        today && h('p', { class: 'body' }, today),
        h('div', { class: 'row buttons' },
          faceButton(text.start, actions.startDaily, { id: 'start' }),
          faceButton(text.back, closeCard, { id: 'back' })))));
}

// ===== Pause =====

/** A daily's pause covers the board entirely, so a pause is no time to plan. */
function pauseOverlay() {
  const text = copy();
  const classes = `pause${view.pause.hidesBoard ? ' solid' : ''}${view.enter ? ' enter' : ''}`;
  return h('div', { class: classes, role: 'dialog', 'aria-label': text.paused },
    h('h1', {}, text.paused),
    faceButton(text.resume, actions.togglePause, { width: 220, height: 52, size: 15, id: 'resume' }),
    faceButton(text.menu, actions.toMenu, { width: 220, height: 52, size: 15, id: 'menu' }),
    faceButton(settings.leftHanded ? text.leftHanded : text.rightHanded, () => {
      actions.toggleHand();
      render();
    }, { width: 220, height: 52, size: 15, id: 'hand' }));
}

// ===== Result =====

/** A finished game's result, set around its bin rather than laid over it. */
function resultOverlay() {
  const text = copy();
  const { w, h: height } = viewSize();
  const { headline, score, newBest, unlocked, daily } = view.result;
  const bin = binFrame('result');
  const verdict = h('div', { class: 'verdict' },
    h('h1', {}, headline),
    h('div', { class: 'score' }, `${score}`),
    newBest && h('p', {}, text.newBest));
  const details = h('div', { class: 'details' },
    daily && dailyFinish(daily),
    unlocked.map(id => h('p', {}, text.unlocked.replace('%@', id))),
    faceButton(text.menu, actions.toMenu, { width: 220, height: 52, size: 15, id: 'menu' }));

  if (w > height) {
    return h('div', { class: 'result beside', style: { left: `${bin.right}px` } }, verdict, details);
  }
  return h('div', { class: 'result' },
    h('div', { class: 'above', style: { height: `${Math.max(0, bin.y - 14)}px` } }, verdict),
    h('div', { class: 'below', style: { top: `${bin.bottom + 18}px` } }, details));
}

/** How the day's daily stands: a blind first try, or the first try against the best, and the streak. */
function dailyFinish({ first, result, streak, unkept }) {
  const text = copy().daily;
  return h('div', { class: 'daily-finish' },
    unkept && h('p', {}, text.unkept),
    !unkept && first && h('p', {}, text.firstTry),
    !unkept && !first && result && h('p', {},
      `${text.firstTryScore.replace('%d', result.firstTry)} · ${text.best.replace('%d', result.best)}`),
    streak > 1 && h('p', { class: 'dim' }, text.streak.replace('%d', streak)));
}

// ===== Keyboard =====

const DIRECTIONS = { ArrowUp: [0, -1], ArrowDown: [0, 1], ArrowLeft: [-1, 0], ArrowRight: [1, 0] };

/** Arrow keys move to the nearest button that way. */
function moveFocus(code) {
  const [dx, dy] = DIRECTIONS[code];
  const buttons = [...root.querySelectorAll('button')].filter(b => b.offsetParent !== null);
  const scope = view.card ? root.querySelectorAll('.card button') : buttons;
  const list = [...scope];
  if (list.length === 0) return false;
  const current = document.activeElement;
  if (!list.includes(current)) {
    list[0].focus();
    return true;
  }
  const from = current.getBoundingClientRect();
  const fromX = from.left + from.width / 2, fromY = from.top + from.height / 2;
  let best = null;
  let bestScore = Infinity;
  for (const button of list) {
    if (button === current) continue;
    const rect = button.getBoundingClientRect();
    const ex = rect.left + rect.width / 2 - fromX, ey = rect.top + rect.height / 2 - fromY;
    const ahead = ex * dx + ey * dy;
    if (ahead <= 1) continue;
    const score = ahead + Math.abs(ex * dy + ey * dx) * 2;
    if (score < bestScore) {
      bestScore = score;
      best = button;
    }
  }
  if (best) best.focus();
  return !!best;
}

function onKey(e) {
  if (view.card) {
    if (e.code === 'Escape') {
      e.preventDefault();
      closeCard();
    } else if (view.card === 'howTo' && (e.code === 'ArrowLeft' || e.code === 'ArrowRight')) {
      e.preventDefault();
      showTab(view.tab + (e.code === 'ArrowLeft' ? -1 : 1));
    } else if (e.code in DIRECTIONS && view.card !== 'howTo') {
      e.preventDefault();
      moveFocus(e.code);
    }
    return;
  }
  if (view.menu && e.code in DIRECTIONS) {
    e.preventDefault();
    moveFocus(e.code);
  }
}

/** Whether a card is open over the menu. */
export const cardOpen = () => view.card !== null;

// ===== Showing =====

function render() {
  if (!root) return;
  const focused = document.activeElement?.dataset?.id;
  const scroller = root.querySelector('.scroll');
  const scrollTop = scroller?.scrollTop ?? 0;
  const parts = [];
  if (view.menu) parts.push(menu());
  if (view.card === 'setup') parts.push(setupCard());
  else if (view.card === 'howTo') parts.push(howToCard());
  else if (view.card === 'daily') parts.push(dailyCard());
  if (view.pause) parts.push(pauseOverlay());
  if (view.result) parts.push(resultOverlay());
  root.replaceChildren(...parts);
  view.reveal = false; // only the first build animates
  view.enter = false;
  if (focused) root.querySelector(`[data-id="${CSS.escape(focused)}"]`)?.focus({ preventScroll: true });
  const next = root.querySelector('.scroll');
  if (next) next.scrollTop = scrollTop;
}

export const refreshUI = render;

export function showMenu({ reveal = true } = {}) {
  Object.assign(view, { menu: true, reveal, card: null, pause: null, result: null });
  preview = null;
  render();
}

/** Nothing over the game. */
export function showPlay() {
  Object.assign(view, { menu: false, card: null, pause: null, result: null });
  preview = null;
  render();
}

export function showPause(hidesBoard) {
  view.pause = { hidesBoard };
  view.enter = true;
  render();
}

export function hidePause() {
  view.pause = null;
  render();
}

export function showResult(result) {
  view.result = result;
  view.pause = null;
  render();
}
