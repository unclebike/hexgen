// renderer.js — Canvas drawing: the bin, falling triangles, the dial, marks, the logo, and skin effects

import { ROW_H, SQRT3, GRIDS, key, dialCells } from './grid.js';
import { CLEAR_TIME, ROTATE_TIME, fallProgress } from './gamestate.js';
import { skin, weights, rgba, markColor, marks, logo } from './skins.js';

const PIECE_INSET = 0.9;   // keep a gap between triangles, so the board reads as tiles
const GLIDE_TIME = 0.42;   // seconds the bin takes to move between layouts
const MENU_SHRINK = 0.8;   // the menu bin at most this much of the play bin, so a game visibly grows it
export const MENU_CONTENT_HEIGHT = 372; // what the portrait menu keeps under the bin

// The spinner's size against the bin's, and the gap between their facing edges, in bin radii
const SPINNER_SIZE = 0.55;
const SPINNER_GAP = 0.06;
const MAX_LANDSCAPE_SPINNER = 280; // px across, so it doesn't swamp a desktop window

let canvas, ctx;
let viewW = 0, viewH = 0;
let grain = null; // riso paper texture, made on first use

// Where the bin is now: its centre and radius (corner to centre). The rest follows from these.
const bin = { x: 0, y: 0, r: 100 };
let target = { kind: 'menu', leftHanded: false };
let glide = null; // { from, t } while moving between layouts

export function initRenderer(canvasEl) {
  canvas = canvasEl;
  ctx = canvas.getContext('2d');
  resize();
  return { canvas, ctx };
}

/** A rectangle's largest hex standing on a corner, and where it sits. */
function fit(area, maxR = Infinity) {
  return { x: area.x + area.w / 2, y: area.y + area.h / 2, r: Math.min(area.w / SQRT3, area.h / 2, maxR) };
}

/**
 * Portrait play: the bin and the spinner as neighbouring hexes. Both stand on a
 * corner; the spinner sits off the bin's lower side toward the player's hand, an
 * edge of each parallel to the other, and the pair fills the width. `lift` is room
 * kept clear under the pair: the stats hold the unlifted pair's baseline.
 */
function portraitPlay(w, h, onLeft, lift = 80, top = 44) {
  const room = { x: 8, y: top, w: Math.max(100, w - 16), h: Math.max(100, h - top - 12 - lift) };
  const k = SPINNER_SIZE;
  const apart = SQRT3 / 2 * (1 + k) + SPINNER_GAP;
  const sx = (onLeft ? -1 : 1) * apart / 2;
  const sy = apart * SQRT3 / 2;
  const minX = Math.min(-SQRT3 / 2, sx - k * SQRT3 / 2);
  const maxX = Math.max(SQRT3 / 2, sx + k * SQRT3 / 2);
  const minY = -1;
  const maxY = Math.max(1, sy + k);
  const unit = Math.min(room.w / (maxX - minX), room.h / (maxY - minY));
  const ox = room.x + room.w / 2 - (minX + maxX) / 2 * unit;
  const oy = room.y + room.h / 2 - (minY + maxY) / 2 * unit;
  return {
    bin: { x: ox, y: oy, r: unit },
    spinner: { x: ox + sx * unit, y: oy + sy * unit, r: k * unit },
  };
}

/** The play layout: where the bin and spinner sit, for the current hand. */
function playLayout(w, h, onLeft) {
  if (h >= w) return portraitPlay(w, h, onLeft);
  const stats = 120;
  const wheel = Math.max(140, w * 0.32);
  const [left, right] = onLeft ? [wheel, stats] : [stats, wheel];
  const place = fit({ x: left, y: 16, w: Math.max(100, w - left - right), h: Math.max(100, h - 32) });
  // The wide column beside the bin, close against it and below the stats
  const halfW = place.r * SQRT3 / 2;
  const gap = 14;
  const top = place.y - place.r * 0.2;
  const column = onLeft ? place.x - halfW : w - place.x - halfW;
  const side = Math.max(0, Math.min(column - 2 * gap, h - top - gap, MAX_LANDSCAPE_SPINNER));
  return {
    bin: place,
    spinner: {
      x: onLeft ? place.x - halfW - gap - side / 2 : place.x + halfW + gap + side / 2,
      y: top + (h - top - gap) / 2,
      r: side / 2,
    },
  };
}

