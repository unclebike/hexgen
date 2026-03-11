// hexdetect.js — Detect completed hexagons (6 same-color triangles in one hex cell)

import { hexKey, getValidHexCoords } from './grid.js';

/**
 * Scan the board for completed hexagons.
 * A hex is complete when all 6 triangles in a cell have the same non-empty color.
 * @param {Map} board - Current board state
 * @param {number} radius - Board radius
 * @returns {Array<{hexCoord, color, triangleIDs}>} - Detected completed hexes
 */
export function detectCompletedHexes(board, radius = 4) {
  const completed = [];
  const coords = getValidHexCoords(radius);

  for (const { q, r } of coords) {
    const cell = board.get(hexKey(q, r));
    if (!cell) continue;

    const firstColor = cell[0].color;
    if (firstColor === -1) continue; // empty cell

    let allSame = true;
    for (let i = 1; i < 6; i++) {
      if (cell[i].color !== firstColor) {
        allSame = false;
        break;
      }
    }

    if (allSame) {
      console.log(`[CLEAR] Hex (${q},${r}) completed with color ${firstColor}!`);
      completed.push({
        hexCoord: { q, r },
        color: firstColor,
        triangleIDs: cell.map((_, i) => ({ q, r, triIndex: i })),
      });
    }
  }

  return completed;
}

/**
 * Clear completed hexes from the board — set their triangles to empty.
 * Returns a new board (immutable update).
 * @param {Map} board - Current board state
 * @param {Array<{hexCoord, color, triangleIDs}>} hexes - Hexes to clear
 * @returns {Map} - New board with cleared triangles
 */
export function clearHexes(board, hexes) {
  const newBoard = new Map();
  for (const [key, cell] of board) {
    newBoard.set(key, cell.map(t => ({ ...t })));
  }

  for (const hex of hexes) {
    const key = hexKey(hex.hexCoord.q, hex.hexCoord.r);
    const cell = newBoard.get(key);
    for (let i = 0; i < 6; i++) {
      cell[i] = {
        id: { q: hex.hexCoord.q, r: hex.hexCoord.r, triIndex: i },
        color: -1,
        isPowerUp: null,
        isGlowing: false,
      };
    }
  }

  return newBoard;
}
