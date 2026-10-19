// hud.js — HUD overlay: score, mode, colours in play, rotate buttons, game over, pause

import { skin, copy, font, weights, rgba } from './skins.js';
import { drawTriangle, getScale, sharpLines, tracePath } from './renderer.js';

const TRACKING = 0.08; // extra letter spacing on one-word uppercase labels, in ems
const SECONDARY = 0.6; // opacity of secondary text; still the one ink colour

// On-screen rotation button positions (set during draw, read by input)
export const touchButtons = {
  rotateCCW: { x: 0, y: 0, radius: 0 },
  rotateCW: { x: 0, y: 0, radius: 0 },
  visible: false,
};

/** Lowercase text in one of the skin's fonts. */
export function drawText(ctx, text, x, y, { role = 'text', size = 14, alpha = 1, align = 'center', baseline = 'middle' } = {}) {
  ctx.font = font(role, size);
  ctx.fillStyle = rgba(skin.ink, alpha);
  ctx.textAlign = align;
  ctx.textBaseline = baseline;
  ctx.fillText(text, x, y);
}

/** A one-word uppercase label with a little extra letter spacing, drawn a letter at a time. */
export function drawLabel(ctx, text, x, y, { size = 14, alpha = 1, align = 'center', baseline = 'middle' } = {}) {
  ctx.font = font('display', size);
  ctx.fillStyle = rgba(skin.ink, alpha);
  ctx.textAlign = 'left';
  ctx.textBaseline = baseline;
  const gap = size * TRACKING;
  const widths = [...text].map(ch => ctx.measureText(ch).width);
  const total = widths.reduce((a, b) => a + b, 0) + gap * (widths.length - 1);
  let cx = align === 'center' ? x - total / 2 : align === 'right' ? x - total : x;
  [...text].forEach((ch, i) => {
    ctx.fillText(ch, cx, y);
    cx += widths[i] + gap;
  });
}

/**
 * Draw the HUD overlay onto the canvas.
 * @param {CanvasRenderingContext2D} ctx
 * @param {GameState} state
 * @param {number} width - Canvas width in CSS pixels
 * @param {number} height - Canvas height in CSS pixels
 */
export function drawHUD(ctx, state, width, height) {
  const text = copy();
  const scale = getScale();
  const wt = weights(scale);
  ctx.save();
  sharpLines(ctx);

  // Score — top-left, in fixed-width digits so it doesn't jitter as it climbs
  drawText(ctx, `${state.score}`, 20, 20, { role: 'digits', size: 24, align: 'left', baseline: 'top' });

  // Mode label — top-centre
  drawLabel(ctx, text.modes[state.mode].label, width / 2, 22, { size: 13, baseline: 'top' });

  // Sprint timer
  if (state.mode === 'sprint' && state.sprintTimeRemaining >= 0) {
    const secs = Math.ceil(state.sprintTimeRemaining / 1000);
    const clock = `${Math.floor(secs / 60)}:${(secs % 60).toString().padStart(2, '0')}`;
    drawText(ctx, clock, width / 2, 42, { role: 'digits', size: 18, baseline: 'top' });
  }

  // Colours in play — top-right, as pieces with their marks, tiled point-up and point-down
  const side = 18;
  const rowH = side * Math.sqrt(3) / 2;
  const top = 20;
  const right = width - 20 - side / 2;
  state.activeColors.forEach((color, i) => {
    const x = right - (state.activeColors.length - 1 - i) * (side / 2);
    const up = (state.activeColors.length - 1 - i) % 2 === 0;
    const corners = up
      ? [{ x, y: top }, { x: x + side / 2, y: top + rowH }, { x: x - side / 2, y: top + rowH }]
      : [{ x: x - side / 2, y: top }, { x: x + side / 2, y: top }, { x, y: top + rowH }];
    const mid = { x, y: top + rowH * (up ? 2 / 3 : 1 / 3) };
    drawTriangle(ctx, corners.map(p => ({ x: mid.x + (p.x - mid.x) * 0.9, y: mid.y + (p.y - mid.y) * 0.9 })), color, side);
  });

  // Hexes cleared counter
  drawText(ctx, `${text.hexes} ${state.hexesCleared}`, width - 20, 20 + rowH + 16, { size: 12, alpha: SECONDARY, align: 'right' });

  // On-screen rotation buttons: solid outlined triangles pointing in, toward the bin's bottom vertex
  const radius = Math.min(42, width * 0.09);
  const y = height - radius - 28;
  const margin = radius + 20;
  touchButtons.rotateCCW = { x: margin, y, radius };
  touchButtons.rotateCW = { x: width - margin, y, radius };
  drawRotateButton(ctx, margin, y, radius, -1, wt.line);
  drawRotateButton(ctx, width - margin, y, radius, 1, wt.line);
  touchButtons.visible = true;

  ctx.restore();
}