/** Where the bin sits in a layout: 'play', 'menu', or 'result'. */
function placement(kind, w, h, onLeft) {
  const landscape = w > h;
  const play = playLayout(w, h, onLeft).bin;
  if (kind === 'play') return play;
  if (kind === 'menu') {
    if (landscape) return fit({ x: 16, y: 12, w: Math.max(100, w / 2 - 24), h: Math.max(100, h - 24) }, play.r * MENU_SHRINK);
    const height = Math.max(120, h - 12 - MENU_CONTENT_HEIGHT);
    const place = fit({ x: w * 0.06, y: 12, w: w * 0.88, h: height }, play.r * MENU_SHRINK);
    return { ...place, y: 12 + place.r }; // hugs the top
  }
  if (landscape) return fit({ x: 16, y: 16, w: Math.max(100, w / 2 - 24), h: Math.max(100, h - 32) });
  return fit({ x: w * 0.06, y: 150, w: w * 0.88, h: Math.max(120, h - 150 - 200) });
}

/** The bounding box of the bin at rest in a layout, for laying the UI around it. */
export function binFrame(kind, w = viewW, h = viewH) {
  const { x, y, r } = placement(kind, w, h, target.leftHanded);
  return { x: x - r * SQRT3 / 2, y: y - r, w: r * SQRT3, h: 2 * r, right: x + r * SQRT3 / 2, bottom: y + r };
}

/** Where the spinner sits, in play. */
export const spinnerPlace = () => playLayout(viewW, viewH, target.leftHanded).spinner;

/** The baseline the portrait stats hold: the unlifted pair's. */
export const statsBaseline = () => Math.max(0, viewH - (() => {
  const { spinner } = portraitPlay(viewW, viewH, target.leftHanded, 0);
  return spinner.y + spinner.r;
})() - 20);

export const isLandscape = () => viewW > viewH;

/** Move the bin to a layout, gliding there unless `snap`. */
export function setLayout(kind, leftHanded, snap = false) {
  if (target.kind === kind && target.leftHanded === leftHanded) return;
  target = { kind, leftHanded };
  if (snap) Object.assign(bin, placement(kind, viewW, viewH, leftHanded));
  else glide = { from: { ...bin }, t: 0 };
}

export function tickLayout(dt) {
  const goal = placement(target.kind, viewW, viewH, target.leftHanded);
  if (!glide) {
    Object.assign(bin, goal);
    return;
  }
  glide.t = Math.min(1, glide.t + dt / GLIDE_TIME);
  const t = glide.t;
  const eased = t < 0.5 ? 2 * t * t : 1 - (2 - 2 * t) ** 2 / 2;
  for (const axis of ['x', 'y', 'r']) bin[axis] = glide.from[axis] + (goal[axis] - glide.from[axis]) * eased;
  if (t >= 1) glide = null;
}

/** Fit the canvas to the viewport. */
export function resize() {
  const dpr = window.devicePixelRatio || 1;
  viewW = window.innerWidth;
  viewH = window.innerHeight;
  canvas.width = viewW * dpr;
  canvas.height = viewH * dpr;
  canvas.style.width = viewW + 'px';
  canvas.style.height = viewH + 'px';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}

export const viewSize = () => ({ w: viewW, h: viewH });

/** Pixels per triangle side on a board. Line weights everywhere are sized from this. */
export const getScale = (grid = GRIDS.standard) => bin.r / grid.size;

// Lattice x runs down the screen and lattice y runs right to left
export const toScreen = ({ x, y }, grid = GRIDS.standard) => {
  const scale = getScale(grid);
  return { x: bin.x - y * scale, y: bin.y + x * scale };
};
export const toUnit = (px, py, grid = GRIDS.standard) => {
  const scale = getScale(grid);
  return { x: (py - bin.y) / scale, y: -(px - bin.x) / scale };
};

export function tracePath(c, points) {
  c.beginPath();
  c.moveTo(points[0].x, points[0].y);
  for (let i = 1; i < points.length; i++) c.lineTo(points[i].x, points[i].y);
  c.closePath();
}

/** Sharp corners and square ends, everywhere. */
export function sharpLines(c) {
  c.lineJoin = 'miter';
  c.lineCap = 'square';
}

export const lerp = (a, b, t) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
export const centroid = pts => ({ x: (pts[0].x + pts[1].x + pts[2].x) / 3, y: (pts[0].y + pts[1].y + pts[2].y) / 3 });
const easeOut = t => 1 - (1 - t) * (1 - t);

