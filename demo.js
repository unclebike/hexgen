// demo.js — A simple auto-player for the game running behind the menu
//
// Every so often it tries every dial and turn on a copy of the board, takes the
// one that clears the most hexes (or, failing that, gathers the most same-
// coloured triangles around a vertex), glides the dial there, and turns it.
// It's greedy and a little noisy on purpose, so it plays like a person.

import { COLOR_COUNT } from './progression.js';
import { dialCells, key } from './grid.js';
import { update, rotate, moveCursorTo, ROTATE_TIME } from './gamestate.js';
import { findHexes } from './hexdetect.js';
import { rotateDial } from './rotation.js';

const THINK_TIME = 0.42; // seconds between decisions
const MOVE_TIME = 0.14;  // between a move and its turn, so the dial is seen travelling
const OPTIONS = [[1], [-1], [1, 1]];

export class DemoPlayer {
  /** Only dials wholly below `floor` (lattice x) are played, so the demo keeps clear of the menu's logo. */
  constructor(floor = -Infinity) {
    this.floor = floor;
    this.pending = [];
    this.timer = 0;
  }

  /** Advance the demo by dt seconds, playing a move when one is due. */
  update(game, dt) {
    const events = update(game, dt);
    if (game.phase !== 'playing') return events;
    this.timer -= dt;
    if (this.timer > 0) return events;

    if (this.pending.length) {
      events.push(...rotate(game, this.pending.shift()));
      this.timer = this.pending.length ? ROTATE_TIME + 0.04 : THINK_TIME;
      return events;
    }
    const move = bestMove(game, this.floor);
    if (move) {
      moveCursorTo(game, move.dial);
      this.pending = [...move.turns];
      this.timer = MOVE_TIME;
    } else {
      this.timer = THINK_TIME;
    }
    return events;
  }
}

/** The best dial and the turns to play there, or null on an empty board. */
function bestMove(game, floor) {
  const { grid, board } = game;
  let best = null;
  for (const dial of grid.dials) {
    // A dial reaches one side above its vertex
    if (grid.vertexXY(dial.k, dial.j).x - 1 < floor) continue;
    const cells = dialCells(dial.k, dial.j);
    // Only dials holding enough triangles to be worth turning
    if (cells.filter(({ r, c }) => board.has(key(r, c))).length < 3) continue;
    const held = new Set(cells.map(({ r, c }) => key(r, c)));
    for (const turns of OPTIONS) {
      const trial = new Map(board);
      if (!turns.every(dir => rotateDial(grid, trial, dial.k, dial.j, dir))) continue;
      const score = findHexes(grid, trial, held).length * 1000 + clustering(grid, trial) + Math.random() * 6;
      if (!best || score > best.score) best = { score, dial, turns };
    }
  }
  return best;
}

/** How close the board is to hexes: for every dial, the square of its largest group of one colour. */
function clustering(grid, board) {
  let total = 0;
  const counts = new Array(COLOR_COUNT).fill(0);
  for (const { k, j } of grid.dials) {
    counts.fill(0);
    for (const { r, c } of dialCells(k, j)) {
      const p = board.get(key(r, c));
      if (p && !(p.clearT > 0)) counts[p.color]++;
    }
    const most = Math.max(...counts);
    total += most * most;
  }
  return total;
}
