// icons.js — Drawn symbols: the menu's games, the daily's modifiers, setup and how-to art
//
// Drawn in the board's own terms: hexes standing on a corner, their six
// triangles drawn apart, each piece in its skin colour with its mark on top, and
// ink lines in the brand's weights. Every symbol reads by shape alone, so mono
// and colour-blind players lose nothing; colours only add. Mirrors MenuIcon and
// ModifierIcons.swift. Sizes are CSS pixels; each call draws into (0, 0, w, h).

import { SQRT3, Grid } from './grid.js';
import { skin, weights, rgba, markColor, marks, SECONDARY } from './skins.js';
import { tracePath, sharpLines, drawMark, lerp, centroid } from './renderer.js';

const ART_GRID = new Grid(2); // the how-to's little bin
const LINE_WEIGHT = () => weights(1).line;
const scaled = (points, f) => {
  const mid = centroid(points);
  return points.map(v => lerp(mid, v, f));
};

/** A hex standing on a corner, like a dial on the board, as its six corners. */
export function corners(c, r) {
  return Array.from({ length: 6 }, (_, k) => {
    const a = (30 + k * 60) * Math.PI / 180;
    return { x: c.x + r * Math.cos(a), y: c.y - r * Math.sin(a) };
  });
}

/** The hex's six triangles, clockwise from the top, drawn apart like pieces. */
function triangles(c, r) {
  return Array.from({ length: 6 }, (_, k) => {
    const mid = (60 - k * 60) * Math.PI / 180;
    const at = a => ({ x: c.x + r * Math.cos(a), y: c.y - r * Math.sin(a) });
    return scaled([c, at(mid + Math.PI / 6), at(mid - Math.PI / 6)], 0.86);
  });
}

/** The largest radius that fits `across` hex widths and `down` hex heights, pulled in so corners aren't clipped. */
function radiusIn(w, h, across = 1, down = 1) {
  return Math.min(w / (SQRT3 * across), h / (2 * down)) / (1 + LINE_WEIGHT() * 0.6);
}

/** An equilateral triangle centred on c, pointing up or down. */
function triangle(c, side, up) {
  const height = side * SQRT3 / 2;
  const tip = up ? -2 * height / 3 : 2 * height / 3;
  const base = up ? height / 3 : -height / 3;
  return [{ x: c.x, y: c.y + tip }, { x: c.x + side / 2, y: c.y + base }, { x: c.x - side / 2, y: c.y + base }];
}

const rotated = (points, angle, c) => points.map(p => {
  const dx = p.x - c.x, dy = p.y - c.y;
  return { x: c.x + dx * Math.cos(angle) - dy * Math.sin(angle), y: c.y + dx * Math.sin(angle) + dy * Math.cos(angle) };
});

function outline(ctx, c, r, { width = weights(r).line, opacity = 1 } = {}) {
  tracePath(ctx, corners(c, r));
  ctx.strokeStyle = rgba(skin.ink, opacity);
  ctx.lineWidth = width;
  ctx.stroke();
}

function line(ctx, a, b, width, opacity = 1) {
  ctx.beginPath();
  ctx.moveTo(a.x, a.y);
  ctx.lineTo(b.x, b.y);
  ctx.strokeStyle = rgba(skin.ink, opacity);
  ctx.lineWidth = width;
  ctx.stroke();
}

function circle(ctx, c, r) {
  ctx.beginPath();
  ctx.arc(c.x, c.y, r, 0, Math.PI * 2);
}

/** A piece: its colour, its mark on top, and with `glow` the power piece's band inside its edge. */
function piece(ctx, points, color, scale, { opacity = 1, glow = false, glowWidth = null } = {}) {
  const fill = skin.pieces[color];
  const wt = weights(scale);
  ctx.save();
  ctx.globalAlpha = opacity;
  tracePath(ctx, points);
  ctx.fillStyle = fill;
  ctx.fill();
  drawMark(ctx, marks()[color], points, markColor(fill), wt.line);
  if (glow) {
    ctx.save();
    tracePath(ctx, points);
    ctx.clip();
    ctx.strokeStyle = rgba(markColor(fill), 0.9);
    ctx.lineWidth = (glowWidth ?? wt.heavy) * 2;
    ctx.stroke();
    ctx.restore();
  }
  ctx.restore();
}

