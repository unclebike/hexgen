// renderer.js — Canvas drawing: the bin, falling triangles, the dial, and effects

import { CELLS, SIZE, ROW_H, key, cellVertices, cellCenter, vertexXY, dialOutline } from './grid.js';
import { COLOR_PALETTE, EMPTY_COLOR, BOARD_BG } from './progression.js';
import { FALL_STEP, CLEAR_TIME, ROTATE_TIME } from './gamestate.js';

const TOP_MARGIN = 72;     // room for the score line
const BOTTOM_MARGIN = 100; // room for the rotate buttons
const PIECE_INSET = 0.9;   // leave a hairline gap between triangles

let canvas, ctx;
let scale = 30; // pixels per triangle side
let originX = 0, originY = 0;

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

// Lattice x runs down the screen and lattice y runs right to left
export const toScreen = ({ x, y }) => ({ x: originX - y * scale, y: originY + x * scale });
export const toUnit = (px, py) => ({ x: (py - originY) / scale, y: -(px - originX) / scale });

function tracePath(points) {
  ctx.beginPath();
  ctx.moveTo(points[0].x, points[0].y);
  for (let i = 1; i < points.length; i++) ctx.lineTo(points[i].x, points[i].y);
  ctx.closePath();
}

const easeOut = t => 1 - (1 - t) * (1 - t);

export function renderFrame(game, animations) {
  const w = canvas.width / (window.devicePixelRatio || 1);
  const h = canvas.height / (window.devicePixelRatio || 1);
  const shake = animations.getScreenShake();

  ctx.save();
  ctx.translate(shake.x, shake.y);
  ctx.fillStyle = BOARD_BG;
  ctx.fillRect(-shake.x, -shake.y, w, h);

  drawBin();
  drawPieces(game);
  drawCursor(game);
  animations.drawParticles(ctx);

  ctx.restore();
}

/** The empty bin: every cell outlined faintly, so the lattice is readable. */
function drawBin() {
  tracePath(binOutline());
  ctx.fillStyle = EMPTY_COLOR;
  ctx.fill();

  ctx.strokeStyle = 'rgba(255, 255, 255, 0.06)';
  ctx.lineWidth = 1;
  for (const { r, c } of CELLS) {
    tracePath(cellVertices(r, c).map(toScreen));
    ctx.stroke();
  }
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

  // The board already holds the turned dial; draw the turned triangles rotated
  // back by the part of the 60° turn that hasn't played yet.
  let rotPieces = null, pivot = null, angle = 0;
  if (game.rotAnim) {
    const { k, j, dir, t } = game.rotAnim;
    rotPieces = game.rotAnim.pieces;
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
      const progress = 1 - p.clearT / CLEAR_TIME;
      flash = progress < 0.3 ? 1 - progress / 0.3 * 0.4 : 0.6;
      if (progress > 0.3) inset *= 1 - (progress - 0.3) / 0.7;
    }

    const points = cellVertices(r, c).map(v => toScreen({
      x: center.x + (v.x - center.x) * inset + dx,
      y: center.y + (v.y - center.y) * inset + dy,
    }));

    const rotating = rotPieces && rotPieces.has(p);
    if (rotating) {
      ctx.save();
      ctx.translate(pivot.x, pivot.y);
      ctx.rotate(angle);
      ctx.translate(-pivot.x, -pivot.y);
    }

    tracePath(points);
    ctx.fillStyle = COLOR_PALETTE[p.color];
    ctx.fill();
    if (flash > 0) {
      ctx.fillStyle = `rgba(255, 255, 255, ${flash})`;
      ctx.fill();
    }
    if (p.power) {
      ctx.strokeStyle = `rgba(255, 255, 255, ${0.5 + 0.4 * Math.sin(Date.now() * 0.008)})`;
      ctx.lineWidth = 2.5;
      ctx.stroke();
    }

    if (rotating) ctx.restore();
  }
}

/** The dial: a hexagon around the vertex it turns. */
function drawCursor(game) {
  const { k, j } = game.cursor;
  const outline = dialOutline(k, j).map(toScreen);

  tracePath(outline);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.08)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.85)';
  ctx.lineWidth = 2.5;
  ctx.stroke();

  const center = toScreen(vertexXY(k, j));
  ctx.beginPath();
  ctx.arc(center.x, center.y, Math.max(2.5, scale * 0.08), 0, Math.PI * 2);
  ctx.fillStyle = 'white';
  ctx.fill();
}
