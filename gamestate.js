// gamestate.js — Game state manager
// Processes inputs, manages state transitions, coordinates all game systems

import { createBoard, getValidHexCoords, getAdjacentTriangles, hexKey, isValidHex, getCentroidY, getHexNeighbors } from './grid.js';
import { rotateHexCell } from './rotation.js';
import { detectCompletedHexes, clearHexes } from './hexdetect.js';
import { generateDrop, applyDrops, isGameOver } from './dropper.js';
import { checkProgression, checkWinCondition, getInitialColors, getInitialDropInterval } from './progression.js';
import { calculateScore, saveHighScore } from './scoring.js';

const BOARD_RADIUS = 4;
const CLEAR_DURATION = 500; // ms for clearing animation

/**
 * Create initial game state for a given mode.
 */
export function createInitialState(mode = 'main') {
  const board = createBoard(BOARD_RADIUS);
  const activeColors = getInitialColors();

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
    cursor: { q: 0, r: 0 },
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

      // Apply gravity after clear
      newState.board = settleBoard(newState.board);

      // Check for chain clears after settling
      const chainClears = detectCompletedHexes(newState.board, BOARD_RADIUS);
      if (chainClears.length > 0) {
        const points = calculateScore(chainClears.length, newState.level);
        return {
          ...newState,
          phase: 'clearing',
          clearTimer: CLEAR_DURATION,
          pendingClears: chainClears,
          score: newState.score + points,
          hexesCleared: newState.hexesCleared + chainClears.length,
          hexesThisLevel: newState.hexesThisLevel + chainClears.length,
          justCleared: chainClears,
        };
      }

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

      // Apply gravity after drop
      newState.board = settleBoard(newState.board);

      // Check for completed hexes after drop + settle
      newState = checkForClears(newState);
    }
  }

  return newState;
}

/**
 * Perform a rotation and check for clears.
 */
function performRotation(state, direction) {
  const { q, r } = state.cursor;
  const newBoard = rotateHexCell(state.board, q, r, direction);
  let newState = { ...state, board: newBoard };

  // Debug: log cursor hex state after rotation
  const cell = newBoard.get(hexKey(q, r));
  if (cell) {
    const colors = cell.map(t => t.color);
    const filled = colors.filter(c => c >= 0);
    console.log(`[ROTATE] Hex (${q},${r}) colors: [${colors}] (${filled.length}/6 filled)`);
  }

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
 * Move the cursor to a hex cell.
 * target is {q, r} for a hex cell.
 */
function moveCursor(state, target) {
  if (!target) return state;
  if (!isValidHex(target.q, target.r, BOARD_RADIUS)) return state;

  return {
    ...state,
    cursor: { q: target.q, r: target.r },
  };
}

/**
 * Move cursor to adjacent hex in a direction.
 * direction is 'up', 'down', 'left', 'right'
 */
export function moveCursorDirection(state, direction) {
  if (state.phase !== 'playing') return state;

  const { q, r } = state.cursor;
  const neighbors = getHexNeighbors(q, r, BOARD_RADIUS);

  const dirAngles = {
    'right': 0,
    'down': Math.PI / 2,
    'left': Math.PI,
    'up': -Math.PI / 2,
  };

  const targetAngle = dirAngles[direction];
  if (targetAngle === undefined) return state;

  const SQRT3 = Math.sqrt(3);
  let bestHex = null;
  let bestDist = Infinity;

  for (const n of neighbors) {
    const dx = SQRT3 * (n.q - q) + (SQRT3 / 2) * (n.r - r);
    const dy = 1.5 * (n.r - r);
    const angle = Math.atan2(dy, dx);
    let angleDiff = angle - targetAngle;
    angleDiff = ((angleDiff + Math.PI) % (2 * Math.PI) + 2 * Math.PI) % (2 * Math.PI) - Math.PI;
    const dist = Math.abs(angleDiff);
    if (dist < bestDist) {
      bestDist = dist;
      bestHex = n;
    }
  }

  if (bestHex) {
    return { ...state, cursor: { q: bestHex.q, r: bestHex.r } };
  }
  return state;
}

/**
 * Activate a power-up at the cursor position.
 */
export function activatePowerUp(state) {
  const { q, r } = state.cursor;
  const cell = state.board.get(hexKey(q, r));
  if (!cell) return state;

  const powerUpTri = cell.find(t => t.isPowerUp !== null);
  if (!powerUpTri) return state;

  let newState = { ...state };

  if (powerUpTri.isPowerUp === 'drain') {
    newState = activateDrain(newState);
  } else if (powerUpTri.isPowerUp === 'swap') {
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

/**
 * Apply gravity — settle all triangles downward until stable.
 * Triangles fall to adjacent empty positions with higher y-coordinates.
 */
function settleBoard(board) {
  const newBoard = new Map();
  for (const [key, cell] of board) {
    newBoard.set(key, cell.map(t => ({ ...t })));
  }

  // Pre-compute all triangle positions sorted by y (ascending = top first)
  const allPositions = [];
  const coords = getValidHexCoords(BOARD_RADIUS);
  for (const { q, r } of coords) {
    for (let i = 0; i < 6; i++) {
      allPositions.push({ q, r, triIndex: i, y: getCentroidY({ q, r, triIndex: i }) });
    }
  }
  allPositions.sort((a, b) => a.y - b.y);

  let changed = true;
  while (changed) {
    changed = false;
    for (const pos of allPositions) {
      const cell = newBoard.get(hexKey(pos.q, pos.r));
      const tri = cell[pos.triIndex];
      if (tri.color === -1) continue;

      const triID = { q: pos.q, r: pos.r, triIndex: pos.triIndex };
      const neighbors = getAdjacentTriangles(triID, BOARD_RADIUS);

      let bestNeighbor = null;
      let bestDy = 0;

      for (const n of neighbors) {
        const nCell = newBoard.get(hexKey(n.q, n.r));
        if (!nCell) continue;
        if (nCell[n.triIndex].color !== -1) continue;

        const dy = getCentroidY(n) - pos.y;
        if (dy > 0.01 && dy > bestDy) {
          bestDy = dy;
          bestNeighbor = n;
        }
      }

      if (bestNeighbor) {
        const nCell = newBoard.get(hexKey(bestNeighbor.q, bestNeighbor.r));
        nCell[bestNeighbor.triIndex] = { ...tri, id: bestNeighbor };
        cell[pos.triIndex] = { id: triID, color: -1, isPowerUp: null, isGlowing: false };
        changed = true;
      }
    }
  }

  return newBoard;
}

export { BOARD_RADIUS, CLEAR_DURATION };
