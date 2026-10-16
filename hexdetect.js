// hexdetect.js — Find completed Hexes: six same-coloured triangles around one vertex

import { DIALS, dialCells, key } from './grid.js';

/**
 * Scan every dial position for a completed Hex.
 * Only resting triangles count; isResting(r, c) says whether a cell's piece can still fall.
 * @returns {Array<{k, j, color, cells}>}
 */
export function findHexes(board, isResting) {
  const found = [];
  for (const { k, j } of DIALS) {
    const cells = dialCells(k, j);
    const first = board.get(key(cells[0].r, cells[0].c));
    if (!first) continue;
    const complete = cells.every(({ r, c }) => {
      const p = board.get(key(r, c));
      return p && p.color === first.color && !(p.clearT > 0) && isResting(r, c);
    });
    if (complete) found.push({ k, j, color: first.color, cells });
  }
  return found;
}
