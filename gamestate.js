// gamestate.js — Game state and rules
// The game object is mutated in place. update() and the input handlers return
// a list of events (clears, level-ups, game over) for audio and effects.

import { SIZE, CELLS, isDial, nearestDial, cellCenter, dialCells, key } from './grid.js';
import { rotateDial } from './rotation.js';
import { findHexes } from './hexdetect.js';
import { stepGravity, spawnPiece, isResting } from './dropper.js';
import { getInitialColors, spawnIntervalFor, checkProgression, checkWinCondition } from './progression.js';
import { calculateScore, saveHighScore } from './scoring.js';

export const FALL_STEP = 140;  // ms per row of falling
export const CLEAR_TIME = 450; // ms a completed hex flashes before vanishing
export const ROTATE_TIME = 120;

export function createGame(mode = 'main') {
  // Start the dial low in the middle, where the first triangles land
  const start = nearestDial(SIZE * 0.5, 0); // lattice x is down on screen
  return {
    board: new Map(), // key(r, c) → piece; empty cells are absent
    mode,
    phase: 'playing', // 'playing' | 'paused' | 'gameover'
    won: false,
    score: 0,
    level: 2,
    hexesCleared: 0,
    hexesThisLevel: 0,
    activeColors: getInitialColors(),
    spawnInterval: spawnIntervalFor(2),
    spawnTimer: 0,
    fallTimer: 0,
    tick: 0,
    cursor: { k: start.k, j: start.j, stickyJ: start.j },
    rotAnim: null,
    sprintTimeRemaining: mode === 'sprint' ? 180000 : -1,
  };
}

/** Advance the game by dt ms. Returns events. */
export function update(game, dt) {
  const events = [];
  if (game.phase !== 'playing') return events;

  if (game.mode === 'sprint') {
    game.sprintTimeRemaining -= dt;
    if (game.sprintTimeRemaining <= 0) {
      game.sprintTimeRemaining = 0;
      endGame(game, events);
      return events;
    }
  }

  if (game.rotAnim) {
    game.rotAnim.t += dt;
    if (game.rotAnim.t >= ROTATE_TIME) game.rotAnim = null;
  }

  // Finished clears leave holes for the triangles above to fall into
  for (const [k, p] of game.board) {
    if (p.holdT > 0) p.holdT -= dt;
    if (p.clearT > 0) {
      p.clearT -= dt;
      if (p.clearT <= 0) game.board.delete(k);
    }
  }

  // Falling and spawning both run on the same step clock, so new triangles
  // enter in sync with the ones already falling.
  game.fallTimer += dt;
  for (let steps = 0; game.fallTimer >= FALL_STEP; steps++) {
    if (steps === 3) { // fell far behind (tab was hidden); don't fast-forward
      game.fallTimer = 0;
      break;
    }
    game.fallTimer -= FALL_STEP;
    game.tick++;
    stepGravity(game.board);

    game.spawnTimer -= FALL_STEP;
    if (game.spawnTimer <= 0) {
      game.spawnTimer += game.spawnInterval;
      const result = spawnPiece(game.board, game.activeColors);
      if (result === 'full') {
        endGame(game, events);
        return events;
      }
      if (result === 'spawned') events.push({ type: 'spawn' });
    }
  }

  detectClears(game, events);
  return events;
}

function detectClears(game, events) {
  const hexes = findHexes(game.board, (r, c) => isResting(game.board, r, c));
  if (hexes.length === 0) return;

  const powers = [];
  for (const hex of hexes) {
    for (const { r, c } of hex.cells) {
      const p = game.board.get(key(r, c));
      if (p.clearT > 0) continue; // shared with another hex found this pass
      p.clearT = CLEAR_TIME;
      if (p.power) powers.push(p.power);
    }
  }

  const points = calculateScore(hexes.length, game.level);
  game.score += points;
  game.hexesCleared += hexes.length;
  game.hexesThisLevel += hexes.length;
  events.push({ type: 'clear', hexes, points });

  for (const power of powers) applyPower(game, power, events);

  if (checkProgression(game)) {
    events.push({ type: 'levelup', color: game.activeColors[game.activeColors.length - 1] });
  }
  if (checkWinCondition(game)) {
    game.won = true;
    endGame(game, events);
  }
}

/** Glowing triangles fire when they're cleared. */
function applyPower(game, power, events) {
  if (power === 'drain') {
    // Empty the bottom two triangle-heights of the bin (lattice x is down)
    for (const { r, c } of CELLS) {
      const p = game.board.get(key(r, c));
      if (cellCenter(r, c).x > SIZE - 2 && p && !(p.clearT > 0)) game.board.delete(key(r, c));
    }
  } else if (power === 'swap' && game.activeColors.length > 1) {
    // Turn every triangle of one colour into another
    const colors = game.activeColors;
    const from = colors[Math.floor(Math.random() * colors.length)];
    const others = colors.filter(color => color !== from);
    const to = others[Math.floor(Math.random() * others.length)];
    for (const p of game.board.values()) {
      if (p.color === from && !(p.clearT > 0)) p.color = to;
    }
  }
  events.push({ type: 'power', power });
}

function endGame(game, events) {
  game.phase = 'gameover';
  events.push({ type: 'gameover', won: game.won, newHighScore: saveHighScore(game.mode, game.score) });
}

/** Turn the dial. dir: 1 = clockwise, -1 = counter-clockwise. */
export function rotate(game, dir) {
  if (game.phase !== 'playing') return [];
  const { k, j } = game.cursor;
  if (!rotateDial(game.board, k, j, dir)) return [];
  // Hold the turned triangles still until the turn has played out, so they
  // don't fall mid-swing; only these pieces are drawn swinging.
  const pieces = dialCells(k, j).map(({ r, c }) => game.board.get(key(r, c))).filter(Boolean);
  for (const p of pieces) p.holdT = ROTATE_TIME;
  game.rotAnim = { k, j, dir, t: 0, pieces: new Set(pieces) };
  return [{ type: 'rotate' }];
}

/** Put the dial on a vertex. */
export function moveCursorTo(game, dial) {
  if (game.phase !== 'playing' || !dial || !isDial(dial.k, dial.j)) return;
  game.cursor = { k: dial.k, j: dial.j, stickyJ: dial.j };
}

/**
 * Nudge the dial with the keyboard. On screen the lattice is turned 90°:
 * up/down move along a lattice row (j ∓ 2), and left/right step to the
 * neighbouring row, drifting back toward the height you were last at.
 */
export function moveCursorDir(game, direction) {
  if (game.phase !== 'playing') return;
  const { k, j, stickyJ } = game.cursor;

  if (direction === 'up' || direction === 'down') {
    const nj = j + (direction === 'up' ? -2 : 2);
    if (isDial(k, nj)) game.cursor = { k, j: nj, stickyJ: nj };
    return;
  }

  const nk = k + (direction === 'left' ? 1 : -1);
  const options = [j - 1, j + 1]
    .filter(nj => isDial(nk, nj))
    .sort((a, b) => Math.abs(a - stickyJ) - Math.abs(b - stickyJ));
  if (options.length) game.cursor = { k: nk, j: options[0], stickyJ };
}

export function togglePause(game) {
  if (game.phase === 'playing') game.phase = 'paused';
  else if (game.phase === 'paused') game.phase = 'playing';
}
