// menu.js — Title screen, mode selection, and skin choice
// Canvas-drawn menu (no HTML elements)

import { loadHighScores } from './scoring.js';
import { skin, copy, weights, unlockedCount, skinCount } from './skins.js';
import { drawLogo, drawOverlayEffects, getScale, sharpLines } from './renderer.js';
import { drawText, drawLabel } from './hud.js';

const BUILD = 'build 7 · brand';
const MODES = ['main', 'endless', 'sprint'];

let buttons = [];
let hoverIndex = -1;
let logoBox = null; // where the logo was drawn, for the hidden unlock taps

/**
 * Draw the menu screen.
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} width
 * @param {number} height
 * @returns {boolean} true if menu is active
 */
export function drawMenu(ctx, width, height) {
  const text = copy();
  const wt = weights(getScale());
  ctx.save();
  sharpLines(ctx);
  ctx.fillStyle = skin.background;
  ctx.fillRect(0, 0, width, height);

  // Logo, built from the game's triangles
  const logoY = height * 0.19;
  // Two lines on the bin's sideways lattice: about 1.2× as wide as tall. Fit it between
  // the top and the tagline above the buttons (which start at 38% of the height).
  const logoW = Math.min(width * 0.6, 300, Math.max(0, height * 0.38 - 68) * 1.2);
  const logoH = drawLogo(ctx, width / 2, logoY, logoW);
  logoBox = { x: width / 2 - logoW / 2, y: logoY - logoH / 2, w: logoW, h: logoH };
  drawText(ctx, text.tagline, width / 2, logoY + logoH / 2 + 24, { size: 13, alpha: 0.6 });

  // Build label, so it's obvious which version a cached browser is running
  drawText(ctx, BUILD, width / 2, height - 14, { size: 10, alpha: 0.6 });

  // Mode buttons, then the skin button
  const btnWidth = 220;
  const btnHeight = 52;
  const btnGap = 18;
  const startY = height * 0.38;
  const scores = loadHighScores();

  const items = [
    ...MODES.map(id => ({ id, label: text.modes[id].label, detail: text.modes[id].detail, best: scores[id] })),
    { id: 'skin', label: text.skin, detail: `${skin.id} · ${unlockedCount()}/${skinCount()}` },
  ];

  buttons = [];
  items.forEach((item, i) => {
    const x = width / 2 - btnWidth / 2;
    const y = startY + i * (btnHeight + btnGap) + (item.id === 'skin' ? btnGap : 0);
    buttons.push({ x, y, w: btnWidth, h: btnHeight, id: item.id });

    // Outlined, sharp-cornered; the selected one takes the heavy weight
    const selected = hoverIndex === i;
    ctx.fillStyle = skin.empty;
    ctx.fillRect(x, y, btnWidth, btnHeight);
    ctx.strokeStyle = skin.ink;
    ctx.lineWidth = selected ? wt.heavy : wt.line;
    ctx.strokeRect(x, y, btnWidth, btnHeight);

    drawLabel(ctx, item.label, width / 2, y + btnHeight / 2 - 7, { size: 17 });
    drawText(ctx, item.detail, width / 2, y + btnHeight / 2 + 13, { size: 11, alpha: 0.6 });

    if (item.best > 0) {
      drawText(ctx, `${text.best} ${item.best}`, x + btnWidth - 8, y + 12, { role: 'digits', size: 10, align: 'right' });
    }
  });

  // Controls hint
  const controlY = height * 0.88;
  drawText(ctx, text.touchHint, width / 2, controlY, { size: 11, alpha: 0.6 });
  drawText(ctx, text.keysHint, width / 2, controlY + 18, { size: 11, alpha: 0.6 });

  drawOverlayEffects(ctx, width, height);
  ctx.restore();
  return true;
}

/**
 * Handle click/tap on menu — returns 'main' | 'endless' | 'sprint' | 'skin' | 'logo', or null.
 */
export function handleMenuClick(x, y) {
  if (logoBox && x >= logoBox.x && x <= logoBox.x + logoBox.w && y >= logoBox.y && y <= logoBox.y + logoBox.h) {
    return 'logo';
  }
  for (const btn of buttons) {
    if (x >= btn.x && x <= btn.x + btn.w && y >= btn.y && y <= btn.y + btn.h) {
      return btn.id;
    }
  }
  return null;
}

/**
 * Handle mouse move for hover effect.
 */
export function handleMenuHover(x, y) {
  hoverIndex = -1;
  for (let i = 0; i < buttons.length; i++) {
    const btn = buttons[i];
    if (x >= btn.x && x <= btn.x + btn.w && y >= btn.y && y <= btn.y + btn.h) {
      hoverIndex = i;
      break;
    }
  }
}

/**
 * Reset menu state.
 */
export function resetMenu() {
  hoverIndex = -1;
}
