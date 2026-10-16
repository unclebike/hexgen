// main.js — Game loop: menus, input, game updates, effects, and drawing

import { createGame, update, rotate, moveCursorTo, moveCursorDir, togglePause } from './gamestate.js';
import { initRenderer, renderFrame, resize, toScreen, toUnit } from './renderer.js';
import { AnimationManager } from './animations.js';
import { drawHUD, drawGameOver, drawPause, touchButtons } from './hud.js';
import { initInput, drainInputQueue, setInputActive } from './input.js';
import { initAudio, resumeAudio, playSound, startDrone, stopDrone } from './audio.js';
import { drawMenu, handleMenuClick, handleMenuHover, resetMenu } from './menu.js';
import { COLOR_PALETTE } from './progression.js';
import { nearestDial, vertexXY } from './grid.js';

let appState = 'menu'; // 'menu' | 'playing' | 'gameover'
let game = null;
let animations = new AnimationManager();
let lastTime = 0;
let isNewHighScore = false;

const canvas = document.getElementById('gameCanvas');
const { ctx } = initRenderer(canvas);
window.addEventListener('resize', resize);
initInput(canvas);

function startGame(mode) {
  drainInputQueue();
  appState = 'playing';
  game = createGame(mode);
  animations = new AnimationManager();
  isNewHighScore = false;
  setInputActive(true);
  startDrone(game.activeColors.length);
}

function toMenu() {
  appState = 'menu';
  resetMenu();
  stopDrone();
  touchButtons.visible = false;
  setInputActive(false);
  drainInputQueue();
}

// ===== Menu and game-over taps (gameplay taps go through input.js) =====
function handleMenuTap(clientX, clientY) {
  initAudio();
  resumeAudio();
  if (appState === 'menu') {
    const rect = canvas.getBoundingClientRect();
    const mode = handleMenuClick(clientX - rect.left, clientY - rect.top);
    if (mode) startGame(mode);
  } else if (appState === 'gameover') {
    toMenu();
  }
}

let lastMenuTouchTime = 0;
canvas.addEventListener('click', (e) => {
  if (performance.now() - lastMenuTouchTime < 500) return; // ghost click after a tap
  if (appState !== 'playing') handleMenuTap(e.clientX, e.clientY);
});
canvas.addEventListener('touchstart', (e) => {
  if (appState !== 'playing') e.preventDefault();
}, { passive: false });
canvas.addEventListener('touchend', (e) => {
  if (appState === 'playing') return;
  e.preventDefault();
  lastMenuTouchTime = performance.now();
  if (e.changedTouches.length === 1) {
    handleMenuTap(e.changedTouches[0].clientX, e.changedTouches[0].clientY);
  }
}, { passive: false });
canvas.addEventListener('mousemove', (e) => {
  if (appState !== 'menu') return;
  const rect = canvas.getBoundingClientRect();
  handleMenuHover(e.clientX - rect.left, e.clientY - rect.top);
});

document.addEventListener('keydown', (e) => {
  if (appState !== 'menu') return;
  const mode = { Digit1: 'main', Digit2: 'endless', Digit3: 'sprint' }[e.code];
  if (!mode) return;
  e.preventDefault();
  initAudio();
  resumeAudio();
  startGame(mode);
});

// ===== Gameplay =====
function handleInput(event) {
  switch (event.type) {
    case 'escape':
      toMenu();
      return;
    case 'pause':
      togglePause(game);
      return;
    case 'move':
      moveCursorDir(game, event.direction);
      return;
    case 'rotate':
      handleGameEvents(rotate(game, event.dir));
      return;
    case 'tap': {
      if (game.phase === 'paused') {
        togglePause(game);
        return;
      }
      const point = toUnit(event.x, event.y);
      const dial = nearestDial(point.x, point.y, 1.2);
      if (!dial) return;
      // Tapping the dial you're on turns it; tapping elsewhere moves it there
      if (dial.k === game.cursor.k && dial.j === game.cursor.j) handleGameEvents(rotate(game, 1));
      else moveCursorTo(game, dial);
    }
  }
}

function handleGameEvents(events) {
  for (const event of events) {
    switch (event.type) {
      case 'rotate':
        playSound('rotate');
        break;
      case 'spawn':
        playSound('place', { colorIndex: game.activeColors[0] });
        break;
      case 'clear':
        for (const hex of event.hexes) {
          playSound('clear', { colorIndex: hex.color });
          const center = toScreen(vertexXY(hex.k, hex.j));
          animations.spawnClearParticles(center.x, center.y, COLOR_PALETTE[hex.color]);
        }
        animations.triggerShake();
        break;
      case 'power':
        animations.triggerShake(300, 4);
        break;
      case 'levelup':
        playSound('levelup', { colorIndex: event.color });
        startDrone(game.activeColors.length);
        break;
      case 'gameover':
        playSound('gameover');
        stopDrone();
        isNewHighScore = event.newHighScore;
        appState = 'gameover';
        setInputActive(false);
        break;
    }
  }
}

function gameLoop(timestamp) {
  const dt = lastTime ? Math.min(timestamp - lastTime, 50) : 16;
  lastTime = timestamp;

  const w = canvas.width / (window.devicePixelRatio || 1);
  const h = canvas.height / (window.devicePixelRatio || 1);

  if (appState === 'menu') {
    drawMenu(ctx, w, h);
  } else {
    for (const event of drainInputQueue()) {
      handleInput(event);
      if (appState === 'menu') break;
    }
    if (appState !== 'menu') {
      handleGameEvents(update(game, dt));
      animations.update(dt);

      renderFrame(game, animations);
      drawHUD(ctx, game, w, h);
      if (game.phase === 'gameover') drawGameOver(ctx, game, w, h, isNewHighScore);
      else if (game.phase === 'paused') drawPause(ctx, w, h);
    } else {
      drawMenu(ctx, w, h);
    }
  }

  requestAnimationFrame(gameLoop);
}

requestAnimationFrame(gameLoop);
