// progression.js — Colors, levels, and pace

// Color palette in order of introduction
export const COLOR_PALETTE = [
  '#4CAF50', // 0: green
  '#FF9800', // 1: orange
  '#FFEB3B', // 2: yellow
  '#F44336', // 3: red
  '#2196F3', // 4: blue
  '#9C27B0', // 5: purple
  '#00BCD4', // 6: cyan
  '#2E7D32', // 7: dark green
];

export const EMPTY_COLOR = '#1a1a2e';
export const BOARD_BG = '#0f0f23';

export const HEXES_PER_LEVEL = 6;
const WIN_HEXES = HEXES_PER_LEVEL * COLOR_PALETTE.length; // 48: six of each colour

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
  if (game.hexesThisLevel < HEXES_PER_LEVEL || game.activeColors.length >= COLOR_PALETTE.length) return false;
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
