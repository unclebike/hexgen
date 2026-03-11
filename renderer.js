// renderer.js — Canvas rendering of board, triangles, and cursor

import { getValidHexCoords, hexToPixel, triangleVertices, hexKey, getBoardBounds } from './grid.js';
import { COLOR_PALETTE, EMPTY_COLOR, BOARD_BG } from './progression.js';
import { BOARD_RADIUS, HEX_SIZE } from './gamestate.js';

let canvas, ctx;
let offsetX = 0, offsetY = 0;
let scale = 1;
let currentSize = HEX_SIZE;

/**
 * Initialize the renderer with a canvas element.
 */
export function initRenderer(canvasEl) {
  canvas = canvasEl;
  ctx = canvas.getContext('2d');
  resize();
  return { canvas, ctx };
}

/**
 * Recalculate canvas size and offsets for responsive scaling.
 */
export function resize() {
  const dpr = window.devicePixelRatio || 1;
  const w = window.innerWidth;
  const h = window.innerHeight;

  canvas.width = w * dpr;
  canvas.height = h * dpr;
  canvas.style.width = w + 'px';
  canvas.style.height = h + 'px';

  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

  // Calculate hex size to fit the board in viewport
  // Board spans roughly 2*radius hex widths horizontally
  const boardWidthHexes = 2 * BOARD_RADIUS + 1;
  const boardHeightHexes = 2 * BOARD_RADIUS + 1;

  const maxHexW = (w * 0.85) / (boardWidthHexes * Math.sqrt(3));
  const maxHexH = (h * 0.80) / (boardHeightHexes * 1.5 + 0.5);
  currentSize = Math.min(maxHexW, maxHexH);

  // Center the board
  offsetX = w / 2;
  offsetY = h / 2;
}

/**
 * Get the current rendering size and offsets (for input hit testing).
 */
export function getRenderParams() {
  return { size: currentSize, offsetX, offsetY };
}

/**
 * Render a complete frame.
 */
export function renderFrame(frame) {
  const { state, animations, dt } = frame;
  const w = canvas.width / (window.devicePixelRatio || 1);
  const h = canvas.height / (window.devicePixelRatio || 1);

  // Apply screen shake from animations
  let shakeX = 0, shakeY = 0;
  if (animations) {
    const shake = animations.getScreenShake();
    shakeX = shake.x;
    shakeY = shake.y;
  }

  ctx.save();
  ctx.translate(shakeX, shakeY);

  // Clear background
  ctx.fillStyle = BOARD_BG;
  ctx.fillRect(-shakeX, -shakeY, w, h);

  // Draw board
  drawBoard(state);

  // Draw cursor
  drawCursor(state);

  // Draw clearing animation
  if (state.phase === 'clearing' && animations) {
    drawClearingEffect(state, animations);
  }

  // Draw particles
  if (animations) {
    animations.drawParticles(ctx, offsetX, offsetY);
  }

  ctx.restore();
}

/**
 * Draw all triangles on the board.
 */
function drawBoard(state) {
  const coords = getValidHexCoords(BOARD_RADIUS);

  for (const { q, r } of coords) {
    const cell = state.board.get(hexKey(q, r));
    if (!cell) continue;

    for (let i = 0; i < 6; i++) {
      const tri = cell[i];
      const verts = triangleVertices({ q, r, triIndex: i }, currentSize);

      // Transform to screen coords
      const screenVerts = verts.map(v => ({
        x: v.x + offsetX,
        y: v.y + offsetY,
      }));

      // Fill
      ctx.beginPath();
      ctx.moveTo(screenVerts[0].x, screenVerts[0].y);
      ctx.lineTo(screenVerts[1].x, screenVerts[1].y);
      ctx.lineTo(screenVerts[2].x, screenVerts[2].y);
      ctx.closePath();

      if (tri.color >= 0 && tri.color < COLOR_PALETTE.length) {
        ctx.fillStyle = COLOR_PALETTE[tri.color];
      } else {
        ctx.fillStyle = EMPTY_COLOR;
      }
      ctx.fill();

      // Stroke
      ctx.strokeStyle = '#0a0a1a';
      ctx.lineWidth = 1;
      ctx.stroke();

      // Power-up glow
      if (tri.isPowerUp) {
        const glowAlpha = 0.3 + 0.3 * Math.sin(Date.now() * 0.005);
        ctx.strokeStyle = `rgba(255, 255, 255, ${glowAlpha})`;
        ctx.lineWidth = 3;
        ctx.stroke();
      }
    }
  }
}

/**
 * Draw cursor overlay on selected triangles.
 */
function drawCursor(state) {
  const { selectedTriangles, center } = state.cursor;

  // Draw selection overlay
  for (const tri of selectedTriangles) {
    const verts = triangleVertices(tri, currentSize);
    const screenVerts = verts.map(v => ({
      x: v.x + offsetX,
      y: v.y + offsetY,
    }));

    ctx.beginPath();
    ctx.moveTo(screenVerts[0].x, screenVerts[0].y);
    ctx.lineTo(screenVerts[1].x, screenVerts[1].y);
    ctx.lineTo(screenVerts[2].x, screenVerts[2].y);
    ctx.closePath();

    ctx.fillStyle = 'rgba(255, 255, 255, 0.15)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.6)';
    ctx.lineWidth = 2;
    ctx.stroke();
  }

  // Draw center dot
  const centerVerts = triangleVertices(center, currentSize);
  const cx = (centerVerts[0].x + centerVerts[1].x + centerVerts[2].x) / 3 + offsetX;
  const cy = (centerVerts[0].y + centerVerts[1].y + centerVerts[2].y) / 3 + offsetY;

  ctx.beginPath();
  ctx.arc(cx, cy, 3, 0, Math.PI * 2);
  ctx.fillStyle = 'white';
  ctx.fill();
}

/**
 * Draw clearing effect (flash white on clearing hexes).
 */
function drawClearingEffect(state, animations) {
  for (const hex of state.pendingClears) {
    const progress = 1 - (state.clearTimer / 500);

    for (const triID of hex.triangleIDs) {
      const verts = triangleVertices(triID, currentSize);
      const screenVerts = verts.map(v => ({
        x: v.x + offsetX,
        y: v.y + offsetY,
      }));

      // Centroid for shrinking effect
      const cx = (screenVerts[0].x + screenVerts[1].x + screenVerts[2].x) / 3;
      const cy = (screenVerts[0].y + screenVerts[1].y + screenVerts[2].y) / 3;

      const shrink = progress < 0.2 ? 1 : 1 - ((progress - 0.2) / 0.8);
      const alpha = progress < 0.2 ? 1 : 1 - ((progress - 0.2) / 0.8);

      ctx.save();
      ctx.translate(cx, cy);
      ctx.scale(shrink, shrink);
      ctx.translate(-cx, -cy);

      ctx.beginPath();
      ctx.moveTo(screenVerts[0].x, screenVerts[0].y);
      ctx.lineTo(screenVerts[1].x, screenVerts[1].y);
      ctx.lineTo(screenVerts[2].x, screenVerts[2].y);
      ctx.closePath();

      ctx.fillStyle = progress < 0.2
        ? `rgba(255, 255, 255, ${1 - progress * 5})`
        : `rgba(255, 255, 255, ${alpha * 0.5})`;
      ctx.fill();

      ctx.restore();
    }
  }
}

export { canvas, ctx, currentSize, offsetX, offsetY };
