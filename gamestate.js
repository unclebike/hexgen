// gamestate.js — Game state and rules
// The game object is mutated in place. update() and the input handlers return
// a list of events (clears, level-ups, game over) for audio and effects. Times
// are in seconds, as in the iOS app's Engine.swift, which these rules mirror.

import { dialCells, key } from './grid.js';
import { rotateDial } from './rotation.js';
import { findHexes } from './hexdetect.js';
import { stepGravity, spawnPiece, spawnDealt, nextMove, POWER_CHANCE } from './dropper.js';
import {
  BOARDS, SPEEDS, INITIAL_COLORS, HEXES_PER_LEVEL, SPECTRUM_HEXES_PER_LEVEL, SPECTRUM_INITIAL_COLORS,
  spawnIntervalFor, winHexes,
} from './progression.js';
import {
  dailyStreams, junkyardPile, hexValue, OVERTIME_PER_HEX, OVERTIME_CAP, SURGE_POWER_CHANCE,
} from './daily.js';
import { randomElement } from './rng.js';

export const FALL_STEP = 0.14;  // seconds per row of falling, at normal speed
export const CLEAR_TIME = 0.45; // seconds a completed hex flashes before vanishing
export const ROTATE_TIME = 0.12;
export const SPRINT_LENGTH = 180;

const shuffle = items => {
  const out = [...items];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
};
const pick = items => items[Math.floor(Math.random() * items.length)];

/**
 * A new game. `daily` plays that day's challenge: a SPRINT at normal speed on the
 * standard board, dealt from the day's fixed sequence with its modifiers.
 */
export function createGame({ mode = 'main', speed = 'normal', board = 'standard', assisted = false, daily = null } = {}) {
  if (daily) {
    mode = 'sprint';
    speed = 'normal';
    board = 'standard';
    assisted = false;
  }
  const { grid, pace: boardPace, colorCount } = BOARDS[board];
  // Start the dial low in the middle, where the first triangles land
  const start = grid.nearestDial(grid.size * 0.5, 0);
  const pace = SPEEDS[speed].pace * boardPace;
  const modifiers = new Set(daily ? daily.modifiers : []);
  const game = {
    grid,
    board: new Map(), // key(r, c) → piece; empty cells are absent
    mode,
    speed,
    boardSize: board,
    assisted,
    rescued: false,
    daily,
    modifiers,
    streams: daily ? dailyStreams(daily.seed) : null,
    phase: 'playing', // 'playing' | 'paused' | 'gameover'
    won: false,
    score: 0,
    level: 2,
    hexesCleared: 0,
    hexesThisLevel: 0,
    activeColors: INITIAL_COLORS,
    colorOrder: Array.from({ length: colorCount }, (_, i) => i),
    colorHexes: new Array(colorCount).fill(0), // hexes cleared of each colour
    pace,
    stepTime: FALL_STEP * pace,
    spawnInterval: 0,
    spawnTimer: 0,
    fallTimer: 0,
    nextPieceID: 0,
    cursor: { k: start.k, j: start.j, stickyJ: start.j },
    rotAnim: null,
    sprintTimeRemaining: mode === 'sprint' ? SPRINT_LENGTH : null,
    lastSwap: null,
    wantedColor: null,
    overtimeAdded: 0,
  };

  if (mode === 'main') {
    game.colorOrder = shuffle(game.colorOrder);
    game.activeColors = game.colorOrder.slice(0, SPECTRUM_INITIAL_COLORS);
    game.level = game.activeColors.length;
  }
  game.spawnInterval = intervalFor(game, game.level);
  if (modifiers.has('fullSpectrum')) game.activeColors = Array.from({ length: colorCount }, (_, i) => i);
  if (modifiers.has('junkyard')) {
    game.board = junkyardPile(grid, game.streams.pileSeed);
    game.nextPieceID = Math.max(-1, ...[...game.board.values()].map(p => p.id)) + 1;
  }
  if (modifiers.has('wanted')) game.wantedColor = pickWanted(game);
  return game;
}

/** Seconds between new triangles at `level`, at this game's pace. */
function intervalFor(game, level) {
  return spawnIntervalFor(level, game.assisted) * game.pace * (game.modifiers.has('downpour') ? 2 : 1);
}

/** How far (0…1) pieces have moved from their `from` cell toward their current one. */
export const fallProgress = game => Math.min(1, game.fallTimer / game.stepTime);

/** How full the bin is (0…1). */
export const binFill = game => game.board.size / game.grid.cells.length;

