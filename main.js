// main.js — Game loop: menus, input, game updates, effects, and drawing

import { createGame, update, rotate, moveCursorTo, moveCursorDir, togglePause } from './gamestate.js';
import { initRenderer, renderFrame, resize, toScreen, toUnit, drawOverlayEffects } from './renderer.js';
import { AnimationManager } from './animations.js';
import { drawHUD, drawGameOver, drawPause, touchButtons } from './hud.js';
import { initInput, drainInputQueue, setInputActive } from './input.js';
import { initAudio, resumeAudio, playSound, startDrone, stopDrone } from './audio.js';
import { drawMenu, handleMenuClick, handleMenuHover, resetMenu } from './menu.js';
import { nearestDial, vertexXY } from './grid.js';
import { loadBrand, skin, hardCut, resetStrobe, recordProgress, cycleSkin, unlockAll, unlockedCount, skinCount } from './skins.js';

const HARD_CUT_FLASH = 50; // ms the screen flashes on a hard cut, about three frames

let appState = 'menu'; // 'menu' | 'playing' | 'gameover'
let game = null;
let animations = new AnimationManager();
let lastTime = 0;
let isNewHighScore = false;
let unlockedSkins = []; // ids unlocked by the game that just ended
let progressRecorded = false;
let flashTimer = 0;

// Hidden shortcut: tap the logo 20 times in a row to open every skin
const LOGO_TAPS_TO_UNLOCK = 20;
const LOGO_TAP_GAP = 1500; // ms allowed between taps
let logoTaps = 0;
let lastLogoTap = 0;

function logoTapped() {
  const now = performance.now();
  logoTaps = now - lastLogoTap <= LOGO_TAP_GAP ? logoTaps + 1 : 1;
  lastLogoTap = now;
  if (logoTaps < LOGO_TAPS_TO_UNLOCK || unlockedCount() >= skinCount()) return;
  logoTaps = 0;
  unlockAll();
  playSound('levelup', { colorIndex: 0 });
}

// Colours, copy, and fonts must be ready before anything is drawn
await loadBrand();

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
  unlockedSkins = [];
  progressRecorded = false;
  flashTimer = 0;
  resetStrobe();
  setInputActive(true);
  startDrone(game.activeColors.length);
}

/** Bank this game's hexes (and a MAIN win) toward skin unlocks, once per game. */
function recordGame() {
  if (!game || progressRecorded) return;
  progressRecorded = true;
  unlockedSkins = recordProgress({ hexes: game.hexesCleared, mainWin: game.won });
}

function toMenu() {
  recordGame();
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
    const choice = handleMenuClick(clientX - rect.left, clientY - rect.top);
    if (choice === 'logo') logoTapped();
    else if (choice === 'skin') cycleSkin();
    else if (choice) startGame(choice);
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
  if (e.code === 'KeyK') {
    e.preventDefault();
    cycleSkin();
    return;
  }
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
          animations.spawnClearParticles(center.x, center.y, skin.pieces[hex.color]);
        }
        if (hardCut()) flashTimer = HARD_CUT_FLASH;
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
        recordGame();
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
      if (game.phase === 'gameover') drawGameOver(ctx, game, w, h, isNewHighScore, unlockedSkins);
      else if (game.phase === 'paused') drawPause(ctx, w, h);
      if (flashTimer > 0) {
        flashTimer -= dt;
        ctx.fillStyle = skin.ink;
        ctx.fillRect(0, 0, w, h);
      }
      drawOverlayEffects(ctx, w, h);
    } else {
      drawMenu(ctx, w, h);
    }
  }

  requestAnimationFrame(gameLoop);
}

requestAnimationFrame(gameLoop);