/**
 * Draw a game's bin. `hint` outlines a dial one turn from a hex; `hideAbove` keeps play
 * below a lattice x (the menu's logo sits above it).
 */
export function renderFrame(game, animations, { hint = null, hideAbove = null } = {}) {
  const shake = animations ? animations.getScreenShake() : { x: 0, y: 0 };
  const { grid } = game;

  ctx.save();
  sharpLines(ctx);
  ctx.translate(shake.x, shake.y);
  ctx.fillStyle = skin.background;
  ctx.fillRect(-shake.x, -shake.y, viewW, viewH);

  drawBin(grid);
  ctx.save();
  if (hideAbove !== null) {
    ctx.beginPath();
    ctx.rect(0, toScreen({ x: hideAbove, y: 0 }).y, viewW, viewH);
    ctx.clip();
  }
  drawPieces(game);
  if (hint) drawHint(grid, hint);
  drawCursor(game);
  ctx.restore();
  if (animations) animations.drawParticles(ctx);
  ctx.restore();
}

/** Skin effects that sit over everything, HUD and menus included. */
export function drawOverlayEffects(c, w, h) {
  c.clearRect(0, 0, w, h);
  const { grain: grainAlpha, scanlines } = skin.effects;
  if (grainAlpha) {
    grain = grain || makeGrain(c);
    c.save();
    c.globalAlpha = grainAlpha;
    c.fillStyle = grain;
    c.fillRect(0, 0, w, h);
    c.restore();
  }
  if (scanlines) {
    c.save();
    c.fillStyle = rgba('#000000', scanlines);
    for (let y = 0; y < h; y += 3) c.fillRect(0, y, w, 1);
    c.restore();
  }
}

/** Speckled paper, as a repeating pattern. */
function makeGrain(c) {
  const tile = document.createElement('canvas');
  tile.width = tile.height = 128;
  const t = tile.getContext('2d');
  const image = t.createImageData(128, 128);
  for (let i = 0; i < image.data.length; i += 4) {
    const v = Math.random() < 0.5 ? 0 : 255;
    image.data[i] = image.data[i + 1] = image.data[i + 2] = v;
    image.data[i + 3] = Math.random() * 255;
  }
  t.putImageData(image, 0, 0);
  return c.createPattern(tile, 'repeat');
}

/** The empty bin: every cell outlined with a hairline, so the lattice is readable. */
function drawBin(grid) {
  const screen = p => toScreen(p, grid);
  tracePath(ctx, grid.binOutline().map(screen));
  ctx.fillStyle = skin.empty;
  ctx.fill();

  const wt = weights(getScale(grid));
  ctx.strokeStyle = rgba(skin.ink, wt.hairlineAlpha);
  ctx.lineWidth = wt.hairline;
  ctx.beginPath();
  for (const { r, c } of grid.cells) {
    const [a, b, d] = grid.cellVertices(r, c).map(screen);
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.lineTo(d.x, d.y);
    ctx.closePath();
  }
  ctx.stroke();
}

function drawPieces(game) {
  const { grid } = game;
  const screen = p => toScreen(p, grid);
  const scale = getScale(grid);
  const fallT = fallProgress(game);
  const hardCut = !!skin.effects.strobe;

  // The board already holds the turned dial; draw those six triangles rotated
  // back by the part of the 60° turn that hasn't played yet.
  let rotKeys = null, pivot = null, angle = 0;
  if (game.rotAnim) {
    const { k, j, dir, t } = game.rotAnim;
    rotKeys = new Set(dialCells(k, j).map(({ r, c }) => key(r, c)));
    pivot = screen(grid.vertexXY(k, j));
    angle = -dir * (Math.PI / 3) * (1 - easeOut(Math.min(1, t / ROTATE_TIME)));
  }

  for (const { r, c } of grid.cells) {
    const p = game.board.get(key(r, c));
    if (!p) continue;

    const center = grid.cellCenter(r, c);
    let dx = 0, dy = 0;
    if (p.from) {
      // Slide in from the cell it left at the last fall step
      const from = grid.cellCenter(p.from.r, p.from.c);
      dx = (from.x - center.x) * (1 - fallT);
      dy = (from.y - center.y) * (1 - fallT);
    }

    let inset = PIECE_INSET;
    let flash = 0;
    if (p.clearT > 0) {
      if (hardCut) continue; // gone on the frame it clears
      const progress = 1 - p.clearT / CLEAR_TIME;
      flash = progress < 0.3 ? 1 - progress / 0.3 * 0.4 : 0.6;
      if (progress > 0.3) inset *= 1 - (progress - 0.3) / 0.7;
    }

    const points = grid.cellVertices(r, c).map(v => screen({
      x: center.x + (v.x - center.x) * inset + dx,
      y: center.y + (v.y - center.y) * inset + dy,
    }));

    const rotating = rotKeys && rotKeys.has(key(r, c));
    if (rotating) {
      ctx.save();
      ctx.translate(pivot.x, pivot.y);
      ctx.rotate(angle);
      ctx.translate(-pivot.x, -pivot.y);
    }

    drawTriangle(ctx, points, p.color, scale, { flash, power: !!p.power });

    if (rotating) ctx.restore();
  }
}

