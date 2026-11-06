// progression.js — Speeds, board sizes, levels, and pace
// The colours themselves belong to the active skin (skins.js, skins.json).

import { GRIDS } from './grid.js';

export const HEXES_PER_LEVEL = 6;
export const COLOR_COUNT = 8;
// SPECTRUM introduces colours faster, so all eight are in play halfway through a win
export const SPECTRUM_HEXES_PER_LEVEL = 4;
export const SPECTRUM_INITIAL_COLORS = 3;
export const INITIAL_COLORS = [0, 1];

// A new player's first few games ease them in: the opening level is slower, each
// new colour arrives without also speeding things up, and a full bin is drained
// once instead of ending the game. Points are scored as normal.
export const ASSISTED_GAMES = 3;
const ASSISTED_PACE_LAG = 2;

/** How fast triangles fall and arrive; turning and clearing keep their timing. */
export const SPEEDS = {
  slow: { pace: 1.4, points: 0.5 },
  normal: { pace: 1, points: 1 },
  fast: { pace: 0.7, points: 1.5 },
};

/**
 * Which bin a solo game is played in. A big board has fewer, larger triangles and
 * works up to fewer colours; its pace keeps triangles crossing the screen about
 * as fast as on the usual board.
 */
export const BOARDS = {
  standard: { grid: GRIDS.standard, colorCount: COLOR_COUNT, pace: 1 },
  big: { grid: GRIDS.big, colorCount: 6, pace: GRIDS.standard.size / GRIDS.big.size },
};

/** MAIN is won after six hexes of every colour. */
export const winHexes = board => HEXES_PER_LEVEL * BOARDS[board].colorCount;

/** Seconds between new triangles. */
function baseInterval(level) {
  return Math.max(0.7, 1.8 - 0.15 * (level - 2));
}

/** Seconds between new triangles, eased in an assisted game. */
export function spawnIntervalFor(level, assisted) {
  if (!assisted) return baseInterval(level);
  if (level <= 2) return baseInterval(2) * SPEEDS.slow.pace;
  return baseInterval(Math.max(2, level - ASSISTED_PACE_LAG));
}
