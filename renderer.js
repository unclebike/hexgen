// renderer.js — Canvas drawing: the bin, falling triangles, the dial, marks, the logo, and skin effects

import { CELLS, SIZE, ROW_H, key, cellVertices, cellCenter, vertexXY, dialCells, dialOutline } from './grid.js';
import { FALL_STEP, CLEAR_TIME, ROTATE_TIME } from './gamestate.js';
import { skin, weights, rgba, markColor, marks, logo } from './skins.js';

const TOP_MARGIN = 72;     // room for the score line
const BOTTOM_MARGIN = 100; // room for the rotate buttons
const PIECE_INSET = 0.9;   // keep a gap between triangles, so the board reads as tiles

let canvas, ctx;
let scale = 30; // pixels per triangle side
let originX = 0, originY = 0;
let grain = null; // riso paper texture, made on first use

export function initRenderer(canvasEl) {
  canvas = canvasEl;
  ctx = canvas.getContext('2d');
  resize();
  return { canvas, ctx };
}

/** Fit the bin to the viewport. */
export function resize() {
  const dpr = window.devicePixelRatio || 1;
  const w = window.innerWidth;
  const h = window.innerHeight;
  canvas.width = w * dpr;
  canvas.height = h * dpr;
  canvas.style.width = w + 'px';
  canvas.style.height = h + 'px';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  // The lattice is drawn turned 90°, so the bin stands on a vertex:
  // it is 2·SIZE·ROW_H wide and 2·SIZE tall on screen
  const availW = w * 0.94;
  const availH = Math.max(100, h - TOP_MARGIN - BOTTOM_MARGIN);
  scale = Math.min(availW / (2 * SIZE * ROW_H), availH / (2 * SIZE));
  originX = w / 2;
  originY = TOP_MARGIN + availH / 2;
}

/** Pixels per triangle side. Line weights everywhere are sized from this. */
export const getScale = () => scale;

// Lattice x runs down the screen and lattice y runs right to left
export const toScreen = ({ x, y }) => ({ x: originX - y * scale, y: originY + x * scale });
export const toUnit = (px, py) => ({ x: (py - originY) / scale, y: -(px - originX) / scale });

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

const easeOut = t => 1 - (1 - t) * (1 - t);
const lerp = (a, b, t) => ({ x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t });
const centroid = pts => ({ x: (pts[0].x + pts[1].x + pts[2].x) / 3, y: (pts[0].y + pts[1].y + pts[2].y) / 3 });

export function renderFrame(game, animations) {
  const w = canvas.width / (window.devicePixelRatio || 1);
  const h = canvas.height / (window.devicePixelRatio || 1);
  const shake = animations.getScreenShake();

  ctx.save();
  sharpLines(ctx);
  ctx.translate(shake.x, shake.y);
  ctx.fillStyle = skin.background;
  ctx.fillRect(-shake.x, -shake.y, w, h);

  drawBin();
  drawPieces(game);
  drawCursor(game);
  animations.drawParticles(ctx);

  ctx.restore();
}