/**
 * One piece: fill, its colour's mark, and any skin stroke. Shared by the
 * board and the HUD's colour row.
 * @param {{x,y}[]} points - the three corners, on screen
 */
export function drawTriangle(c, points, color, boardScale, { flash = 0, power = false } = {}) {
  const fill = skin.pieces[color];
  const wt = weights(boardScale);
  const { misregister, glow } = skin.effects;
  const offset = (misregister || 0) * boardScale;

  if (glow) {
    // Phosphor bloom: the same triangle, larger and faint, underneath
    const mid = centroid(points);
    tracePath(c, points.map(v => lerp(mid, v, 1.2)));
    c.fillStyle = rgba(fill, glow);
    c.fill();
  }

  if (offset) {
    // The second plate of a risograph print never quite lines up
    tracePath(c, points.map(v => ({ x: v.x - offset, y: v.y + offset * 0.6 })));
    c.fillStyle = rgba(fill, 0.35);
    c.fill();
  }

  tracePath(c, points);
  c.fillStyle = fill;
  c.fill();

  if (skin.stroke.outline) {
    c.strokeStyle = skin.stroke.outlineColor;
    c.lineWidth = wt[skin.stroke.outline];
    c.stroke();
  }

  drawMark(c, marks()[color], points, markColor(fill), wt.line);

  if (flash > 0) {
    tracePath(c, points);
    c.fillStyle = rgba(skin.ink, flash);
    c.fill();
  }
  if (power) {
    // Heavy pulsing edge, kept inside the triangle so it never touches a neighbour
    c.save();
    tracePath(c, points);
    c.clip();
    c.strokeStyle = rgba(markColor(fill), 0.5 + 0.4 * Math.sin(Date.now() * 0.008));
    c.lineWidth = wt.heavy * 2;
    c.stroke();
    c.restore();
  }
}

/**
 * The small mark inset in a piece, so colours can be told apart without
 * colour. Every mark has three-fold symmetry and is built from the triangle's
 * own corners, so it survives the dial's 60° turn without jumping.
 */
export function drawMark(c, kind, points, color, lineWidth) {
  const mid = centroid(points);
  // Inradius: distance from the centre to an edge (half the distance to a corner)
  const r = Math.hypot(points[0].x - mid.x, points[0].y - mid.y) / 2;
  const s = skin.stroke.markScale || 1;
  const toward = f => points.map(v => lerp(mid, v, f * s));

  c.save();
  c.fillStyle = color;
  c.strokeStyle = color;
  c.lineWidth = Math.min(lineWidth, r * 0.32);
  sharpLines(c);

  const dot = (p, radius) => {
    c.beginPath();
    c.arc(p.x, p.y, radius, 0, Math.PI * 2);
    c.fill();
  };
  const ring = radius => {
    c.beginPath();
    c.arc(mid.x, mid.y, radius, 0, Math.PI * 2);
    c.stroke();
  };

  switch (kind) {
    case 'dot':
      dot(mid, r * 0.34 * s);
      break;
    case 'ring':
      ring(r * 0.46 * s);
      break;
    case 'target':
      ring(r * 0.56 * s);
      dot(mid, r * 0.16 * s);
      break;
    case 'spokes':
      c.beginPath();
      for (const p of toward(0.42)) {
        c.moveTo(mid.x, mid.y);
        c.lineTo(p.x, p.y);
      }
      c.stroke();
      break;
    case 'frame':
      tracePath(c, toward(0.4));
      c.stroke();
      break;
    case 'trio':
      for (const p of toward(0.42)) dot(p, r * 0.17 * s);
      break;
    case 'corners':
      // A small solid triangle tucked into each corner, pointing out. Placed
      // without the mark scale, and capped, so they never reach the piece's edge.
      for (const p of points.map(v => lerp(mid, v, 0.52))) {
        const k = Math.min(0.22 * s, 0.28);
        tracePath(c, points.map(v => ({ x: p.x + (v.x - mid.x) * k, y: p.y + (v.y - mid.y) * k })));
        c.fill();
      }
      break;
    case 'tri':
      // Solid triangle pointing the other way
      tracePath(c, toward(-0.32));
      c.fill();
      break;
  }
  c.restore();
}

