// dropper.js — Triangles raining into the bin, and falling once they're in
//
// A triangle can't flip as it falls, so it moves diagonally one row at a time,
// (r, c) → (r+1, c±1), which keeps its orientation. It alternates left and
// right, so in open space it zig-zags straight down. It lands the moment its
// next step is blocked by another triangle, even if there's a gap beside it.
// Only the bin's slanted walls make it slide: when its next step would leave
// the bin, it takes the other diagonal, running down along the wall.

import { ROWS, CELLS, TOP_CELLS, isCell, key } from './grid.js';

const POWER_CHANCE = 0.04;
const rows = Array.from({ length: ROWS }, (_, r) => CELLS.filter(cell => cell.r === r));

/** Where the piece at (r, c) moves next, or null if it has landed. */
function nextMove(board, r, c, zig) {
  for (const dir of [zig, -zig]) {
    if (!isCell(r + 1, c + dir)) continue; // a wall: slide along it
    if (board.has(key(r + 1, c + dir))) return null; // a triangle: land
    return { r: r + 1, c: c + dir, dir };
  }
  return null; // walls on both sides: the floor
}

/** A piece is resting once it has landed. */
export function isResting(board, r, c) {
  const p = board.get(key(r, c));
  return nextMove(board, r, c, p ? p.zig : 1) === null;
}

/**
 * Move every loose piece one step. Mutates the board.
 * Each piece records where it came from, so the renderer can animate the move.
 */
export function stepGravity(board, tick) {
  for (const p of board.values()) p.from = null;

  for (let r = ROWS - 1; r >= 0; r--) {
    // Alternate scan direction so neither side wins every race for a slot
    const row = tick % 2 ? rows[r] : [...rows[r]].reverse();
    for (const { c } of row) {
      const p = board.get(key(r, c));
      if (!p || p.from || p.clearT > 0) continue; // already moved this step, or clearing
      const move = nextMove(board, r, c, p.zig);
      if (!move) continue;
      board.delete(key(r, c));
      board.set(key(move.r, move.c), p);
      p.from = { r, c };
      p.zig = -move.dir; // alternate, so it zig-zags straight down
    }
  }
}

/**
 * Drop a new triangle into a random empty cell on the top row.
 * Returns false when the bin is full: a resting triangle already sits on the top row.
 */
export function spawnPiece(board, activeColors) {
  if (TOP_CELLS.some(({ r, c }) => board.has(key(r, c)) && isResting(board, r, c))) return false;

  const open = TOP_CELLS.filter(({ r, c }) => !board.has(key(r, c)));
  if (open.length === 0) return false;

  const { r, c } = open[Math.floor(Math.random() * open.length)];
  const zig = Math.random() < 0.5 ? -1 : 1;
  const hasPower = [...board.values()].some(p => p.power);
  board.set(key(r, c), {
    color: activeColors[Math.floor(Math.random() * activeColors.length)],
    power: !hasPower && Math.random() < POWER_CHANCE ? (Math.random() < 0.5 ? 'drain' : 'swap') : null,
    zig: -zig,
    from: { r: r - 1, c: c - zig }, // enter from above the bin
    clearT: 0,
  });
  return true;
}
