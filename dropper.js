// dropper.js — Triangle drop system
// Generates new colored triangles at the top of the board

import { hexKey, getTopEdgeCells } from './grid.js';

// Max triangles to drop per tick (prevents flooding)
const MAX_DROP_PER_TICK = 3;

/**
 * Generate a drop — add new colored triangles at the top of the board.
 * Drops into the upper triangles (tri 4 and 5) of top-edge cells.
 * @param {Map} board - Current board state
 * @param {number[]} activeColors - Color indices currently in play
 * @param {number} radius - Board radius
 * @returns {Array<{triID, color, isPowerUp}>} - New triangles to place
 */
export function generateDrop(board, activeColors, radius = 4) {
  const topCells = getTopEdgeCells(radius);
  const hasPowerUp = boardHasPowerUp(board);

  // Collect all empty top-entry positions
  // tri 4 (upper-left) and tri 5 (upper-right) are the topmost within each cell
  const emptyPositions = [];
  for (const { q, r } of topCells) {
    const cell = board.get(hexKey(q, r));
    if (!cell) continue;
    for (const i of [4, 5]) {
      if (cell[i].color === -1) {
        emptyPositions.push({ q, r, triIndex: i });
      }
    }
  }

  if (emptyPositions.length === 0) return [];

  // Drop into a random subset of empty positions
  const dropCount = Math.min(MAX_DROP_PER_TICK, emptyPositions.length);
  shuffleArray(emptyPositions);

  const drops = [];
  for (let d = 0; d < dropCount; d++) {
    const pos = emptyPositions[d];
    const { color, isPowerUp } = generateTriangleContent(activeColors, hasPowerUp && drops.every(dr => !dr.isPowerUp));
    drops.push({
      triID: pos,
      color,
      isPowerUp,
    });
  }

  return drops;
}

/**
 * Apply drops to the board — returns new board.
 */
export function applyDrops(board, drops) {
  const newBoard = new Map();
  for (const [key, cell] of board) {
    newBoard.set(key, cell.map(t => ({ ...t })));
  }

  for (const drop of drops) {
    const cell = newBoard.get(hexKey(drop.triID.q, drop.triID.r));
    cell[drop.triID.triIndex] = {
      id: drop.triID,
      color: drop.color,
      isPowerUp: drop.isPowerUp,
      isGlowing: drop.isPowerUp !== null,
    };
  }

  return newBoard;
}

/**
 * Generate content for a single new triangle.
 */
function generateTriangleContent(activeColors, hasPowerUp) {
  let isPowerUp = null;

  if (!hasPowerUp) {
    const roll = Math.random();
    if (roll < 0.03) {
      isPowerUp = 'drain';
    } else if (roll < 0.05) {
      isPowerUp = 'swap';
    }
  }

  const color = activeColors[Math.floor(Math.random() * activeColors.length)];
  return { color, isPowerUp };
}

/**
 * Check if the board already has a power-up triangle.
 */
function boardHasPowerUp(board) {
  for (const [, cell] of board) {
    for (const tri of cell) {
      if (tri.isPowerUp !== null) return true;
    }
  }
  return false;
}

/**
 * Check if the game is over — top entry positions are all full.
 */
export function isGameOver(board, radius = 4) {
  const topCells = getTopEdgeCells(radius);
  for (const { q, r } of topCells) {
    const cell = board.get(hexKey(q, r));
    if (!cell) continue;
    for (const i of [4, 5]) {
      if (cell[i].color === -1) return false;
    }
  }
  return true;
}

/**
 * Fisher-Yates shuffle (in-place).
 */
function shuffleArray(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
}