/** A whole hex of pieces; `color` picks each triangle's colour, clockwise from the top. */
function hex(ctx, c, r, color, options = {}) {
  triangles(c, r).forEach((points, k) => piece(ctx, points, color(k), r, options));
}

/** An ink arc round c from a0 to a1 (radians, y down), ending in a solid arrowhead. */
function turn(ctx, c, radius, a0, a1, width) {
  const head = width * 2.4;
  const direction = a1 > a0 ? 1 : -1;
  const end = a1 - direction * (head * 0.7 / radius);
  ctx.save();
  ctx.lineCap = 'butt';
  ctx.beginPath();
  ctx.arc(c.x, c.y, radius, a0, end, direction < 0);
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = width;
  ctx.stroke();
  ctx.restore();
  const tip = { x: c.x + Math.cos(a1) * radius, y: c.y + Math.sin(a1) * radius };
  const back = { x: c.x + Math.cos(end) * radius, y: c.y + Math.sin(end) * radius };
  const length = Math.max(0.001, Math.hypot(tip.x - back.x, tip.y - back.y));
  const ux = (tip.x - back.x) / length, uy = (tip.y - back.y) / length;
  tracePath(ctx, [
    { x: tip.x + ux * head * 0.25, y: tip.y + uy * head * 0.25 },
    { x: back.x - uy * head * 0.6, y: back.y + ux * head * 0.6 },
    { x: back.x + uy * head * 0.6, y: back.y - ux * head * 0.6 },
  ]);
  ctx.fillStyle = skin.ink;
  ctx.fill();
}

// ===== The HUD's colours =====

/** One colour's hex: it fills a triangle per hex cleared; a colour not yet in play is a faint outline. */
export function drawColorHex(ctx, c, width, color, count, inPlay) {
  const r = width / SQRT3 / (1 + LINE_WEIGHT() * 0.6);
  const wt = weights(r);
  const fill = skin.pieces[color];
  triangles(c, r).forEach((points, k) => {
    if (inPlay && k < count) piece(ctx, points, color, r);
    else if (inPlay) {
      tracePath(ctx, points);
      ctx.fillStyle = skin.empty;
      ctx.fill();
    }
  });
  tracePath(ctx, corners(c, r));
  if (inPlay) {
    ctx.strokeStyle = fill;
    ctx.lineWidth = wt.line;
  } else {
    ctx.strokeStyle = rgba(skin.ink, 0.14);
    ctx.lineWidth = weights(1).hairline;
  }
  ctx.stroke();
}

/** One piece colour as a single triangle with its mark, for naming a colour in the HUD. */
export function drawSwatch(ctx, x, y, size, color, opacity = 1) {
  const side = Math.min(size, size * 2 / SQRT3);
  piece(ctx, triangle({ x: x + size / 2, y: y + size / 2 + side * SQRT3 / 12 }, side, true), color, side / 2, { opacity });
}

// ===== Game symbols =====

/** SPECTRUM: one hex of six different colours. */
function spectrum(ctx, w, h) {
  hex(ctx, { x: w / 2, y: h / 2 }, radiusIn(w, h), k => k);
}

/** ENDLESS: a row of cleared hexes running on out of the frame, fading as they go. */
function endless(ctx, w, h) {
  const r = radiusIn(w, h, 2.75);
  const step = SQRT3 * r * 1.08;
  [1, 0.5, 0.2].forEach((opacity, i) => {
    hex(ctx, { x: SQRT3 / 2 * r + i * step, y: h / 2 }, r, () => i, { opacity });
  });
}

/** SPRINT: a hex of one colour at speed, trailing lines behind it. */
function sprint(ctx, w, h) {
  const r = radiusIn(w, h);
  const c = { x: w - SQRT3 / 2 * r * 1.06, y: h / 2 };
  hex(ctx, c, r, () => 3);
  const width = weights(r).heavy;
  const trail = c.x - SQRT3 / 2 * r - width * 1.5;
  for (const [dy, length] of [[-0.5, 0.55], [0, 0.85], [0.5, 0.55]]) {
    const y = c.y + dy * r;
    line(ctx, { x: Math.max(width, trail - length * r * 1.4), y }, { x: trail, y }, width);
  }
}

