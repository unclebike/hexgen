// hud.js — The in-game overlay on the canvas: score, colours, mode, callouts, pause, and the spinner
//
// Portrait, in order of weight: the board and the dial carry the screen; the
// score is the one big number, in the pocket under the bin away from the dial,
// with the colour progress beneath it; the mode and pause sit quietly in the top
// corners, and any callout between them. Landscape: the stats run down the sides.
// The stats take the side the spinner leaves free, so they swap with the hand.

import { skin, copy, font, weights, rgba, markColor, marks, SECONDARY } from './skins.js';
import {
  getScale, sharpLines, tracePath, isLandscape, spinnerPlace, statsBaseline, binFrame, toScreen, drawMark, lerp,
} from './renderer.js';
import { drawColorHex, drawSwatch, drawModifier, corners } from './icons.js';
import { dialCells, key, SQRT3 } from './grid.js';
import { upcomingColors } from './gamestate.js';
import { settings } from './settings.js';

const TRACKING = 0.08; // extra letter spacing on one-word uppercase labels, in ems
const PADDING = 20;
const PAUSE_SIZE = 44;
const SPIN_STEP = Math.PI / 3;
const SPIN_RETURN = 18; // how fast a let-go spinner settles, per second

// Where the controls are (set during draw, read by input)
export const hudZones = {
  pause: null,    // { x, y, w, h }
  spinner: null,  // { x, y, r, clockwiseOnly }
};

/** How far the finger has turned the spinner past the last whole step, in radians (clockwise positive). */
export const spinner = { spin: 0, held: false };

export function tickSpinner(dt) {
  if (!spinner.held) spinner.spin *= Math.exp(-SPIN_RETURN * dt);
}

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

/** Break text into lines no wider than maxWidth, in the current font. */
function wrap(ctx, text, maxWidth) {
  const lines = [];
  let line = '';
  for (const word of text.split(' ')) {
    const next = line ? `${line} ${word}` : word;
    if (line && ctx.measureText(next).width > maxWidth) {
      lines.push(line);
      line = word;
    } else {
      line = next;
    }
  }
  if (line) lines.push(line);
  return lines;
}

/** Draw the in-game overlay. `feed` is the game's CalloutFeed. */
export function drawHUD(ctx, game, width, height, feed) {
  ctx.save();
  sharpLines(ctx);
  hudZones.pause = null;

  const onLeft = settings.leftHanded;
  if (isLandscape()) drawSideColumns(ctx, game, width, height, feed, onLeft);
  else drawPortrait(ctx, game, width, height, feed, onLeft);
  drawSpinner(ctx, game);
  ctx.restore();
}

function drawPortrait(ctx, game, width, height, feed, onLeft) {
  const statsLeft = !onLeft;
  const align = statsLeft ? 'left' : 'right';
  const x = statsLeft ? PADDING : width - PADDING;

  // The mode (and a sprint's clock), small and quiet, and pause in the other corner
  drawModeBlock(ctx, game, x, PADDING, align, SECONDARY);
  drawPauseButton(ctx, statsLeft ? width - PADDING - PAUSE_SIZE : PADDING, PADDING - 8);

  // A callout between them, down to just short of the bin's top corner
  const headroom = Math.max(0, binFrame('play').y - PADDING - 8);
  drawCallout(ctx, feed, width / 2, PADDING, Math.max(120, width - 2 * (PADDING + 84)), 'center', headroom);

  // The score, and the colours beneath it, in the pocket under the bin
  const side = 28;
  const rows = colorRows(game, 4);
  const hexHeight = side * 2 / SQRT3;
  const coloursHeight = rows.length * hexHeight + (rows.length - 1) * side * 0.02;
  const bottom = height - PADDING - statsBaseline();
  drawColorHexes(ctx, game, rows, x, bottom - coloursHeight, side, align);

  const room = (width - 2 * PADDING) * 0.45;
  ctx.font = font('digits', 44);
  const scoreSize = Math.min(44, Math.floor(44 * room / Math.max(1, ctx.measureText(`${game.score}`).width)));
  drawText(ctx, `${game.score}`, x, bottom - coloursHeight - 10, { role: 'digits', size: scoreSize, align, baseline: 'bottom' });
}

function drawSideColumns(ctx, game, width, height, feed, onLeft) {
  const coloursLeft = !onLeft;
  let y = PADDING;
  drawText(ctx, `${game.score}`, PADDING, y, { role: 'digits', size: 24, align: 'left', baseline: 'top' });
  y += 34;
  y = drawModeBlock(ctx, game, PADDING, y, 'left', 1);

  const side = 22;
  const rows = colorRows(game, 4);
  const hexHeight = side * 2 / SQRT3;
  if (coloursLeft) {
    y += 8;
    drawColorHexes(ctx, game, rows, PADDING, y, side, 'left');
    y += rows.length * hexHeight + 4;
  }
  drawCallout(ctx, feed, PADDING, y + 4, 112, 'left', Math.max(60, height - y - 24));

  drawPauseButton(ctx, width - PADDING - PAUSE_SIZE, PADDING - 8);
  if (!coloursLeft) drawColorHexes(ctx, game, rows, width - PADDING, PADDING + PAUSE_SIZE + 4, side, 'right');
}

