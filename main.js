// main.js — Game loop orchestrator
// Ties together all modules: state, rendering, input, audio

import { createInitialState, processInput, tick, unpause, BOARD_RADIUS, HEX_SIZE } from './gamestate.js';
import { initRenderer, renderFrame, resize, getRenderParams } from './renderer.js';
import { AnimationManager } from './animations.js';
import { drawHUD, drawGameOver, drawPause } from './hud.js';
import { initInput, drainInputQueue } from './input.js';
import { initAudio, resumeAudio, playSound, startDrone, stopDrone, toggleMute } from './audio.js';
import { drawMenu, handleMenuClick, handleMenuHover, resetMenu } from './menu.js';
import { saveHighScore } from './scoring.js';
import { COLOR_PALETTE } from './progression.js';
import { hexToPixel } from './grid.js';
import { getAdjacentTriangles, triangleToPixel, triEqual } from './grid.js';

// Game phases
let appState = 'menu'; // 'menu' | 'playing' | 'gameover'
let gameState = null;
let prevGameState = null;
let animations = null;
let lastTime = 0;
let isNewHighScore = false;

// Canvas setup
const canvas = document.getElementById('gameCanvas');
const { ctx } = initRenderer(canvas);

// Responsive resize
window.addEventListener('resize', resize);

// Initialize input
initInput(canvas, getRenderParams);

// Menu interaction handlers
canvas.addEventListener('click', (e) => {
  // Initialize audio on first click
  initAudio();
  resumeAudio();

  if (appState === 'menu') {
    const rect = canvas.getBoundingClientRect();
    const mode = handleMenuClick(e.clientX - rect.left, e.clientY - rect.top);
    if (mode) {
      startGame(mode);
    }
  } else if (appState === 'gameover') {
    // Return to menu
    appState = 'menu';
    resetMenu();
    stopDrone();
  }
});

canvas.addEventListener('mousemove', (e) => {
  if (appState === 'menu') {
    const rect = canvas.getBoundingClientRect();
    handleMenuHover(e.clientX - rect.left, e.clientY - rect.top);
  }
});

/**
 * Start a new game.
 */
function startGame(mode) {
  appState = 'playing';
  gameState = createInitialState(mode);
  prevGameState = null;
  animations = new AnimationManager();
  isNewHighScore = false;
  startDrone(gameState.activeColors.length);
}

/**
 * Handle cursor movement by direction (from keyboard).
 */
function handleDirectionalMove(state, direction) {
  const { center } = state.cursor;
  const adjacent = getAdjacentTriangles(center, BOARD_RADIUS);

  // Map directions to approximate angles
  const dirAngles = {
    'up': -Math.PI / 2,
    'down': Math.PI / 2,
    'left': Math.PI,
    'right': 0,
  };

  const targetAngle = dirAngles[direction];
  if (targetAngle === undefined) return state;

  const size = HEX_SIZE;
  const centerPixel = triangleToPixel(center, size);

  // Find the adjacent triangle closest to the desired direction
  let bestTri = null;
  let bestDist = Infinity;

  for (const tri of adjacent) {
    const triPixel = triangleToPixel(tri, size);
    const dx = triPixel.x - centerPixel.x;
    const dy = triPixel.y - centerPixel.y;
    const angle = Math.atan2(dy, dx);
    const angleDiff = Math.abs(((angle - targetAngle + Math.PI) % (2 * Math.PI)) - Math.PI);
    if (angleDiff < bestDist) {
      bestDist = angleDiff;
      bestTri = tri;
    }
  }

  if (bestTri) {
    return processInput(state, { type: 'moveCursor', target: bestTri, timestamp: performance.now() });
  }
  return state;
}

/**
 * Main game loop.
 */
function gameLoop(timestamp) {
  const dt = lastTime ? Math.min(timestamp - lastTime, 50) : 16; // cap at 50ms
  lastTime = timestamp;

  const w = canvas.width / (window.devicePixelRatio || 1);
  const h = canvas.height / (window.devicePixelRatio || 1);

  if (appState === 'menu') {
    drawMenu(ctx, w, h);
  } else if (appState === 'playing' || appState === 'gameover') {
    // Process inputs
    const events = drainInputQueue();
    for (const event of events) {
      if (event.type === 'escape') {
        appState = 'menu';
        resetMenu();
        stopDrone();
        requestAnimationFrame(gameLoop);
        return;
      }

      if (event.type === 'pause') {
        if (gameState.phase === 'paused') {
          gameState = unpause(gameState);
        } else if (gameState.phase === 'playing') {
          gameState = processInput(gameState, event);
        }
        continue;
      }

      if (event.type === 'moveCursorDir') {
        gameState = handleDirectionalMove(gameState, event.direction);
        continue;
      }

      if (gameState.phase === 'playing') {
        prevGameState = gameState;
        gameState = processInput(gameState, event);

        // Audio triggers based on input
        if (event.type === 'rotateCW' || event.type === 'rotateCCW') {
          playSound('rotate');
        }
      }
    }

    // Tick game state
    if (gameState.phase !== 'paused') {
      prevGameState = gameState;
      gameState = tick(gameState, dt);
    }

    // Detect state changes for audio
    if (prevGameState && gameState !== prevGameState) {
      // Hex cleared
      if (gameState.justCleared.length > 0) {
        for (const hex of gameState.justCleared) {
          playSound('clear', { colorIndex: hex.color });
          // Spawn particles
          const { size, offsetX, offsetY } = getRenderParams();
          const hCenter = hexToPixel(hex.hexCoord.q, hex.hexCoord.r, size);
          animations.spawnClearParticles(
            hCenter.x + offsetX,
            hCenter.y + offsetY,
            COLOR_PALETTE[hex.color]
          );
          animations.triggerShake();
        }
      }

      // Level up
      if (gameState.leveledUp) {
        playSound('levelup', { colorIndex: gameState.activeColors[gameState.activeColors.length - 1] });
        startDrone(gameState.activeColors.length);
      }

      // Game over
      if (gameState.phase === 'gameover' && prevGameState.phase !== 'gameover') {
        playSound('gameover');
        stopDrone();
        isNewHighScore = saveHighScore(gameState.mode, gameState.score);
        appState = 'gameover';
      }

      // Drop happened
      if (gameState.justDropped) {
        playSound('place', { colorIndex: gameState.activeColors[0] });
      }
    }

    // Update animations
    animations.update(dt);

    // Render
    renderFrame({ state: gameState, animations, dt });
    drawHUD(ctx, gameState, w, h);

    // Overlays
    if (gameState.phase === 'gameover') {
      drawGameOver(ctx, gameState, w, h, isNewHighScore);
    } else if (gameState.phase === 'paused') {
      drawPause(ctx, w, h);
    }
  }

  requestAnimationFrame(gameLoop);
}

// Start the loop
requestAnimationFrame(gameLoop);