/** Skin effects that sit over everything, HUD included. Call last. */
export function drawOverlayEffects(c, w, h) {
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
function drawBin() {
  tracePath(ctx, binOutline());
  ctx.fillStyle = skin.empty;
  ctx.fill();

  const wt = weights(scale);
  ctx.strokeStyle = rgba(skin.ink, wt.hairlineAlpha);
  ctx.lineWidth = wt.hairline;
  ctx.beginPath();
  for (const { r, c } of CELLS) {
    const [a, b, d] = cellVertices(r, c).map(toScreen);
    ctx.moveTo(a.x, a.y);
    ctx.lineTo(b.x, b.y);
    ctx.lineTo(d.x, d.y);
    ctx.closePath();
  }
  ctx.stroke();
}

function binOutline() {
  const s = SIZE;
  return [
    { x: s, y: 0 }, { x: s / 2, y: s * ROW_H }, { x: -s / 2, y: s * ROW_H },
    { x: -s, y: 0 }, { x: -s / 2, y: -s * ROW_H }, { x: s / 2, y: -s * ROW_H },
  ].map(toScreen);
}

function drawPieces(game) {
  const fallT = Math.min(1, game.fallTimer / FALL_STEP);
  const hardCut = !!skin.effects.strobe;

  // The board already holds the turned dial; draw those six triangles rotated
  // back by the part of the 60° turn that hasn't played yet.
  let rotKeys = null, pivot = null, angle = 0;
  if (game.rotAnim) {
    const { k, j, dir, t } = game.rotAnim;
    rotKeys = new Set(dialCells(k, j).map(({ r, c }) => key(r, c)));
    pivot = toScreen(vertexXY(k, j));
    angle = -dir * (Math.PI / 3) * (1 - easeOut(Math.min(1, t / ROTATE_TIME)));
  }

  for (const { r, c } of CELLS) {
    const p = game.board.get(key(r, c));
    if (!p) continue;

    const center = cellCenter(r, c);
    let dx = 0, dy = 0;
    if (p.from) {
      // Slide in from the cell it left at the last fall step
      const from = cellCenter(p.from.r, p.from.c);
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

    const points = cellVertices(r, c).map(v => toScreen({
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
  const { k, j } = game.cursor;
  const wt = weights(scale);

  tracePath(ctx, dialOutline(k, j).map(toScreen));
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = wt.line;
  ctx.stroke();

  const center = toScreen(vertexXY(k, j));
  ctx.beginPath();
  ctx.arc(center.x, center.y, Math.max(2, wt.line), 0, Math.PI * 2);
  ctx.fillStyle = skin.ink;
  ctx.fill();
}

// ===== Logo =====

/**
 * Every filled triangle in the logo as a (j, k) cell — column j left to right, row k
 * top down, rows half a side apart — on the board's sideways lattice, plus the grid's
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
  words.forEach((w, lineIndex) => {
    const cells = [];
    let offset = 0;
    let width = 0;
    for (const letter of w) {
      const rows = glyphs[letter];
      rows.forEach((row, k) => {
        [...row].forEach((mark, j) => {
          if (mark === '#') cells.push({ j: j + offset, k: k + lineIndex * lineStep });
        });
      });
      width = offset + Math.max(...rows.map(row => row.length));
      offset = width + gap;
      offset += offset % 2; // every glyph on an even column, so its triangles keep their directions
    }
    lineCells.push(cells);
    widths.push(width);
  });
  const columns = Math.max(...widths);
  // Centre each line, by an even shift so its triangles keep their directions
  const cells = lineCells.flatMap((line, i) => {
    const shift = Math.floor((columns - widths[i]) / 4) * 2;
    return line.map(({ j, k }) => ({ j: j + shift, k }));
  });
  return { cells, columns, rows: (words.length - 1) * lineStep + height };
}

/**
 * HEXGEN, built from the game's triangles, centred on (cx, cy).
 * Returns the height drawn, in pixels.
 */
export function drawLogo(c, cx, cy, maxWidth) {
  const { cells, columns, rows } = logoCells();
  const side = Math.min(maxWidth / (columns * ROW_H), 26);
  const colW = side * ROW_H;
  const width = columns * colW;
  const height = ((rows + 1) * side) / 2;
  const left0 = cx - width / 2;
  const top0 = cy - height / 2;
  c.fillStyle = skin.ink;
  for (const { j, k } of cells) {
    const left = left0 + j * colW;
    const right = left + colW;
    const top = top0 + (k * side) / 2;
    const corners = (j + k) % 2 === 0
      ? [{ x: left, y: top }, { x: left, y: top + side }, { x: right, y: top + side / 2 }]
      : [{ x: right, y: top }, { x: right, y: top + side }, { x: left, y: top + side / 2 }];
    const mid = centroid(corners);
    tracePath(c, corners.map(v => lerp(mid, v, PIECE_INSET)));
    c.fill();
  }
  return height;
}