/** Each colour as a small hex, a row at a time. A big board's six sit three and three. */
function colorRows(game, columns) {
  const colors = game.colorHexes.map((_, i) => i);
  const across = Math.min(columns, Math.ceil(colors.length / 2));
  const rows = [];
  for (let i = 0; i < colors.length; i += across) rows.push(colors.slice(i, i + across));
  return rows;
}

function drawColorHexes(ctx, game, rows, x, y, side, align) {
  const stepX = side * 1.14;
  const stepY = side * 2 / SQRT3 * 0.98;
  rows.forEach((row, rowIndex) => {
    row.forEach((color, i) => {
      const left = align === 'left' ? x + i * stepX : x - (row.length - i) * stepX + side * 0.14;
      const c = { x: left + side / 2, y: y + rowIndex * stepY + side / SQRT3 };
      const count = game.colorHexes[color];
      const inPlay = game.activeColors.includes(color);
      drawColorHex(ctx, c, side, color, count, inPlay);
      if (inPlay && count > 6) {
        ctx.font = font('digits', 10);
        const w = ctx.measureText(`${count}`).width + 6;
        ctx.fillStyle = rgba(skin.background, 0.85);
        ctx.fillRect(c.x - w / 2, c.y - 7, w, 14);
        drawText(ctx, `${count}`, c.x, c.y, { role: 'digits', size: 10 });
      }
    });
  });
}

/** The mode, its clock, and a daily's strip. Returns the y under them. */
function drawModeBlock(ctx, game, x, y, align, alpha) {
  const text = copy();
  const label = game.daily ? text.daily.label : text.modes[game.mode].label;
  drawLabel(ctx, label, x, y, { size: 13, align, baseline: 'top', alpha });
  y += 18;
  if (game.sprintTimeRemaining !== null) {
    const seconds = Math.ceil(game.sprintTimeRemaining);
    const clock = `${Math.floor(seconds / 60)}:${(seconds % 60).toString().padStart(2, '0')}`;
    drawText(ctx, clock, x, y, { role: 'digits', size: 18, align, baseline: 'top', alpha });
    y += 24;
  }
  if (game.daily) y = drawDailyStrip(ctx, game, x, y, align, alpha);
  return y;
}

/** A daily's modifiers, each a symbol and its name (WANTED with the colour it wants), then the next few colours. */
function drawDailyStrip(ctx, game, x, y, align, alpha) {
  const text = copy().daily;
  const side = 14;
  const dir = align === 'left' ? 1 : -1;
  const place = (at, w) => (align === 'left' ? at : at - w);
  ctx.save();
  ctx.globalAlpha = alpha;
  for (const modifier of game.daily.modifiers) {
    ctx.save();
    ctx.translate(place(x, side), y);
    drawModifier(ctx, modifier, side, side);
    ctx.restore();
    const title = text.modifiers[modifier].title;
    let at = x + dir * (side + 5);
    drawText(ctx, title, at, y + side / 2, { size: 11, align });
    at += dir * (ctx.measureText(title).width + 5);
    if (modifier === 'wanted' && game.wantedColor !== null) drawSwatch(ctx, place(at, side), y, side, game.wantedColor);
    y += side + 4;
  }
  const upcoming = upcomingColors(game, 3);
  if (upcoming.length) {
    drawText(ctx, text.next, x, y + side / 2, { size: 10, align, alpha: SECONDARY });
    let at = x + dir * (ctx.measureText(text.next).width + 4);
    upcoming.forEach((color, i) => {
      drawSwatch(ctx, place(at, side), y, side, color, i === 0 ? 1 : 0.6);
      at += dir * (side + 3);
    });
    y += side + 4;
  }
  ctx.restore();
  return y;
}