/** The Daily Dial: a calendar page with today's hex on it, the days before stacked behind. */
function dailyIcon(ctx, w, h, day) {
  const count = Math.max(1, marks().length);
  const color = ((day % count) + count) % count; // walks through every colour, one a day
  const height = h * 0.94;
  const width = Math.min(w * 0.62, height * 0.92);
  const wt = weights(height * 0.5);
  const page = { x: (w - width) / 2 + width * 0.08, y: (h - height) / 2 + wt.line / 2, w: width, h: height - wt.line };
  [0.25, 0.5].forEach((fade, i) => {
    const offset = (2 - i) * width * 0.14;
    const back = [page.x - offset, page.y + offset * 0.3, page.w, page.h - offset * 0.6];
    ctx.fillStyle = skin.background;
    ctx.fillRect(...back);
    ctx.strokeStyle = rgba(skin.ink, fade);
    ctx.lineWidth = wt.line;
    ctx.strokeRect(...back);
  });
  ctx.fillStyle = skin.background;
  ctx.fillRect(page.x, page.y, page.w, page.h);
  const band = page.h * 0.24;
  ctx.fillStyle = skin.ink;
  ctx.fillRect(page.x, page.y, page.w, band);
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = wt.line;
  ctx.strokeRect(page.x, page.y, page.w, page.h);
  const bodyH = page.h - band;
  const r = Math.min(page.w / SQRT3, bodyH / 2) * 0.78;
  hex(ctx, { x: page.x + page.w / 2, y: page.y + band + bodyH / 2 }, r, () => color);
}

// ===== Modifiers =====