/** The dial: a hexagon around the vertex it turns. */
function drawCursor(game) {
  const { grid } = game;
  const { k, j } = game.cursor;
  const screen = p => toScreen(p, grid);
  const wt = weights(getScale(grid));

  tracePath(ctx, grid.dialOutline(k, j).map(screen));
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = wt.line;
  ctx.stroke();

  const center = screen(grid.vertexXY(k, j));
  ctx.beginPath();
  ctx.arc(center.x, center.y, Math.max(2, wt.line), 0, Math.PI * 2);
  ctx.fillStyle = skin.ink;
  ctx.fill();
}

/** A dial one turn from finishing a hex: a slow pulsing outline. */
function drawHint(grid, dial) {
  const wt = weights(getScale(grid));
  tracePath(ctx, grid.dialOutline(dial.k, dial.j).map(p => toScreen(p, grid)));
  ctx.strokeStyle = rgba(skin.ink, 0.4 + 0.3 * Math.sin(Date.now() * 0.005));
  ctx.lineWidth = wt.heavy;
  ctx.stroke();
}

// ===== Logo =====

/**
 * Every filled triangle in the logo as a (j, k) cell — column j left to right, row k
 * top down, rows half a side apart — with the letter it belongs to, plus the grid's
 * size in cells. A cell points right when j + k is even. Mirrors Marks.swift.
 */
function logoCells() {
  const { word, lines, gap, lineGap, glyphs } = logo();
  const words = lines ?? [word];
  const height = Math.max(...words.flatMap(w => [...w].map(ch => glyphs[ch].length)));
  let lineStep = height + lineGap;
  lineStep += lineStep % 2; // an even step keeps the next line's triangles pointing the same ways
  const lineCells = [];
  const widths = [];
  let letter = 0;
  words.forEach((w, lineIndex) => {
    const cells = [];
    let offset = 0;
    let width = 0;
    for (const ch of w) {
      const rows = glyphs[ch];
      rows.forEach((row, k) => {
        [...row].forEach((mark, j) => {
          if (mark === '#') cells.push({ j: j + offset, k: k + lineIndex * lineStep, letter });
        });
      });
      width = offset + Math.max(...rows.map(row => row.length));
      offset = width + gap;
      offset += offset % 2; // every glyph on an even column, so its triangles keep their directions
      letter++;
    }
    lineCells.push(cells);
    widths.push(width);
  });
  const columns = Math.max(...widths);
  // Centre each line, by an even shift so its triangles keep their directions
  const cells = lineCells.flatMap((line, i) => {
    const shift = Math.floor((columns - widths[i]) / 4) * 2;
    return line.map(cell => ({ ...cell, j: cell.j + shift }));
  });
  return { cells, columns, rows: (words.length - 1) * lineStep + height };
}

const LOGO_LIFT = 2; // half-rows the logo sits above the bin's middle, leaving the lower bowl for play

/** Where the logo's grid starts on a bin's half-size lattice: centred across and lifted toward the top. */
function logoOrigin(columns, rows) {
  const j0 = Math.trunc((4 * GRIDS.standard.size - columns) / 2);
  let k0 = Math.trunc(-(rows + 1) / 2) - LOGO_LIFT;
  if ((j0 + k0) % 2 !== 0) k0 -= 1;
  return { j0, k0 };
}

/** Where the bottom of the logo sits in a bin, in board sides below its middle: play stays below this. */
export function logoBottomInBin() {
  const { columns, rows } = logoCells();
  return (logoOrigin(columns, rows).k0 + rows + 1) / 4;
}

// Lit slots per letter: each letter shows one to three pieces among its ink triangles
const LOGO_SLOTS = 3;
const LOGO_FADE = 0.35;

