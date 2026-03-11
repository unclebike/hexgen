// rotation.js — Core rotation mechanic
// Rotates the 6 triangles within a hex cell by 60° CW or CCW
// Matches original Dialhex: the cursor is one hex, rotation cycles its contents

import { hexKey } from './grid.js';

/**
 * Rotate the 6 triangles within a hex cell by one step (60°).
 * CW (direction=1): each position i gets data from position (i-1+6)%6
 * CCW (direction=-1): each position i gets data from position (i+1)%6
 *
 * @param {Map} board - Current board state
 * @param {number} q - Hex q coordinate
 * @param {number} r - Hex r coordinate
 * @param {number} direction - 1 for CW, -1 for CCW
 * @returns {Map} - New board with rotated cell
 */
export function rotateHexCell(board, q, r, direction) {
  const key = hexKey(q, r);
  const cell = board.get(key);
  if (!cell) return board;

  // Clone the board
  const newBoard = new Map();
  for (const [k, c] of board) {
    newBoard.set(k, k === key ? new Array(6) : c.map(t => ({ ...t })));
  }

  const newCell = newBoard.get(key);
  for (let i = 0; i < 6; i++) {
    const srcIndex = direction === 1
      ? (i - 1 + 6) % 6   // CW: position i gets data from the one before it
      : (i + 1) % 6;       // CCW: position i gets data from the one after it
    newCell[i] = { ...cell[srcIndex], id: { q, r, triIndex: i } };
  }

  return newBoard;
}