/**
 * A triangle centred on (x, y) pointing inward, toward the board: the
 * counter-clockwise button sits on the left and points right, the clockwise
 * one points left. A turn arrow inside shows which way it turns.
 */
function drawRotateButton(ctx, x, y, radius, dir, lineWidth) {
  const corners = [0, 1, 2].map(i => {
    const a = (dir > 0 ? Math.PI : 0) + i * (2 * Math.PI / 3);
    return { x: x + Math.cos(a) * radius, y: y + Math.sin(a) * radius };
  });
  tracePath(ctx, corners);
  ctx.fillStyle = skin.empty;
  ctx.fill();
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = lineWidth;
  ctx.stroke();

  // A near-full turn with a solid triangular arrowhead, sitting in the triangle's incircle
  const r = radius * 0.5 * 0.58;
  const gap = Math.PI * 0.4; // opening at the top, where the arrowhead points across
  const start = -Math.PI / 2 + dir * gap / 2;
  const end = start + dir * (2 * Math.PI - gap);
  ctx.beginPath();
  ctx.arc(x, y, r, start, end, dir < 0);
  ctx.stroke();

  const p = { x: x + Math.cos(end) * r, y: y + Math.sin(end) * r };
  const along = { x: -Math.sin(end) * dir, y: Math.cos(end) * dir }; // direction of travel
  const out = { x: Math.cos(end), y: Math.sin(end) };
  const head = Math.max(lineWidth * 2.8, r * 0.7);
  const back = { x: p.x - along.x * head * 0.25, y: p.y - along.y * head * 0.25 };
  ctx.beginPath();
  ctx.moveTo(p.x + along.x * head * 0.75, p.y + along.y * head * 0.75);
  ctx.lineTo(back.x + out.x * head * 0.6, back.y + out.y * head * 0.6);
  ctx.lineTo(back.x - out.x * head * 0.6, back.y - out.y * head * 0.6);
  ctx.closePath();
  ctx.fillStyle = skin.ink;
  ctx.fill();
}

function dim(ctx, width, height, alpha) {
  ctx.fillStyle = rgba(skin.background, alpha);
  ctx.fillRect(0, 0, width, height);
}

/**
 * Draw game over overlay.
 * @param {string[]} unlocked - ids of skins this game unlocked
 */
export function drawGameOver(ctx, state, width, height, isNewHighScore, unlocked = []) {
  const text = copy();
  dim(ctx, width, height, 0.88);

  const timeUp = state.mode === 'sprint' && state.sprintTimeRemaining === 0;
  const headline = state.won ? text.cleared : timeUp ? text.timeUp : text.binFull;
  drawText(ctx, headline, width / 2, height / 2 - 60, { role: 'display', size: 36 });
  drawText(ctx, `${state.score}`, width / 2, height / 2 - 10, { role: 'digits', size: 28 });

  let y = height / 2 + 25;
  if (isNewHighScore) {
    drawText(ctx, text.newBest, width / 2, y, { size: 16 });
    y += 26;
  }
  for (const id of unlocked) {
    drawText(ctx, text.unlocked.replace('%@', id), width / 2, y, { size: 16 });
    y += 26;
  }

  drawText(ctx, text.tapForMenu, width / 2, y + 20, { size: 13, alpha: SECONDARY });
}

/**
 * Draw pause overlay.
 */
export function drawPause(ctx, width, height) {
  const text = copy();
  dim(ctx, width, height, 0.75);
  drawText(ctx, text.paused, width / 2, height / 2, { role: 'display', size: 32 });
  drawText(ctx, text.tapToContinue, width / 2, height / 2 + 40, { size: 13, alpha: SECONDARY });
}