/** What just shifted in play, faded in and out beside the bin. Where there's no height for it, just the title. */
function drawCallout(ctx, feed, x, y, maxWidth, align, maxHeight) {
  const callout = feed.current;
  if (!callout) return;
  ctx.save();
  ctx.globalAlpha = feed.opacity;

  const swatch = 14;
  const arrow = 18;
  ctx.font = font('display', 15);
  const titleWidth = ctx.measureText(callout.title).width;
  const extra = callout.colors.length ? 6 + callout.colors.length * swatch + (callout.colors.length - 1) * arrow : 0;
  const titleX = align === 'center' ? x - (titleWidth + extra) / 2 : x;
  drawText(ctx, callout.title, titleX, y, { role: 'display', size: 15, align: 'left', baseline: 'top' });
  let at = titleX + titleWidth + 6;
  callout.colors.forEach((color, i) => {
    if (i > 0) {
      const mid = y + 9;
      ctx.strokeStyle = rgba(skin.ink, SECONDARY);
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.moveTo(at + 3, mid);
      ctx.lineTo(at + 13, mid);
      ctx.moveTo(at + 9, mid - 4);
      ctx.lineTo(at + 13, mid);
      ctx.lineTo(at + 9, mid + 4);
      ctx.stroke();
      at += arrow;
    }
    drawColorHex(ctx, { x: at + swatch / 2, y: y + 9 }, swatch, color, 6, true);
    at += swatch;
  });

  if (callout.detail) {
    ctx.font = font('text', 12);
    const lines = wrap(ctx, callout.detail, maxWidth);
    const lineHeight = 15;
    if (22 + lines.length * lineHeight <= maxHeight) {
      lines.forEach((line, i) => {
        drawText(ctx, line, x, y + 22 + i * lineHeight, { size: 12, alpha: SECONDARY, align, baseline: 'top' });
      });
    }
  }
  ctx.restore();
}

/** Two bars, at the line weight. */
function drawPauseButton(ctx, x, y) {
  hudZones.pause = { x, y, w: PAUSE_SIZE, h: PAUSE_SIZE };
  const barW = Math.max(2, weights(getScale()).line);
  const cx = x + PAUSE_SIZE / 2;
  const cy = y + PAUSE_SIZE / 2;
  ctx.fillStyle = rgba(skin.ink, SECONDARY);
  ctx.fillRect(cx - 3 - barW, cy - 8, barW, 16);
  ctx.fillRect(cx + 3, cy - 8, barW, 16);
}

/**
 * The dial itself as a control: a hex of six triangles showing the pieces under the
 * dial on the board. Drag around it to turn, either way; a tap turns it forward.
 */
function drawSpinner(ctx, game) {
  const place = spinnerPlace();
  hudZones.spinner = null;
  if (game.phase === 'gameover' || place.r < 24) return;
  const clockwiseOnly = game.modifiers.has('oneWay');
  // The outline's mitred corners reach past the path, so pull the drawing in to keep it whole
  const radius = place.r / (1 + weights(1).line * 0.6);
  hudZones.spinner = { x: place.x, y: place.y, r: radius, clockwiseOnly };

  const { grid, cursor, board } = game;
  const center = toScreen(grid.vertexXY(cursor.k, cursor.j), grid);
  const slots = new Array(6).fill(null);
  for (const { r, c } of dialCells(cursor.k, cursor.j)) {
    const p = board.get(key(r, c));
    if (!p) continue;
    // Which way this cell lies from the dial's centre, on screen, picks its slot
    const at = toScreen(grid.cellCenter(r, c), grid);
    const angle = Math.atan2(center.y - at.y, at.x - center.x);
    slots[((Math.round(angle / SPIN_STEP) % 6) + 6) % 6] = p;
  }

  const wt = weights(radius);
  ctx.save();
  ctx.translate(place.x, place.y);
  ctx.rotate(spinner.spin);
  const corner = degrees => {
    const a = degrees * Math.PI / 180;
    return { x: radius * Math.cos(a), y: -radius * Math.sin(a) };
  };
  slots.forEach((p, k) => {
    const mid = k * 60;
    const origin = { x: 0, y: 0 };
    const whole = [origin, corner(mid - 30), corner(mid + 30)];
    const heart = { x: (whole[1].x + whole[2].x) / 3, y: (whole[1].y + whole[2].y) / 3 };
    const points = whole.map(v => lerp(heart, v, 0.9));
    tracePath(ctx, points);
    if (!p) {
      ctx.fillStyle = skin.empty;
      ctx.fill();
      ctx.strokeStyle = rgba(skin.ink, 0.15);
      ctx.lineWidth = 1;
      ctx.stroke();
      return;
    }
    const fill = skin.pieces[p.color];
    ctx.fillStyle = fill;
    ctx.fill();
    if (skin.stroke.outline) {
      ctx.strokeStyle = skin.stroke.outlineColor;
      ctx.lineWidth = wt[skin.stroke.outline];
      ctx.stroke();
    }
    drawMark(ctx, marks()[p.color], points, markColor(fill), wt.line);
  });
  tracePath(ctx, corners({ x: 0, y: 0 }, radius));
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = wt.line;
  ctx.stroke();
  ctx.beginPath();
  ctx.arc(0, 0, Math.max(3, wt.line), 0, Math.PI * 2);
  ctx.fillStyle = skin.ink;
  ctx.fill();
  ctx.restore();
}

/** A daily counting back in after a pause, over the board so the player can find their place. */
export function drawCountdown(ctx, count, width, height) {
  ctx.fillStyle = rgba(skin.background, 0.35);
  ctx.fillRect(0, 0, width, height);
  drawText(ctx, `${count}`, width / 2, height / 2, { role: 'digits', size: 72 });
}
