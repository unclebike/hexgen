// progression.js — Levels and pace
// The colours themselves belong to the active skin (skins.js, skins.json).

// Piece colours, introduced one per level
export const PIECE_COUNT = 8;

export const HEXES_PER_LEVEL = 6;
const WIN_HEXES = HEXES_PER_LEVEL * PIECE_COUNT; // 48: six of each colour

// Time between new triangles, in ms
const INITIAL_SPAWN_INTERVAL = 1800;
const SPAWN_INTERVAL_STEP = 150;
const MIN_SPAWN_INTERVAL = 700;

export function getInitialColors() {
  return [0, 1];
}

export function spawnIntervalFor(level) {
  return Math.max(MIN_SPAWN_INTERVAL, INITIAL_SPAWN_INTERVAL - SPAWN_INTERVAL_STEP * (level - 2));
}

/**
 * Add the next colour once enough hexes have been cleared at this level.
 * Mutates the game. Returns true if it levelled up.
 */
export function checkProgression(game) {
  if (game.hexesThisLevel < HEXES_PER_LEVEL || game.activeColors.length >= PIECE_COUNT) return false;
  game.activeColors = [...game.activeColors, game.activeColors.length];
  game.hexesThisLevel -= HEXES_PER_LEVEL;
  game.level = game.activeColors.length;
  game.spawnInterval = spawnIntervalFor(game.level);
  return true;
}

/** Main mode is won after six hexes of every colour. */
export function checkWinCondition(game) {
  return game.mode === 'main' && game.hexesCleared >= WIN_HEXES;
}
