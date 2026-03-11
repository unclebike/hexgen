// dropper.js — Triangle drop system
// Generates new colored triangles at the top of the board

import { getValidHexCoords, hexKey, getTopEdgeCells } from './grid.js';

/**
 * Generate a drop — fill empty triangles in the top-edge cells.
 * Returns new triangles to place (does not modify board).
 * @param {Map} board - Current board state
 * @param {number[]} activeColors - Color indices currently in play
 * @param {number} radius - Board radius
 * @returns {Array<{triID, color, isPowerUp}>} - New triangles to place
 */
export function generateDrop(board, activeColors, radius = 4) {
  const topCells = getTopEdgeCells(radius);
  const drops = [];
  const hasPowerUp = boardHasPowerUp(board);

  for (const { q, r } of topCells) {
    const cell = board.get(hexKey(q, r));
    if (!cell) continue;

    // Only fill triangles in the top portion of the cell (triIndex 0, 1, 5 — upper half)
    const topTriIndices = [0, 1, 5];
    for (const i of topTriIndices) {
      if (cell[i].color === -1) {
        const { color, isPowerUp } = generateTriangleContent(activeColors, hasPowerUp);
        drops.push({
          triID: { q, r, triIndex: i },
          color,
          isPowerUp,
        });
      }
    }
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
 * Check if the game is over — top row completely full when a drop is needed.
 */
export function isGameOver(board, radius = 4) {
  const topCells = getTopEdgeCells(radius);
  for (const { q, r } of topCells) {
    const cell = board.get(hexKey(q, r));
    if (!cell) continue;
    const topTriIndices = [0, 1, 5];
    for (const i of topTriIndices) {
      if (cell[i].color === -1) return false;
    }
  }
  return true;
}
