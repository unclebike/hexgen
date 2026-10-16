// dropper.js — Triangles raining into the bin, and falling once they're in
//
// On screen the bin stands on a vertex, so the lattice's rows are vertical
// columns and "down" is +c along a row. A triangle falls straight down its
// column, two cells at a time so it keeps its shape, and lands as soon as the
// cell below it is taken. Only the bin's slanted bottom walls make it slide:
// at the foot of a column it steps into the next column toward the bottom
// point and carries on falling.

import { ROWS, SIZE, CELLS, isCell, cellCenter, key } from './grid.js';

const POWER_CHANCE = 0.04;

// Column r, top to bottom
const columns = Array.from({ length: ROWS }, (_, r) =>
  CELLS.filter(cell => cell.r === r).sort((a, b) => a.c - b.c));

/** The top cell of every column: where new triangles enter. */
export const SPAWN_CELLS = columns.map(col => col[0]);

const isOpen = (board, r, c) => isCell(r, c) && !board.has(key(r, c));

/** Where the piece at (r, c) moves next, or null if it has landed. */
function nextMove(board, r, c) {
  if (isCell(r, c + 1)) {
    if (board.has(key(r, c + 1))) return null; // resting on the triangle below
    // Fall a full edge (two cells, same shape), or one cell into the last gap
    return isOpen(board, r, c + 2) ? { r, c: c + 2 } : { r, c: c + 1 };
  }
  // The foot of the column, against a slanted wall: slide one column inward,
  // into the open cell next to us that is lower down
  const inward = r < SIZE ? r + 1 : r - 1;
  const here = cellCenter(r, c);
  let best = null;
  let bestD = Infinity;
  for (let nc = c - 1; nc <= c + 2; nc++) {
    if (!isOpen(board, inward, nc)) continue;
    const there = cellCenter(inward, nc);
    if (there.x <= here.x + 1e-9) continue; // must be lower on screen
    const d = (there.x - here.x) ** 2 + (there.y - here.y) ** 2;
    if (d < bestD) {
      bestD = d;
      best = { r: inward, c: nc };
    }
  }
  return best;
}

/** A piece is resting once it has landed. */
export function isResting(board, r, c) {
  return nextMove(board, r, c) === null;
}

/**
 * Move every loose piece one step. Mutates the board.
 * `held` is a set of cell keys whose pieces don't fall: the six cells under
 * the dial. Pieces from outside can still fall into an empty held cell, and
 * are held from then on.
 * Each piece records where it came from, so the renderer can animate the move.
 */
export function stepGravity(board, held) {
  for (const p of board.values()) p.from = null;

  // Bottom of each column first, so a falling stack moves together
  const order = [...CELLS].sort((a, b) => b.c - a.c);
  for (const { r, c } of order) {
    const p = board.get(key(r, c));
    // Skip pieces that already moved this step, are clearing, or are held
    if (!p || p.from || p.clearT > 0 || held.has(key(r, c))) continue;
    const move = nextMove(board, r, c);
    if (!move) continue;
    board.delete(key(r, c));
    board.set(key(move.r, move.c), p);
    p.from = { r, c };
  }
}

/**
 * Drop a new triangle into the top of a random open column; a full column
 * just stops taking new ones. Returns 'full' when every column is stacked to
 * its top, 'wait' when the tops are only blocked by triangles still falling.
 */
export function spawnPiece(board, activeColors) {
  const open = SPAWN_CELLS.filter(({ r, c }) => !board.has(key(r, c)));
  if (open.length === 0) {
    return SPAWN_CELLS.every(({ r, c }) => isResting(board, r, c)) ? 'full' : 'wait';
  }

  const { r, c } = open[Math.floor(Math.random() * open.length)];
  const hasPower = [...board.values()].some(p => p.power);
  board.set(key(r, c), {
    color: activeColors[Math.floor(Math.random() * activeColors.length)],
    power: !hasPower && Math.random() < POWER_CHANCE ? (Math.random() < 0.5 ? 'drain' : 'swap') : null,
    from: { r, c: c - 2 }, // enter from above the bin
    clearT: 0,
  });
  return 'spawned';
}
