// hexdetect.js — Completed Hexes, and hexes the player could finish with one turn

import { dialCells, key } from './grid.js';
import { isResting } from './dropper.js';
import { rotateDial } from './rotation.js';

/**
 * The completed Hex around dial (k, j), if there is one. Held triangles count as
 * settled even when they would otherwise still be falling.
 */
function hexAt(grid, board, k, j, held) {
  const cells = dialCells(k, j);
  const first = board.get(key(cells[0].r, cells[0].c));
  if (!first) return null;
  const complete = cells.every(({ r, c }) => {
    const p = board.get(key(r, c));
    return p && p.color === first.color && !(p.clearT > 0)
      && (held.has(key(r, c)) || isResting(grid, board, r, c));
  });
  return complete ? { k, j, color: first.color, cells } : null;
}

/** Every dial position holding a completed Hex. */
export function findHexes(grid, board, held = new Set()) {
  return grid.dials.map(({ k, j }) => hexAt(grid, board, k, j, held)).filter(Boolean);
}

/** Whether turning the dial at (k, j) one step, either way, completes a hex that isn't there already. */
export function finishesHex(grid, board, k, j) {
  const cells = dialCells(k, j);
  // A turn only moves what's in its six cells; it takes at least two to make anything new
  if (cells.filter(({ r, c }) => board.has(key(r, c))).length < 2) return false;
  const held = new Set(cells.map(({ r, c }) => key(r, c)));
  // A new hex has to take in one of the turned cells, so only the dials touching them can make one
  const nearby = grid.touching.get(key(k, j)) ?? [];
  const before = new Set(nearby.filter(d => hexAt(grid, board, d.k, d.j, held)).map(d => key(d.k, d.j)));
  return [1, -1].some(dir => {
    const trial = new Map(board);
    if (!rotateDial(grid, trial, k, j, dir)) return false;
    return nearby.some(d => !before.has(key(d.k, d.j)) && hexAt(grid, trial, d.k, d.j, held));
  });
}

/** A dial where one turn completes a hex, the closest to `cursor` if there are several. */
export function oneTurnFromHex(grid, board, cursor) {
  const here = grid.vertexXY(cursor.k, cursor.j);
  let best = null;
  let bestD = Infinity;
  for (const { k, j } of grid.dials) {
    if (!finishesHex(grid, board, k, j)) continue;
    const v = grid.vertexXY(k, j);
    const d = (v.x - here.x) ** 2 + (v.y - here.y) ** 2;
    if (d < bestD) {
      bestD = d;
      best = { k, j };
    }
  }
  return best;
}