/** Gravity is suspended in the six cells under the dial. */
export function heldCells(game) {
  const { k, j } = game.cursor;
  return new Set(dialCells(k, j).map(({ r, c }) => key(r, c)));
}

/** Whether the dial is holding up a piece that would fall without it. */
export function isHoldingPiece(game) {
  const { k, j } = game.cursor;
  return dialCells(k, j).some(({ r, c }) => {
    const p = game.board.get(key(r, c));
    return p && !(p.clearT > 0) && nextMove(game.grid, game.board, r, c) !== null;
  });
}

/** Advance the game by dt seconds. Returns events. */
export function update(game, dt) {
  const events = [];
  if (game.phase !== 'playing') return events;

  if (game.sprintTimeRemaining !== null) {
    const remaining = game.sprintTimeRemaining;
    game.sprintTimeRemaining = Math.max(0, remaining - dt);
    if (remaining - dt <= 0) {
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
    if (p.clearT > 0) {
      p.clearT -= dt;
      if (p.clearT <= 0) game.board.delete(k);
    }
  }

  // Falling and spawning both run on the same step clock, so new triangles
  // enter in sync with the ones already falling.
  game.fallTimer += dt;
  let steps = 0;
  while (game.fallTimer >= game.stepTime) {
    if (steps === 3) { // fell far behind (tab was hidden); don't fast-forward
      game.fallTimer = 0;
      break;
    }
    steps++;
    game.fallTimer -= game.stepTime;
    stepGravity(game.grid, game.board, heldCells(game));

    game.spawnTimer -= game.stepTime;
    if (game.spawnTimer <= 0) {
      game.spawnTimer += game.spawnInterval;
      // DOWNPOUR brings two at a time
      for (let i = game.modifiers.has('downpour') ? 2 : 1; i > 0; i--) {
        const result = spawnNext(game);
        if (result === 'full') {
          if (game.assisted && !game.rescued) {
            // Once a game, a new player's full bin drains instead of ending
            game.rescued = true;
            applyPower(game, 'drain', events, true);
          } else {
            endGame(game, events);
            return events;
          }
        } else if (result === 'spawned') {
          game.nextPieceID++;
          events.push({ type: 'spawn' });
        }
      }
    }
  }

  detectClears(game, events);
  return events;
}

function spawnNext(game) {
  const { grid, board, activeColors, streams, modifiers, nextPieceID } = game;
  if (streams) {
    const surge = modifiers.has('powerSurge');
    return spawnDealt(grid, board, activeColors, nextPieceID, streams.deal,
      surge ? SURGE_POWER_CHANCE : POWER_CHANCE, surge);
  }
  return spawnPiece(grid, board, activeColors, nextPieceID, game.assisted);
}

/**
 * The colours of a daily's next `count` triangles, if the colours in play stay as
 * they are (a new colour reshuffles them); empty outside a daily.
 */
export function upcomingColors(game, count) {
  if (!game.streams) return [];
  const deal = game.streams.deal.clone();
  const n = BigInt(game.activeColors.length);
  return Array.from({ length: count }, () => game.activeColors[Number(deal.next().color % n)]);
}

/** A colour in play for WANTED to want, other than the one it wanted last when there's a choice. */
function pickWanted(game) {
  const { activeColors, wantedColor } = game;
  const choices = activeColors.length > 1 ? activeColors.filter(c => c !== wantedColor) : activeColors;
  return choices[Number(game.streams.wanted.next() % BigInt(choices.length))];
}

function detectClears(game, events) {
  const { grid, board, modifiers } = game;
  const hexes = findHexes(grid, board, heldCells(game));
  if (hexes.length === 0) return;

  const powers = [];
  for (const hex of hexes) {
    for (const { r, c } of hex.cells) {
      const p = board.get(key(r, c));
      if (p.clearT > 0) continue; // shared with another hex found this pass
      p.clearT = CLEAR_TIME;
      if (p.power) powers.push(p.power);
    }
  }

  const value = hexValue(hexes, game.wantedColor, modifiers);
  const points = Math.round(100 * game.level * value * SPEEDS[game.speed].points);
  game.score += points;
  game.hexesCleared += hexes.length;
  game.hexesThisLevel += hexes.length;
  for (const hex of hexes) game.colorHexes[hex.color]++;
  events.push({ type: 'clear', hexes, points });

  if (game.wantedColor !== null && hexes.some(hex => hex.color === game.wantedColor)) {
    game.wantedColor = pickWanted(game);
  }
  if (modifiers.has('overtime') && game.sprintTimeRemaining !== null) {
    const added = Math.min(OVERTIME_PER_HEX * hexes.length, OVERTIME_CAP - game.overtimeAdded);
    game.overtimeAdded += added;
    game.sprintTimeRemaining += added;
  }

  for (const power of powers) applyPower(game, power, events);

  const colorCount = BOARDS[game.boardSize].colorCount;
  const perLevel = game.mode === 'main' ? SPECTRUM_HEXES_PER_LEVEL : HEXES_PER_LEVEL;
  if (game.hexesThisLevel >= perLevel && game.activeColors.length < colorCount) {
    const color = game.colorOrder[game.activeColors.length];
    game.activeColors = [...game.activeColors, color];
    game.hexesThisLevel -= perLevel;
    game.level = game.activeColors.length;
    game.spawnInterval = intervalFor(game, game.level);
    events.push({ type: 'levelup', color });
  } else if (modifiers.has('fullSpectrum') && game.hexesThisLevel >= HEXES_PER_LEVEL && game.level < colorCount) {
    // Every colour is already in, so the level climbs (and the pace with it) with no new colour to show
    game.hexesThisLevel -= HEXES_PER_LEVEL;
    game.level++;
    game.spawnInterval = intervalFor(game, game.level);
  }
  if (game.mode === 'main' && game.hexesCleared >= winHexes(game.boardSize)) {
    game.won = true;
    endGame(game, events);
  }
}

/** Glowing triangles fire when they're cleared. */
function applyPower(game, power, events, rescue = false) {
  const { grid, board, activeColors, streams } = game;
  if (power === 'drain') {
    // Empty the bottom two triangle-heights of the bin (lattice x is down)
    for (const { r, c } of grid.cells) {
      const p = board.get(key(r, c));
      if (grid.cellCenter(r, c).x > grid.size - 2 && p && !(p.clearT > 0)) board.delete(key(r, c));
    }
  } else if (power === 'swap' && activeColors.length > 1) {
    // Turn every triangle of one colour into another. A daily's swaps come
    // from their own generator, so they never shift the deal.
    const choose = items => (streams ? randomElement(items, streams.swaps) : pick(items));
    const from = choose(activeColors);
    const to = choose(activeColors.filter(color => color !== from));
    for (const p of board.values()) {
      if (p.color === from && !(p.clearT > 0)) p.color = to;
    }
    game.lastSwap = { from, to };
  }
  events.push({ type: 'power', power, rescue });
}

function endGame(game, events) {
  game.phase = 'gameover';
  events.push({ type: 'gameover', won: game.won });
}

/** Turn the dial. dir: 1 = clockwise, -1 = counter-clockwise. */
export function rotate(game, dir) {
  if (game.phase !== 'playing' || (game.modifiers.has('oneWay') && dir === -1)) return [];
  const { k, j } = game.cursor;
  if (!rotateDial(game.grid, game.board, k, j, dir)) return [];
  for (const { r, c } of dialCells(k, j)) {
    const p = game.board.get(key(r, c));
    if (p) p.from = null;
  }
  game.rotAnim = { k, j, dir, t: 0 };
  return [{ type: 'rotate' }];
}

/** Put the dial on a vertex. */
export function moveCursorTo(game, dial) {
  if (game.phase !== 'playing' || !dial || !game.grid.isDial(dial.k, dial.j)) return;
  game.cursor = { k: dial.k, j: dial.j, stickyJ: dial.j };
}

/**
 * Nudge the dial with the keyboard. On screen the lattice is turned 90°:
 * up/down move along a lattice row (j ∓ 2), and left/right step to the
 * neighbouring row, drifting back toward the height you were last at.
 */
export function moveCursorDir(game, direction) {
  if (game.phase !== 'playing') return;
  const { grid } = game;
  const { k, j, stickyJ } = game.cursor;

  if (direction === 'up' || direction === 'down') {
    const nj = j + (direction === 'up' ? -2 : 2);
    if (grid.isDial(k, nj)) game.cursor = { k, j: nj, stickyJ: nj };
    return;
  }

  const nk = k + (direction === 'left' ? 1 : -1);
  const options = [j - 1, j + 1]
    .filter(nj => grid.isDial(nk, nj))
    .sort((a, b) => Math.abs(a - stickyJ) - Math.abs(b - stickyJ));
  if (options.length) game.cursor = { k: nk, j: options[0], stickyJ };
}

export function togglePause(game) {
  if (game.phase === 'playing') game.phase = 'paused';
  else if (game.phase === 'paused') game.phase = 'playing';
}
