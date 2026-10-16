// rotation.js — Turning the dial
// The dial sits on a vertex and turns the six triangles around it by 60°.
// Because dials overlap, turning one moves triangles into neighbouring hexes.

import { dialCells, key } from './grid.js';

/**
 * Turn the six cells around vertex (k, j) one step. dir: 1 = clockwise, -1 = counter.
 * Mutates the board. Returns false (and changes nothing) if a cell is mid-clear.
 */
export function rotateDial(board, k, j, dir) {
  const cells = dialCells(k, j);
  const pieces = cells.map(({ r, c }) => board.get(key(r, c)));
  if (pieces.some(p => p && p.clearT > 0)) return false;

  cells.forEach(({ r, c }, i) => {
    const p = pieces[(i - dir + 6) % 6];
    if (p) {
      p.from = null;
      board.set(key(r, c), p);
    } else {
      board.delete(key(r, c));
    }
  });
  return true;
}
