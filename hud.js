// hud.js — HUD overlay: score, level, mode, game over, pause

import { COLOR_PALETTE } from './progression.js';

// On-screen rotation button positions (set during draw, read by input)
export const touchButtons = {
  rotateCCW: { x: 0, y: 0, radius: 0 },
  rotateCW: { x: 0, y: 0, radius: 0 },
  visible: false,
};

/**
 * Draw the HUD overlay onto the canvas.
 * @param {CanvasRenderingContext2D} ctx
 * @param {GameState} state
 * @param {number} width - Canvas width in CSS pixels
 * @param {number} height - Canvas height in CSS pixels
 */
export function drawHUD(ctx, state, width, height) {
  // Score — top-left
  ctx.save();
  ctx.font = 'bold 24px monospace';
  ctx.fillStyle = 'white';
  ctx.textAlign = 'left';
  ctx.textBaseline = 'top';
  ctx.fillText(`${state.score}`, 20, 20);

  // Mode label — top-center
  ctx.font = '14px monospace';
  ctx.textAlign = 'center';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
  const modeLabel = state.mode === 'main' ? 'MAIN' : state.mode === 'endless' ? 'ENDLESS' : 'SPRINT';
  ctx.fillText(modeLabel, width / 2, 20);

  // Sprint timer
  if (state.mode === 'sprint' && state.sprintTimeRemaining >= 0) {
    const secs = Math.ceil(state.sprintTimeRemaining / 1000);
    const mins = Math.floor(secs / 60);
    const s = secs % 60;
    ctx.font = 'bold 18px monospace';
    ctx.fillStyle = secs <= 30 ? '#F44336' : 'white';
    ctx.fillText(`${mins}:${s.toString().padStart(2, '0')}`, width / 2, 40);
  }

  // Level indicator — top-right (colored dots)
  ctx.textAlign = 'right';
  const dotSize = 8;
  const dotSpacing = 20;
  const startX = width - 20;
  const dotY = 28;

  for (let i = 0; i < state.activeColors.length; i++) {
    const x = startX - (state.activeColors.length - 1 - i) * dotSpacing;
    ctx.beginPath();
    ctx.arc(x, dotY, dotSize, 0, Math.PI * 2);
    ctx.fillStyle = COLOR_PALETTE[state.activeColors[i]];
    ctx.fill();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)';
    ctx.lineWidth = 1;
    ctx.stroke();
  }

  // Hexes cleared counter
  ctx.font = '12px monospace';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.4)';
  ctx.textAlign = 'right';
  ctx.fillText(`hexes: ${state.hexesCleared}`, width - 20, dotY + 20);

  // On-screen rotation buttons (always visible, essential for touch)
  const btnRadius = Math.min(32, width * 0.06);
  const btnY = height - btnRadius - 24;
  const btnMargin = btnRadius + 20;

  // CCW button (left)
  touchButtons.rotateCCW = { x: btnMargin, y: btnY, radius: btnRadius };
  ctx.beginPath();
  ctx.arc(btnMargin, btnY, btnRadius, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.1)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)';
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.font = `bold ${btnRadius}px monospace`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
  ctx.fillText('\u21BA', btnMargin, btnY);

  // CW button (right)
  touchButtons.rotateCW = { x: width - btnMargin, y: btnY, radius: btnRadius };
  ctx.beginPath();
  ctx.arc(width - btnMargin, btnY, btnRadius, 0, Math.PI * 2);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.1)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.3)';
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
  ctx.fillText('\u21BB', width - btnMargin, btnY);

  touchButtons.visible = true;

  ctx.restore();
}

/**
 * Draw game over overlay.
 */
export function drawGameOver(ctx, state, width, height, isNewHighScore) {
  // Semi-transparent overlay
  ctx.fillStyle = 'rgba(0, 0, 0, 0.7)';
  ctx.fillRect(0, 0, width, height);

  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';

  // Game Over text
  ctx.font = 'bold 36px monospace';
  ctx.fillStyle = 'white';
  ctx.fillText(
    state.mode === 'main' && state.hexesCleared >= 48 ? 'YOU WIN' : 'GAME OVER',
    width / 2,
    height / 2 - 60
  );

  // Final score
  ctx.font = 'bold 28px monospace';
  ctx.fillStyle = '#FFD700';
  ctx.fillText(`${state.score}`, width / 2, height / 2 - 10);

  if (isNewHighScore) {
    ctx.font = '16px monospace';
    ctx.fillStyle = '#FFD700';
    ctx.fillText('NEW HIGH SCORE!', width / 2, height / 2 + 25);
  }

  // Restart hint
  ctx.font = '14px monospace';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
  ctx.fillText('tap to restart', width / 2, height / 2 + 60);
}

/**
 * Draw pause overlay.
 */
export function drawPause(ctx, width, height) {
  ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
  ctx.fillRect(0, 0, width, height);

  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.font = 'bold 32px monospace';
  ctx.fillStyle = 'white';
  ctx.fillText('PAUSED', width / 2, height / 2);

  ctx.font = '14px monospace';
  ctx.fillStyle = 'rgba(255, 255, 255, 0.5)';
  ctx.fillText('press space to continue', width / 2, height / 2 + 40);
}