const MODIFIER_ICONS = {
  /** OVERTIME: a clock running round, a hex at the hand's tip feeding it time. */
  overtime(ctx, w, h) {
    const r = Math.min(w, h) / 2 * 0.74;
    const c = { x: w / 2 - r * 0.16, y: h / 2 + r * 0.16 };
    const wt = weights(r);
    const start = -Math.PI / 2;
    ctx.beginPath();
    ctx.moveTo(c.x, c.y);
    ctx.arc(c.x, c.y, r, start, start + 2 * Math.PI * 0.62);
    ctx.closePath();
    ctx.fillStyle = skin.pieces[1];
    ctx.fill();
    circle(ctx, c, r);
    ctx.strokeStyle = skin.ink;
    ctx.lineWidth = wt.line;
    ctx.stroke();
    const hand = -Math.PI / 2 + 2 * Math.PI * 0.15;
    line(ctx, c, { x: c.x + Math.cos(hand) * r * 0.82, y: c.y + Math.sin(hand) * r * 0.82 }, wt.heavy * 0.8);
    circle(ctx, c, r * 0.12);
    ctx.fillStyle = skin.ink;
    ctx.fill();
    const hr = r * 0.52;
    const hc = { x: c.x + Math.cos(hand) * r * 1.02, y: c.y + Math.sin(hand) * r * 1.02 };
    tracePath(ctx, corners(hc, hr * 1.2));
    ctx.fillStyle = skin.background;
    ctx.fill();
    hex(ctx, hc, hr, () => 0);
  },

  /** DOWNPOUR: two triangles falling side by side, rain streaks above them. */
  downpour(ctx, w, h) {
    const s = Math.min(w * 0.46, h * 0.5);
    const height = s * SQRT3 / 2;
    const mid = { x: w / 2, y: h - height * 0.62 - s * 0.08 };
    const gap = s * 0.1;
    const wt = weights(s);
    [-(s + gap) / 2, (s + gap) / 2].forEach((dx, i) => {
      const c = { x: mid.x + dx, y: mid.y };
      piece(ctx, triangle(c, s, false), [2, 1][i], s);
      const top = c.y - height / 3 - wt.heavy * 1.4;
      for (const [sx, length] of [[-0.3, 0.55], [0.3, 0.9]]) {
        const x = c.x + sx * s * (i === 0 ? 1 : -1);
        line(ctx, { x, y: top - length * height * 0.9 }, { x, y: top }, wt.line * 1.3);
      }
    });
  },

  /** POWER SURGE: a hex whose every triangle glows, power pieces all round. */
  powerSurge(ctx, w, h) {
    const c = { x: w / 2, y: h / 2 };
    const r = radiusIn(w, h) * 0.78;
    const wt = weights(r);
    hex(ctx, c, r, k => [4, 0][k % 2], { glow: true, glowWidth: wt.line });
    for (const corner of corners(c, r)) {
      const dx = corner.x - c.x, dy = corner.y - c.y;
      line(ctx, { x: c.x + dx * 1.12, y: c.y + dy * 1.12 }, { x: c.x + dx * 1.3, y: c.y + dy * 1.3 }, wt.line);
    }
  },

  /** JUNKYARD: the bin already piled with a jumble of every colour. */
  junkyard(ctx, w, h) {
    const s = Math.min(w / 3, h / (3 * SQRT3 / 2)) * 0.9;
    const height = s * SQRT3 / 2;
    const cx = w / 2;
    const top = (h - 3 * height) / 2;
    const wt = weights(s);
    const colors = [2, 0, 5, 1, 4, 6, 3, 7, 0];
    const jitter = [
      [0.16, 0.04, 0.02], [-0.22, -0.03, 0.05], [0.3, 0.02, -0.04], [-0.12, 0.05, 0.03], [0.24, -0.04, -0.02],
      [-0.3, 0, 0.06], [0.1, -0.06, 0], [-0.2, 0.03, -0.05], [0.18, 0, 0.03],
    ];
    let slot = 0;
    for (let row = 0; row < 3; row++) {
      const y0 = top + row * height;
      const left = cx - 1.5 * s + row * s / 2;
      for (let j = 0; j < 2 * (2 - row) + 1; j++) {
        const x = left + Math.floor(j / 2) * s;
        const shape = j % 2 === 0
          ? [{ x, y: y0 }, { x: x + s, y: y0 }, { x: x + s / 2, y: y0 + height }]
          : [{ x: x + s, y: y0 }, { x: x + s * 1.5, y: y0 + height }, { x: x + s / 2, y: y0 + height }];
        const [spin, dx, dy] = jitter[slot];
        const moved = rotated(scaled(shape, 0.82), spin, centroid(shape)).map(p => ({ x: p.x + dx * s, y: p.y + dy * s }));
        // The top row only part filled: a pile, not a full bin
        if (!(row === 0 && (j === 0 || j === 4))) piece(ctx, moved, colors[slot], s);
        slot++;
      }
    }
    tracePath(ctx, [{ x: cx - 1.5 * s, y: top }, { x: cx + 1.5 * s, y: top }, { x: cx, y: top + 3 * height }]);
    ctx.strokeStyle = skin.ink;
    ctx.lineWidth = wt.line;
    ctx.stroke();
  },

  /** WANTED: one triangle caught in an ink sight, its colour the one that pays triple. */
  wanted(ctx, w, h) {
    const c = { x: w / 2, y: h / 2 };
    const ring = Math.min(w, h) / 2 * 0.72;
    const wt = weights(ring);
    const s = ring * 1.2;
    piece(ctx, triangle({ x: c.x, y: c.y + s * 0.04 }, s, true), 2, s * 0.8);
    circle(ctx, c, ring);
    ctx.strokeStyle = skin.ink;
    ctx.lineWidth = wt.line;
    ctx.stroke();
    for (let k = 0; k < 4; k++) {
      const a = k * Math.PI / 2;
      const ux = Math.cos(a), uy = Math.sin(a);
      line(ctx, { x: c.x + ux * ring * 1.36, y: c.y + uy * ring * 1.36 },
        { x: c.x + ux * ring * 0.86, y: c.y + uy * ring * 0.86 }, wt.line);
    }
  },

  /** COMBO FEVER: three hexes clearing at once, packed together, each outlined as it flashes out. */
  comboFever(ctx, w, h) {
    const r = Math.min(w / (2 * SQRT3), h / 3.5) / (1 + weights(1).heavy * 0.6);
    const mid = { x: w / 2, y: h / 2 };
    const centers = [
      { x: mid.x, y: mid.y - 0.75 * r },
      { x: mid.x - SQRT3 / 2 * r, y: mid.y + 0.75 * r },
      { x: mid.x + SQRT3 / 2 * r, y: mid.y + 0.75 * r },
    ];
    centers.forEach((c, i) => hex(ctx, c, r, () => [2, 0, 1][i]));
    centers.forEach(c => outline(ctx, c, r, { width: weights(r).heavy }));
  },

  /** ONE WAY: the dial, and a single arrow turning clockwise round it. */
  oneWay(ctx, w, h) {
    const c = { x: w / 2, y: h / 2 };
    const r = radiusIn(w, h) * 0.6;
    const wt = weights(r);
    hex(ctx, c, r, k => (k % 2 === 0 ? 0 : 1));
    outline(ctx, c, r, { width: wt.heavy });
    turn(ctx, c, r * 1.42, -Math.PI * 0.95, -Math.PI * 0.95 + Math.PI * 1.35, wt.heavy * 0.9);
  },

  /** FULL SPECTRUM: a hex of six colours, and the last two waiting beside it. */
  fullSpectrum(ctx, w, h) {
    const r = Math.min(w / (SQRT3 + 0.95), h / 2) / (1 + LINE_WEIGHT() * 0.6);
    const side = r * 0.86;
    const depth = side * SQRT3 / 2;
    const left = (w - (SQRT3 * r + r * 0.16 + depth)) / 2;
    const c = { x: left + SQRT3 / 2 * r, y: h / 2 };
    hex(ctx, c, r, k => k);
    const x = c.x + SQRT3 / 2 * r + r * 0.16;
    for (let i = 0; i < 2; i++) {
      const y = c.y + (i === 0 ? -1 : 1) * side * 0.56;
      piece(ctx, [{ x, y: y - side / 2 }, { x: x + depth, y }, { x, y: y + side / 2 }], 6 + i, r);
    }
  },
};

