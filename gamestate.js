// gamestate.js — Game state manager
// Processes inputs, manages state transitions, coordinates all game systems

import { createBoard, getValidHexCoords, getAdjacentTriangles, hexKey, isValidHex, getCentroidY, getCentroidX, getGravityTargets, getHexNeighbors } from './grid.js';
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

  let newState = { ...state, leveledUp: false, justCleared: [], justDropped: false, gravityMoves: null };

  // Handle clearing phase
  if (newState.phase === 'clearing') {
    newState.clearTimer -= dt;
    if (newState.clearTimer <= 0) {
      // Clear the hexes from the board
      newState.board = clearHexes(newState.board, newState.pendingClears);
      newState.pendingClears = [];
      newState.phase = 'playing';

      // Apply gravity after clear
      const { board: settledBoard, moveLog } = settleBoard(newState.board);
      newState.board = settledBoard;
      if (moveLog.length > 0) {
        newState.gravityMoves = moveLog;
      }

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
      const { board: settledBoard, moveLog } = settleBoard(newState.board);
      newState.board = settledBoard;
      if (moveLog.length > 0) {
        newState.gravityMoves = moveLog;
      }

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
 * Uses getGravityTargets for vertical fall paths (top→bottom within hex,
 * then cross-hex to the hex below, choosing exit that minimizes x-drift).
 * Returns { board, moveLog } where moveLog is an array of passes,
 * each pass an array of {from, to} moves for animation.
 */
function settleBoard(board) {
  const newBoard = new Map();
  for (const [key, cell] of board) {
    newBoard.set(key, cell.map(t => ({ ...t })));
  }

  // Pre-compute all triangle positions sorted by y ascending (top first)
  const allPositions = [];
  const coords = getValidHexCoords(BOARD_RADIUS);
  for (const { q, r } of coords) {
    for (let i = 0; i < 6; i++) {
      allPositions.push({ q, r, triIndex: i, y: getCentroidY({ q, r, triIndex: i }) });
    }
  }
  allPositions.sort((a, b) => a.y - b.y);

  const moveLog = [];
  let changed = true;
  while (changed) {
    changed = false;
    const passMoves = [];
    // Track pieces that just landed this pass — don't let them move again
    const justLanded = new Set();

    for (const pos of allPositions) {
      const posKey = `${pos.q},${pos.r},${pos.triIndex}`;
      if (justLanded.has(posKey)) continue;

      const cell = newBoard.get(hexKey(pos.q, pos.r));
      const tri = cell[pos.triIndex];
      if (tri.color === -1) continue;

      const triID = { q: pos.q, r: pos.r, triIndex: pos.triIndex };
      const targets = getGravityTargets(triID, BOARD_RADIUS);

      // Filter to empty targets (also skip positions just vacated by another piece
      // that hasn't re-landed yet — but the board state handles this since we update in-place)
      const emptyTargets = targets.filter(t => {
        const tCell = newBoard.get(hexKey(t.q, t.r));
        return tCell && tCell[t.triIndex].color === -1;
      });

      if (emptyTargets.length === 0) continue;

      // Pick target: if multiple (top tris have 2 options), choose closest x
      let bestTarget;
      if (emptyTargets.length === 1) {
        bestTarget = emptyTargets[0];
      } else {
        const curX = getCentroidX(triID);
        let bestDx = Infinity;
        for (const t of emptyTargets) {
          const dx = Math.abs(getCentroidX(t) - curX);
          if (dx < bestDx) {
            bestDx = dx;
            bestTarget = t;
          }
        }
      }

      // Move the piece
      const tCell = newBoard.get(hexKey(bestTarget.q, bestTarget.r));
      tCell[bestTarget.triIndex] = { ...tri, id: bestTarget };
      cell[pos.triIndex] = { id: triID, color: -1, isPowerUp: null, isGlowing: false };
      passMoves.push({ from: { ...triID }, to: { ...bestTarget } });
      justLanded.add(`${bestTarget.q},${bestTarget.r},${bestTarget.triIndex}`);
      changed = true;
    }

    if (passMoves.length > 0) {
      moveLog.push(passMoves);
    }
  }

  return { board: newBoard, moveLog };
}

export { BOARD_RADIUS, CLEAR_DURATION };
