// menu.js — Title screen and mode selection
// Canvas-drawn menu (no HTML elements)

import { BOARD_BG } from './progression.js';
import { loadHighScores } from './scoring.js';

const MODES = [
  { id: 'main', label: 'MAIN', desc: 'Clear all 8 colors' },
  { id: 'endless', label: 'ENDLESS', desc: 'Play forever' },
  { id: 'sprint', label: 'SPRINT', desc: '3 minutes, max score' },
];

let buttons = [];
let selectedMode = null;
let hoverIndex = -1;

/**
 * Draw the menu screen.
 * @param {CanvasRenderingContext2D} ctx
 * @param {number} width
 * @param {number} height
 * @returns {boolean} true if menu is active
 */
export function drawMenu(ctx, width, height) {
  ctx.fillStyle = BOARD_BG;
  ctx.fillRect(0, 0, width, height);

  // Title
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  ctx.font = 'bold 48px monospace';
  ctx.fillStyle = 'white';
  ctx.fillText('DIALHEX', width / 2, height * 0.2);

  ctx.font = '14px monospace';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.4)';
  ctx.fillText('a hexagonal puzzle', width / 2, height * 0.2 + 40);

  // Mode buttons
  const btnWidth = 200;
  const btnHeight = 50;
  const btnGap = 20;
  const startY = height * 0.4;

  buttons = [];
  const scores = loadHighScores();

  MODES.forEach((mode, i) => {
    const x = width / 2 - btnWidth / 2;
    const y = startY + i * (btnHeight + btnGap);
    buttons.push({ x, y, w: btnWidth, h: btnHeight, mode: mode.id });

    const isHover = hoverIndex === i;

    // Button background
    ctx.fillStyle = isHover ? 'rgba(255, 255, 255, 0.15)' : 'rgba(255, 255, 255, 0.05)';
    ctx.fillRect(x, y, btnWidth, btnHeight);

    // Button border
    ctx.strokeStyle = isHover ? 'rgba(255, 255, 255, 0.6)' : 'rgba(255, 255, 255, 0.2)';
    ctx.lineWidth = 1;
    ctx.strokeRect(x, y, btnWidth, btnHeight);

    // Label
    ctx.font = 'bold 18px monospace';
    ctx.fillStyle = 'white';
    ctx.fillText(mode.label, width / 2, y + btnHeight / 2 - 6);

    // Description
    ctx.font = '10px monospace';
    ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
    ctx.fillText(mode.desc, width / 2, y + btnHeight / 2 + 12);

    // High score
    const hs = scores[mode.id];
    if (hs > 0) {
      ctx.font = '10px monospace';
      ctx.fillStyle = '#FFD700';
      ctx.textAlign = 'right';
      ctx.fillText(`best: ${hs}`, x + btnWidth - 8, y + 14);
      ctx.textAlign = 'center';
    }
  });

  // Controls hint
  ctx.font = '11px monospace';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.3)';
  const controlY = height * 0.85;
  ctx.fillText('scroll/QE: rotate | click/WASD: move cursor', width / 2, controlY);
  ctx.fillText('touch: tap to move, two-finger twist to rotate', width / 2, controlY + 18);

  return true;
}

/**
 * Handle click/tap on menu — returns selected mode or null.
 */
export function handleMenuClick(x, y) {
  for (const btn of buttons) {
    if (x >= btn.x && x <= btn.x + btn.w && y >= btn.y && y <= btn.y + btn.h) {
      return btn.mode;
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
  selectedMode = null;
  hoverIndex = -1;
}