export const drawModifier = (ctx, modifier, w, h) => MODIFIER_ICONS[modifier](ctx, w, h);

// ===== Setup and tile glyphs =====

/** A gauge whose needle swings with the speed. */
function gauge(ctx, w, h, speed) {
  const r = Math.min(w, h * 1.3) * 0.46;
  const c = { x: w / 2, y: h / 2 + r * 0.42 };
  const width = Math.max(1.5, r * 0.13);
  const from = Math.PI * 0.95, to = Math.PI * 2.05;
  ctx.save();
  ctx.lineCap = 'butt';
  ctx.beginPath();
  ctx.arc(c.x, c.y, r, from, to);
  ctx.strokeStyle = rgba(skin.ink, 0.45);
  ctx.lineWidth = width;
  ctx.stroke();
  const at = { slow: 0.14, normal: 0.5, fast: 0.86 }[speed];
  const a = from + (to - from) * at;
  ctx.beginPath();
  ctx.arc(c.x, c.y, r, from, a);
  ctx.strokeStyle = skin.ink;
  ctx.stroke();
  ctx.restore();
  line(ctx, c, { x: c.x + Math.cos(a) * r * 0.78, y: c.y + Math.sin(a) * r * 0.78 }, width);
  circle(ctx, c, width * 1.1);
  ctx.fillStyle = skin.ink;
  ctx.fill();
}

/** The bin's lattice: more, smaller triangles for the regular board. */
function boardGlyph(ctx, w, h, board) {
  const c = { x: w / 2, y: h / 2 };
  const r = radiusIn(w, h);
  const n = board === 'big' ? 2 : 3;
  const shape = corners(c, r);
  ctx.strokeStyle = rgba(skin.ink, 0.5);
  ctx.lineWidth = Math.max(1, r * 0.05);
  ctx.beginPath();
  for (let side = 0; side < 3; side++) {
    const [a, b, d, e] = [shape[side], shape[(side + 1) % 6], shape[(side + 3) % 6], shape[(side + 4) % 6]];
    for (let i = 1; i < n * 2; i++) {
      const t = i / (n * 2);
      const p = lerp(a, e, t), q = lerp(b, d, t);
      ctx.moveTo(p.x, p.y);
      ctx.lineTo(q.x, q.y);
    }
  }
  ctx.stroke();
  outline(ctx, c, r, { width: Math.max(1.5, r * 0.1) });
}

