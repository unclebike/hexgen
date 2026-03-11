// gamestate.js — Game state manager
// Processes inputs, manages state transitions, coordinates all game systems

import { createBoard, getTrianglesInRadius, getAdjacentTriangles, getTriangle, triKey, triEqual, hexKey, getValidHexCoords, getBoardBounds } from './grid.js';
import { computeRotation, applyRotation } from './rotation.js';
import { detectCompletedHexes, clearHexes } from './hexdetect.js';
import { generateDrop, applyDrops, isGameOver } from './dropper.js';
import { checkProgression, checkWinCondition, getInitialColors, getInitialDropInterval } from './progression.js';
import { calculateScore, saveHighScore } from './scoring.js';

const BOARD_RADIUS = 4;
const HEX_SIZE = 30; // size used for rotation pixel math
const CLEAR_DURATION = 500; // ms for clearing animation

/**
 * Create initial game state for a given mode.
 */
export function createInitialState(mode = 'main') {
  const board = createBoard(BOARD_RADIUS);
  const activeColors = getInitialColors();
  const centerTri = { q: 0, r: 0, triIndex: 0 };

  return {
    board,
    score: 0,
    level: 2,
    hexesCleared: 0,
    hexesThisLevel: 0,
    dropTimer: getInitialDropInterval(),
    dropInterval: getInitialDropInterval(),
    activeColors,
    mode,
    phase: 'playing',
    cursor: {
      center: centerTri,
      radius: 1,
      selectedTriangles: getTrianglesInRadius(centerTri, 1, BOARD_RADIUS),
    },
    clearTimer: 0,
    pendingClears: [],
    startTime: Date.now(),
    sprintTimeRemaining: mode === 'sprint' ? 180000 : -1,
    leveledUp: false,
    justCleared: [],
    justDropped: false,
  };
}

/**
 * Process an input event against the current state.
 * Returns new state.
 */
export function processInput(state, event) {
  if (state.phase !== 'playing') return state;

  switch (event.type) {
    case 'rotateCW':
      return performRotation(state, 1);
    case 'rotateCCW':
      return performRotation(state, -1);
    case 'moveCursor':
      return moveCursor(state, event.target);
    case 'expandCursor':
      return changeCursorRadius(state, 1);
    case 'shrinkCursor':
      return changeCursorRadius(state, -1);
    case 'pause':
      return { ...state, phase: 'paused' };
    default:
      return state;
  }
}

/**
 * Unpause the game.
 */
export function unpause(state) {
  if (state.phase === 'paused') {
    return { ...state, phase: 'playing' };
  }
  return state;
}

/**
 * Advance the game by dt milliseconds.
 * Handles drop timer, clearing phase transitions, sprint timer.
 */
export function tick(state, dt) {
  if (state.phase === 'paused' || state.phase === 'gameover') return state;

  let newState = { ...state, leveledUp: false, justCleared: [], justDropped: false };

  // Handle clearing phase
  if (newState.phase === 'clearing') {
    newState.clearTimer -= dt;
    if (newState.clearTimer <= 0) {
      // Clear the hexes from the board
      newState.board = clearHexes(newState.board, newState.pendingClears);
      newState.pendingClears = [];
      newState.phase = 'playing';

      // Check progression (new color?)
      newState = checkProgression(newState);

      // Check win condition
      if (checkWinCondition(newState)) {
        saveHighScore(newState.mode, newState.score);
        return { ...newState, phase: 'gameover' };
      }
    }
    return newState;
  }

  // Sprint timer
  if (newState.mode === 'sprint') {
    newState.sprintTimeRemaining -= dt;
    if (newState.sprintTimeRemaining <= 0) {
      saveHighScore('sprint', newState.score);
      return { ...newState, phase: 'gameover', sprintTimeRemaining: 0 };
    }
  }

  // Drop timer
  newState.dropTimer -= dt;
  if (newState.dropTimer <= 0) {
    newState.dropTimer = newState.dropInterval;

    // Check game over before dropping
    if (isGameOver(newState.board, BOARD_RADIUS)) {
      saveHighScore(newState.mode, newState.score);
      return { ...newState, phase: 'gameover' };
    }

    // Generate and apply drops
    const drops = generateDrop(newState.board, newState.activeColors, BOARD_RADIUS);
    if (drops.length > 0) {
      newState.board = applyDrops(newState.board, drops);
      newState.justDropped = true;

      // Check for completed hexes after drop
      newState = checkForClears(newState);
    }
  }

  return newState;
}

