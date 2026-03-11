// progression.js — Level and color progression

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

// Hexes needed to unlock next color
const HEXES_PER_LEVEL = 6;

// Starting drop interval in ms
const INITIAL_DROP_INTERVAL = 2000;
// Decrease per level
const DROP_INTERVAL_DECREASE = 100;
// Minimum drop interval
const MIN_DROP_INTERVAL = 600;

/**
 * Check if the player has earned a new color, and update state accordingly.
 * @param {GameState} state
 * @returns {GameState} - Updated state (may have new color added)
 */
export function checkProgression(state) {
  const newState = { ...state };

  // Check if enough hexes cleared this level to unlock next color
  if (newState.hexesThisLevel >= HEXES_PER_LEVEL && newState.activeColors.length < 8) {
    const nextColorIndex = newState.activeColors.length;
    newState.activeColors = [...newState.activeColors, nextColorIndex];
    newState.hexesThisLevel = newState.hexesThisLevel - HEXES_PER_LEVEL;
    newState.level = newState.activeColors.length;
    newState.dropInterval = Math.max(
      MIN_DROP_INTERVAL,
      INITIAL_DROP_INTERVAL - DROP_INTERVAL_DECREASE * (newState.level - 2)
    );
    newState.leveledUp = true;
  }

  return newState;
}

/**
 * Check if the game is won (main mode only).
 * Main mode ends after clearing hexes through all 8 colors.
 */
export function checkWinCondition(state) {
  if (state.mode === 'main') {
    // Win after 48 total hex clears (6 per color × 8 colors)
    return state.hexesCleared >= 48;
  }
  return false;
}

/**
 * Check if sprint mode time is up.
 */
export function checkSprintTimer(state, elapsed) {
  if (state.mode === 'sprint') {
    return elapsed >= 180000; // 3 minutes
  }
  return false;
}

/**
 * Get initial active colors (always start with 2).
 */
export function getInitialColors() {
  return [0, 1];
}

/**
 * Get initial drop interval.
 */
export function getInitialDropInterval() {
  return INITIAL_DROP_INTERVAL;
}
