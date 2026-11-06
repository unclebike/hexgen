// dropper.js — Triangles raining into the bin, and falling once they're in
//
// On screen the bin stands on a vertex, so the lattice's rows are vertical
// columns and "down" is +c along a row. A triangle falls straight down its
// column, two cells at a time so it keeps its shape, and lands as soon as the
// cell below it is taken. Only the bin's slanted bottom walls make it slide:
// at the foot of a column it steps into the next column toward the bottom
// point and carries on falling.

import { dialCells, key } from './grid.js';

export const POWER_CHANCE = 0.04;
// How often a gentle spawn picks a colour a nearly finished hex is waiting for
const GENTLE_COLOR_CHANCE = 0.35;

const pick = items => items[Math.floor(Math.random() * items.length)];
const isOpen = (grid, board, r, c) => grid.isCell(r, c) && !board.has(key(r, c));

/** Where the piece at (r, c) moves next, or null if it has landed. */
export function nextMove(grid, board, r, c) {
  if (grid.isCell(r, c + 1)) {
    if (board.has(key(r, c + 1))) return null; // resting on the triangle below
    // Fall a full edge (two cells, same shape), or one cell into the last gap
    return isOpen(grid, board, r, c + 2) ? { r, c: c + 2 } : { r, c: c + 1 };
  }
  // The foot of the column, against a slanted wall: slide one column inward,
  // into the open cell next to us that is lower down
  const inward = r < grid.size ? r + 1 : r - 1;
  const here = grid.cellCenter(r, c);
  let best = null;
  let bestD = Infinity;
  for (let nc = c - 1; nc <= c + 2; nc++) {
    if (!isOpen(grid, board, inward, nc)) continue;
    const there = grid.cellCenter(inward, nc);
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
export function isResting(grid, board, r, c) {
  return nextMove(grid, board, r, c) === null;
}

/**
 * Move every loose piece one step. Mutates the board. `held` is a set of cell
 * keys whose pieces don't fall: the six cells under the dial. Pieces from
 * outside can still fall into an empty held cell, and are held from then on.
 * Each piece records where it came from, so the renderer can animate the move.
 */
export function stepGravity(grid, board, held = new Set()) {
  for (const p of board.values()) p.from = null;
  const moved = new Set();
  for (const { r, c } of grid.gravityOrder) {
    const p = board.get(key(r, c));
    if (!p || held.has(key(r, c)) || moved.has(p.id) || p.clearT > 0) continue;
    const move = nextMove(grid, board, r, c);
    if (!move) continue;
    board.delete(key(r, c));
    board.set(key(move.r, move.c), p);
    p.from = { r, c };
    moved.add(p.id);
  }
}

const anyGlowing = board => [...board.values()].some(p => p.power);

/** Enter from just above the bin. */
const entering = (id, color, power, { r, c }) => ({ id, color, power, from: { r, c: c - 2 }, clearT: 0 });

function blockedResult(grid, board) {
  return grid.spawnCells.every(({ r, c }) => isResting(grid, board, r, c)) ? 'full' : 'wait';
}

/**
 * Drop a new triangle into the top of a random open column; a full column just
 * stops taking new ones. Returns 'full' when every column is stacked to its
 * top, 'wait' when the tops are only blocked by triangles still falling. A
 * `gentle` spawn (an assisted game) leans toward emptier columns and toward
 * colours a hex is waiting for.
 */
export function spawnPiece(grid, board, colors, id, gentle = false) {
  const open = grid.spawnCells.filter(({ r, c }) => !board.has(key(r, c)));
  if (open.length === 0) return blockedResult(grid, board);

  const cell = gentle ? roomiest(grid, board, open) : pick(open);
  let color = pick(colors);
  if (gentle && Math.random() < GENTLE_COLOR_CHANCE) {
    const wanted = wantedColors(grid, board, colors);
    if (wanted.length) color = pick(wanted);
  }
  let power = null;
  if (!anyGlowing(board) && Math.random() < POWER_CHANCE) power = Math.random() < 0.5 ? 'drain' : 'swap';
  board.set(key(cell.r, cell.c), entering(id, color, power, cell));
  return 'spawned';
}

/**
 * Drop the next triangle of a fixed deal (the Daily Dial's). A roll is only taken
 * when a triangle actually enters, so the nth triangle is rolled the same however
 * the game has gone. It glows at `powerChance`, and unless `manyPowers`, only
 * while nothing else on the board does.
 */
export function spawnDealt(grid, board, colors, id, deal, powerChance, manyPowers) {
  const open = grid.spawnCells.filter(({ r, c }) => !board.has(key(r, c)));
  if (open.length === 0) return blockedResult(grid, board);

  const roll = deal.next();
  const cell = open[Math.min(open.length - 1, Math.floor(roll.column * open.length))];
  const color = colors[Number(roll.color % BigInt(colors.length))];
  const canGlow = manyPowers || !anyGlowing(board);
  const power = canGlow && roll.power < powerChance ? (roll.drain ? 'drain' : 'swap') : null;
  board.set(key(cell.r, cell.c), entering(id, color, power, cell));
  return 'spawned';
}

/** One of the open column tops, weighted by how many empty cells its column has. */
function roomiest(grid, board, open) {
  const weights = open.map(top => grid.columns[top.r].filter(({ r, c }) => !board.has(key(r, c))).length);
  let roll = Math.random() * Math.max(1, weights.reduce((a, b) => a + b, 0));
  for (let i = 0; i < open.length; i++) {
    roll -= weights[i];
    if (roll < 0) return open[i];
  }
  return open[open.length - 1];
}

/**
 * Colours that are the only thing missing from a dial: four or more of the
 * colour around a vertex, and the rest of its cells empty.
 */
function wantedColors(grid, board, colors) {
  const wanted = new Set();
  for (const { k, j } of grid.dials) {
    const pieces = dialCells(k, j).map(({ r, c }) => board.get(key(r, c))).filter(Boolean);
    if (pieces.length < 4 || pieces.length >= 6) continue;
    const { color } = pieces[0];
    if (colors.includes(color) && pieces.every(p => p.color === color && !(p.clearT > 0))) wanted.add(color);
  }
  return [...wanted];
}