/**
 * Perform a rotation and check for clears.
 */
function performRotation(state, direction) {
  const { center, selectedTriangles } = state.cursor;

  const mappings = computeRotation(center, selectedTriangles, direction, HEX_SIZE, BOARD_RADIUS);
  if (!mappings) return state; // Invalid rotation

  const newBoard = applyRotation(state.board, mappings);
  let newState = { ...state, board: newBoard };

  // Check for clears after rotation
  newState = checkForClears(newState);

  return newState;
}

/**
 * Check for completed hexes and transition to clearing phase if found.
 */
function checkForClears(state) {
  const completed = detectCompletedHexes(state.board, BOARD_RADIUS);
  if (completed.length > 0) {
    const points = calculateScore(completed.length, state.level);
    return {
      ...state,
      phase: 'clearing',
      clearTimer: CLEAR_DURATION,
      pendingClears: completed,
      score: state.score + points,
      hexesCleared: state.hexesCleared + completed.length,
      hexesThisLevel: state.hexesThisLevel + completed.length,
      justCleared: completed,
    };
  }
  return state;
}

/**
 * Move the cursor to a new center triangle.
 */
function moveCursor(state, target) {
  if (!target) return state;

  // Validate target is on the board
  const bounds = getBoardBounds(BOARD_RADIUS);
  const isValid = bounds.some(b => triEqual(b, target));
  if (!isValid) return state;

  const selectedTriangles = getTrianglesInRadius(target, state.cursor.radius, BOARD_RADIUS);

  return {
    ...state,
    cursor: {
      ...state.cursor,
      center: target,
      selectedTriangles,
    },
  };
}

/**
 * Change cursor selection radius.
 */
function changeCursorRadius(state, delta) {
  const newRadius = Math.max(0, Math.min(3, state.cursor.radius + delta));
  if (newRadius === state.cursor.radius) return state;

  const selectedTriangles = getTrianglesInRadius(state.cursor.center, newRadius, BOARD_RADIUS);

  return {
    ...state,
    cursor: {
      ...state.cursor,
      radius: newRadius,
      selectedTriangles,
    },
  };
}

/**
 * Activate a power-up at the cursor position.
 */
export function activatePowerUp(state) {
  const tri = getTriangle(state.board, state.cursor.center);
  if (!tri || !tri.isPowerUp) return state;

  let newState = { ...state };

  if (tri.isPowerUp === 'drain') {
    newState = activateDrain(newState);
  } else if (tri.isPowerUp === 'swap') {
    newState = activateSwap(newState);
  }

  return newState;
}

/**
 * Drain power-up: remove all triangles in the bottom row.
 */
function activateDrain(state) {
  const newBoard = new Map();
  for (const [key, cell] of state.board) {
    newBoard.set(key, cell.map(t => ({ ...t })));
  }

  // Get bottom edge cells
  const coords = getValidHexCoords(BOARD_RADIUS);
  const maxR = Math.max(...coords.map(c => c.r));
  const bottomCells = coords.filter(c => c.r === maxR);

  for (const { q, r } of bottomCells) {
    const cell = newBoard.get(hexKey(q, r));
    for (let i = 0; i < 6; i++) {
      cell[i] = {
        id: { q, r, triIndex: i },
        color: -1,
        isPowerUp: null,
        isGlowing: false,
      };
    }
  }

  return { ...state, board: newBoard };
}

/**
 * Swap power-up: change all triangles of one random color to another.
 */
function activateSwap(state) {
  const { activeColors } = state;
  if (activeColors.length < 2) return state;

  const fromColor = activeColors[Math.floor(Math.random() * activeColors.length)];
  let toColor;
  do {
    toColor = activeColors[Math.floor(Math.random() * activeColors.length)];
  } while (toColor === fromColor);

  const newBoard = new Map();
  for (const [key, cell] of state.board) {
    newBoard.set(key, cell.map(t => {
      if (t.color === fromColor) {
        return { ...t, color: toColor };
      }
      return { ...t };
    }));
  }

  return { ...state, board: newBoard };
}

export { BOARD_RADIUS, HEX_SIZE, CLEAR_DURATION };
