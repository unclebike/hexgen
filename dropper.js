// dropper.js — Triangles raining into the bin, and falling once they're in
//
// A triangle can't flip as it falls, so it moves diagonally one row at a time,
// (r, c) → (r+1, c±1), which keeps its orientation. It alternates left and
// right, so in open space it zig-zags straight down. A triangle that can't
// fall slides along its row toward the nearest spot where it can, so the bin
// fills level instead of piling up in the middle. It rests once it can do
// neither.

import { ROWS, CELLS, TOP_CELLS, isCell, key } from './grid.js';

const POWER_CHANCE = 0.04;
const rows = Array.from({ length: ROWS }, (_, r) => CELLS.filter(cell => cell.r === r));

const isOpen = (board, r, c) => isCell(r, c) && !board.has(key(r, c));
const canDrop = (board, r, c, dir) => isOpen(board, r + 1, c + dir);

/**
 * Where the piece at (r, c) moves next, or null if it's resting.
 * Prefers falling (toward `zig` first), then sliding sideways toward the
 * nearest open drop along its row.
 */
function nextMove(board, r, c, zig) {
  for (const dir of [zig, -zig]) {
    if (canDrop(board, r, c, dir)) return { r: r + 1, c: c + dir, dir };
  }
  // Same-orientation neighbours along the row are two columns apart
  for (let dist = 2; dist < 4 * ROWS; dist += 2) {
    for (const dir of [zig, -zig]) {
      const nc = c + dir * dist;
      if (!isOpen(board, r, nc)) continue;
      // The path to it must be clear too
      let clear = true;
      for (let d = 2; d < dist; d += 2) {
        if (!isOpen(board, r, c + dir * d)) { clear = false; break; }
      }
      if (clear && (canDrop(board, r, nc, -1) || canDrop(board, r, nc, 1))) {
        return { r, c: c + dir * 2, dir };
      }
    }
  }
  return null;
}

/** A piece is resting when it has nowhere to fall or slide. */
export function isResting(board, r, c) {
  return nextMove(board, r, c, 1) === null;
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
      // Alternate after a fall; keep heading the same way while sliding
      p.zig = move.r > r ? -move.dir : move.dir;
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