/** The skin tile: the skin's own colours, as a hex. */
function paletteGlyph(ctx, w, h) {
  const r = radiusIn(w, h);
  hex(ctx, { x: w / 2, y: h / 2 }, r, k => [0, 1, 2, 4, 5, 6][k]);
}

/** A padlock, while the skin is only a preview. */
function lockGlyph(ctx, w, h) {
  const s = Math.min(w, h) * 0.92;
  const left = (w - s * 0.7) / 2;
  const top = (h - s) / 2 + s * 0.42;
  const width = Math.max(1.5, s * 0.08);
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = width;
  ctx.strokeRect(left, top, s * 0.7, s * 0.58);
  ctx.beginPath();
  ctx.arc(w / 2, top, s * 0.2, Math.PI, 0);
  ctx.moveTo(w / 2 - s * 0.2, top);
  ctx.stroke();
  circle(ctx, { x: w / 2, y: top + s * 0.28 }, s * 0.06);
  ctx.fillStyle = skin.ink;
  ctx.fill();
}

/** The rules tile: a question mark, set in the skin's display face. */
function questionGlyph(ctx, w, h) {
  ctx.font = `${Math.round(h * 0.95)}px "${skin.fonts.display}"`;
  ctx.fillStyle = skin.ink;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText('?', w / 2, h / 2 + h * 0.04);
}

/** A hand, for which side the spinner sits. A dial beside a bin, on that side. */
function handGlyph(ctx, w, h, leftHanded) {
  const r = radiusIn(w, h, 1.7);
  const big = { x: w / 2 + (leftHanded ? r * 0.42 : -r * 0.42), y: h / 2 - r * 0.2 };
  outline(ctx, big, r * 0.95, { width: Math.max(1.5, r * 0.1), opacity: SECONDARY });
  const side = leftHanded ? -1 : 1;
  const small = { x: big.x + side * r * 1.06, y: big.y + r * 1.0 };
  tracePath(ctx, corners(small, r * 0.52));
  ctx.fillStyle = skin.ink;
  ctx.fill();
}

/** A speaker, with waves when the sound is on and a slash when it's off. */
function speakerGlyph(ctx, w, h, on) {
  const s = Math.min(w, h) * 0.9;
  const x = w / 2 - s * 0.4, y = h / 2;
  const width = Math.max(1.5, s * 0.08);
  tracePath(ctx, [
    { x, y: y - s * 0.14 }, { x: x + s * 0.2, y: y - s * 0.14 }, { x: x + s * 0.42, y: y - s * 0.34 },
    { x: x + s * 0.42, y: y + s * 0.34 }, { x: x + s * 0.2, y: y + s * 0.14 }, { x, y: y + s * 0.14 },
  ]);
  ctx.fillStyle = skin.ink;
  ctx.fill();
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = width;
  if (on) {
    for (const r of [0.2, 0.36]) {
      ctx.beginPath();
      ctx.arc(x + s * 0.44, y, s * r, -Math.PI / 4, Math.PI / 4);
      ctx.stroke();
    }
  } else {
    line(ctx, { x: x + s * 0.58, y: y - s * 0.16 }, { x: x + s * 0.88, y: y + s * 0.16 }, width);
    line(ctx, { x: x + s * 0.88, y: y - s * 0.16 }, { x: x + s * 0.58, y: y + s * 0.16 }, width);
  }
}

// ===== How-to art =====