/** A repeatable hash of two numbers, 0…1, so the logo's pieces look random but hold from frame to frame. */
function hash(a, b) {
  let h = Math.imul(a * 2654435761 + b | 0, 0x9E3779B1);
  h = Math.imul(h ^ (h >>> 15), 0x85EBCA77);
  h = Math.imul(h ^ (h >>> 13), 0xC2B2AE3D);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

/** What one letter's slot shows at time t: which triangle, which colour, and how far in (0…1). */
function logoSlot(letter, slot, t, hardCuts) {
  const seed = letter * LOGO_SLOTS + slot;
  // Each piece holds about five seconds; slot 0 runs back to back, the others rest between pieces
  const lit = 4.5 + hash(seed, 1);
  const period = slot === 0 ? lit : lit + 2 + hash(seed, 2) * 3;
  const shifted = t + hash(seed, 3) * period;
  const cycle = Math.floor(shifted / period);
  const s = shifted - cycle * period;
  if (s >= lit) return null;
  const amount = hardCuts ? 1 : Math.min(1, s / LOGO_FADE, (lit - s) / LOGO_FADE);
  return { pick: hash(seed, 10 + cycle), color: hash(seed, 20 + cycle), amount };
}

/** HEXGEN built from the game's triangles, laid into the menu's bin, with live pieces swapping in. */
export function drawLogoInBin(c, t) {
  const { cells, columns, rows } = logoCells();
  const { j0, k0 } = logoOrigin(columns, rows);
  const boardSide = getScale();
  const side = boardSide / 2;
  const colW = side * ROW_H;
  const originX = bin.x - (2 * GRIDS.standard.size - j0) * colW;
  const originY = bin.y + (k0 * side) / 2;

  const corners = ({ j, k }) => {
    const left = originX + j * colW;
    const right = left + colW;
    const top = originY + (k * side) / 2;
    return (j + k) % 2 === 0
      ? [{ x: left, y: top }, { x: left, y: top + side }, { x: right, y: top + side / 2 }]
      : [{ x: right, y: top }, { x: right, y: top + side }, { x: left, y: top + side / 2 }];
  };
  const scaled = (points, f) => {
    const mid = centroid(points);
    return points.map(v => lerp(mid, v, f));
  };

  // Colours that would vanish against the ink sit out
  const colors = skin.pieces.map((_, i) => i).filter(i => inkContrast(skin.pieces[i]) >= 1.6);

  const lit = new Map();
  if (colors.length) {
    const byLetter = new Map();
    cells.forEach((cell, i) => {
      if (!byLetter.has(cell.letter)) byLetter.set(cell.letter, []);
      byLetter.get(cell.letter).push(i);
    });
    for (const [letter, indices] of byLetter) {
      for (let slot = 0; slot < LOGO_SLOTS; slot++) {
        const choices = indices.filter((_, at) => at % LOGO_SLOTS === slot);
        const shown = choices.length ? logoSlot(letter, slot, t, !!skin.effects.strobe) : null;
        if (!shown) continue;
        lit.set(choices[Math.floor(shown.pick * choices.length)],
          { color: colors[Math.floor(shown.color * colors.length)], amount: shown.amount });
      }
    }
  }

  cells.forEach((cell, i) => {
    const points = scaled(corners(cell), PIECE_INSET);
    const state = lit.get(i);
    // The ink triangle gives way as the piece grows into its place
    tracePath(c, points);
    c.fillStyle = state ? rgba(skin.ink, 1 - state.amount) : skin.ink;
    c.fill();
    if (state) {
      c.save();
      c.globalAlpha = state.amount;
      drawTriangle(c, scaled(points, 0.8 + 0.2 * state.amount), state.color, side);
      c.restore();
    }
  });
}

/** Whether a point is on the logo's corner of the bin, for the hidden unlock taps. */
export function isOnMenuLogo(x, y) {
  const top = bin.y - bin.r * 0.75;
  return Math.abs(x - bin.x) <= bin.r * 0.8 && y >= top && y <= toScreen({ x: logoBottomInBin(), y: 0 }).y;
}

function inkContrast(hex) {
  const luminance = h => {
    const n = parseInt(h.slice(1), 16);
    const [r, g, b] = [n >> 16, (n >> 8) & 255, n & 255].map(v => {
      const c = v / 255;
      return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
    });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const [hi, lo] = [luminance(hex), luminance(skin.ink)].sort((a, b) => b - a);
  return (hi + 0.05) / (lo + 0.05);
}