/** A small bin on a real lattice, the bottom filled, one more triangle on its way in. */
function binArt(ctx, w, h) {
  const r = radiusIn(w, h);
  const scale = r / ART_GRID.size;
  const at = ({ x, y }) => ({ x: w / 2 - y * scale, y: h / 2 + x * scale });
  const lowest = [...ART_GRID.cells].sort((a, b) => ART_GRID.cellCenter(b.r, b.c).x - ART_GRID.cellCenter(a.r, a.c).x);
  const colors = [0, 2, 1, 2, 0, 1, 4, 0, 2, 1, 0];
  const shape = cell => scaled(ART_GRID.cellVertices(cell.r, cell.c).map(at), 0.86);
  lowest.slice(0, colors.length).forEach((cell, i) => piece(ctx, shape(cell), colors[i], scale));
  piece(ctx, shape(lowest[lowest.length - 3]), 2, scale);
  outline(ctx, { x: w / 2, y: h / 2 }, r);
}

/** The dial on a mixed hex, with a turn round it. */
function dialArt(ctx, w, h) {
  const c = { x: w / 2, y: h / 2 };
  const r = radiusIn(w, h) * 0.7;
  const wt = weights(r);
  hex(ctx, c, r, k => [0, 1, 0, 2, 1, 2][k]);
  outline(ctx, c, r, { width: wt.line });
  turn(ctx, c, r * 1.32, -Math.PI * 0.9, Math.PI * 0.2, wt.line * 1.1);
}

/** Six of one colour: a hex. */
function hexArt(ctx, w, h) {
  const c = { x: w / 2, y: h / 2 };
  const r = radiusIn(w, h);
  hex(ctx, c, r, () => 0);
  outline(ctx, c, r);
}

/** Colours coming in, one more each level. */
function levelsArt(ctx, w, h) {
  const width = w / 2.2;
  const rowH = width * 2 / SQRT3 * 0.96;
  [[0, 0, 6, true], [1, 0, 3, true], [0, 1, 1, true], [1, 1, 0, false]].forEach(([col, row, count, inPlay], i) => {
    drawColorHex(ctx, { x: w / 2 + (col - 0.5) * width * 1.1, y: h / 2 + (row - 0.5) * rowH }, width, i, count, inPlay);
  });
}

/** A hex with one glowing triangle. */
function glowArt(ctx, w, h) {
  const c = { x: w / 2, y: h / 2 };
  const r = radiusIn(w, h);
  triangles(c, r).forEach((points, k) => piece(ctx, points, 4, r, { glow: k === 1 }));
}

/** A fingertip on the dial. */
function touchArt(ctx, w, h) {
  dialArt(ctx, w, h);
  circle(ctx, { x: w * 0.62, y: h * 0.6 }, Math.min(w, h) * 0.17);
  ctx.fillStyle = rgba(skin.ink, 0.55);
  ctx.fill();
}

/** Keys. */
function keyboardArt(ctx, w, h) {
  const unit = Math.min(w / 3.6, h / 2.6);
  const left = (w - unit * 3.3) / 2;
  const top = (h - unit * 2.2) / 2;
  ctx.strokeStyle = skin.ink;
  ctx.lineWidth = Math.max(1.25, unit * 0.09);
  ctx.strokeRect(left + unit * 1.1, top, unit, unit);
  for (let i = 0; i < 3; i++) ctx.strokeRect(left + i * unit * 1.1, top + unit * 1.2, unit, unit);
}

const ART = {
  bin: binArt, dial: dialArt, hex: hexArt, levels: levelsArt, glow: glowArt, touch: touchArt, keyboard: keyboardArt,
  speed: (ctx, w, h) => gauge(ctx, w, h, 'fast'),
  board: (ctx, w, h) => boardGlyph(ctx, w, h, 'big'),
  main: spectrum, endless, sprint,
};

/** How-to art by name, or a game symbol. Also what the menu's tiles use. */
export function drawArt(ctx, name, w, h, value) {
  sharpLines(ctx);
  switch (name) {
    case 'daily': dailyIcon(ctx, w, h, value); break;
    case 'gauge': gauge(ctx, w, h, value); break;
    case 'boardGlyph': boardGlyph(ctx, w, h, value); break;
    case 'palette': paletteGlyph(ctx, w, h); break;
    case 'lock': lockGlyph(ctx, w, h); break;
    case 'question': questionGlyph(ctx, w, h); break;
    case 'hand': handGlyph(ctx, w, h, value); break;
    case 'speaker': speakerGlyph(ctx, w, h, value); break;
    default: ART[name]?.(ctx, w, h);
  }
}
