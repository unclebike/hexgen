// main.js — Game loop: menus, input, game updates, effects, and drawing

import {
  createGame, update, rotate, moveCursorTo, moveCursorDir, togglePause, binFill, isHoldingPiece,
} from './gamestate.js';
import {
  initRenderer, renderFrame, resize, setLayout, tickLayout, toScreen, toUnit, drawOverlayEffects,
  drawLogoInBin, logoBottomInBin, isOnMenuLogo, getScale,
} from './renderer.js';
import { AnimationManager } from './animations.js';
import { drawHUD, drawCountdown, tickSpinner } from './hud.js';
import { initInput, drainInputQueue, setInputActive } from './input.js';
import {
  initAudio, resumeAudio, playSound, startDrone, stopDrone, toggleMute,
} from './audio.js';
import {
  initUI, showMenu, showPlay, showPause, hidePause, showResult, refreshUI, tickUI, announce, cardOpen,
} from './ui.js';
import { oneTurnFromHex, finishesHex } from './hexdetect.js';
import {
  loadBrand, copy, skin, weights, hardCut, resetStrobe, recordProgress, cycleSkin, unlockAll, unlockedCount,
  skinCount, wearPlayableSkin,
} from './skins.js';
import { settings, setSpeed, setBoard, toggleHand, shouldAssist, countAssistedGame } from './settings.js';
import { saveHighScore } from './scoring.js';
import { dailyChallenge, todayNumber, recordDaily, dailyResult, dailyStreak, latestDailyDay } from './daily.js';
import { DemoPlayer } from './demo.js';
import { CalloutFeed } from './callouts.js';
import { SPEEDS } from './progression.js';

const HARD_CUT_FLASH = 50;       // ms the screen flashes on a hard cut, about three frames
const RESUME_COUNT = 3;          // seconds a paused daily counts back in
const DEMO_RESTART_FILL = 0.55;  // the menu's demo starts over rather than fill up
const HINT_DELAY = 3;            // seconds a one-turn hex goes unnoticed before it's marked
const HINT_SEARCH_GAP = 0.25;
const TENSE_ON = 0.7, TENSE_OFF = 0.55; // how full the bin is when the danger callout comes and goes
const SPRINT_FINISH = 30;        // seconds left that count as a sprint's last stretch
const LOGO_FADE = 0.25;

let screen = 'menu'; // 'menu' | 'playing'
let game = null;
let animations = new AnimationManager();
let lastTime = 0;
let flashTimer = 0;
let logoAlpha = 1;

let demo = null;
let demoPlayer = null;
const logoFloor = () => logoBottomInBin();

// What this game has said and shown so far
const feed = new CalloutFeed();
let progressRecorded = false;
let unlockedNow = [];
let resumeCountdown = null;
let glowSeen = false;
let wasTense = false;
let finaleCalled = false;
let hint = null;
let hintWait = 0;
let hintSearchLeft = 0;

feed.onShow = callout => announce([callout.title, callout.detail].filter(Boolean).join(' '));

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
  refreshUI();
}

// Colours, copy, and fonts must be ready before anything is drawn
await loadBrand();

const canvas = document.getElementById('gameCanvas');
const fx = document.getElementById('fx');
const { ctx } = initRenderer(canvas);
const fxCtx = fx.getContext('2d');
initInput(canvas);

/** The skin's grain and scanlines sit over everything, menus included, on their own canvas. */
function refreshEffects() {
  const dpr = window.devicePixelRatio || 1;
  fx.width = window.innerWidth * dpr;
  fx.height = window.innerHeight * dpr;
  fx.style.width = `${window.innerWidth}px`;
  fx.style.height = `${window.innerHeight}px`;
  fxCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
  drawOverlayEffects(fxCtx, window.innerWidth, window.innerHeight);
  const wt = weights(Math.min(36, getScale()));
  document.documentElement.style.setProperty('--line', `${Math.max(1.5, wt.line)}px`);
  document.documentElement.style.setProperty('--heavy', `${Math.max(3, wt.heavy)}px`);
}

window.addEventListener('resize', () => {
  resize();
  refreshEffects();
  refreshUI();
});

function startDemo() {
  demo = createGame({ mode: 'endless', speed: settings.speed });
  demoPlayer = new DemoPlayer(logoFloor());
}

// Today's daily, rebuilt when the UTC day turns over
let dailyCache = null;
function todaysDaily() {
  const day = todayNumber();
  if (dailyCache?.day !== day) dailyCache = dailyChallenge(day);
  return dailyCache;
}

function beginGame(options) {
  wearPlayableSkin();
  drainInputQueue();
  screen = 'playing';
  game = createGame(options);
  animations = new AnimationManager();
  progressRecorded = false;
  unlockedNow = [];
  flashTimer = 0;
  resumeCountdown = null;
  glowSeen = false;
  wasTense = false;
  finaleCalled = false;
  hint = null;
  hintWait = 0;
  hintSearchLeft = 0;
  feed.reset();
  resetStrobe();
  setLayout('play', settings.leftHanded);
  refreshEffects();
  showPlay();
  setInputActive(true);
  startDrone(game.activeColors.length);
}

function startGame(mode) {
  beginGame({ mode, speed: settings.speed, board: settings.board, assisted: shouldAssist(mode) });
}

/** Bank this game's hexes (and a MAIN win) toward skin unlocks, once per game. */
function recordGame() {
  if (!game || progressRecorded) return;
  progressRecorded = true;
  unlockedNow = recordProgress({ hexes: game.hexesCleared, mainWin: game.won });
}

function toMenu() {
  recordGame();
  screen = 'menu';
  game = null;
  resumeCountdown = null;
  stopDrone();
  setInputActive(false);
  drainInputQueue();
  startDemo();
  logoAlpha = 0;
  setLayout('menu', settings.leftHanded);
  refreshEffects();
  showMenu();
}

// ===== Pausing =====

function pauseToggled() {
  if (!game || game.phase === 'gameover') return;
  // A paused daily hides its board, so it comes back on a count instead of at once
  // (asking again while it counts stays paused)
  if (game.daily && game.phase === 'paused') {
    resumeCountdown = resumeCountdown === null ? RESUME_COUNT : null;
    if (resumeCountdown === null) showPause(true);
    else hidePause();
    return;
  }
  togglePause(game);
  if (game.phase === 'paused') showPause(!!game.daily);
  else hidePause();
}

/** The tab was hidden: stop the clock. */
function pauseIfPlaying() {
  if (!game) return;
  if (resumeCountdown !== null) {
    resumeCountdown = null;
    showPause(true);
  } else if (game.phase === 'playing') {
    pauseToggled();
  }
}

document.addEventListener('visibilitychange', () => {
  if (document.hidden) pauseIfPlaying();
});

initUI(document.getElementById('ui'), document.getElementById('announce'), {
  start: startGame,
  startDaily: () => beginGame({ daily: todaysDaily() }),
  todaysDaily,
  cycleSkin() {
    cycleSkin();
    refreshEffects();
    refreshUI();
  },
  setSpeed(speed) {
    setSpeed(speed);
    startDemo();
  },
  setBoard,
  toggleHand() {
    toggleHand();
    if (game) setLayout('play', settings.leftHanded);
  },
  toggleSound() {
    initAudio();
    toggleMute();
  },
  togglePause: pauseToggled,
  toMenu,
});

// ===== Menu =====

// Browsers only start sound from a gesture
document.addEventListener('pointerdown', () => {
  initAudio();
  resumeAudio();
});

canvas.addEventListener('pointerup', (e) => {
  if (screen === 'menu' && !cardOpen() && isOnMenuLogo(e.clientX, e.clientY)) logoTapped();
});

document.addEventListener('keydown', (e) => {
  if (e.repeat) return;
  initAudio();
  resumeAudio();
  if (screen === 'menu' && !cardOpen()) {
    if (e.code === 'KeyK') {
      e.preventDefault();
      cycleSkin();
      refreshEffects();
      refreshUI();
      return;
    }
    const mode = { Digit1: 'main', Digit2: 'endless', Digit3: 'sprint' }[e.code];
    if (mode) {
      e.preventDefault();
      startGame(mode);
    }
  } else if (game?.phase === 'gameover' && (e.code === 'Enter' || e.code === 'Escape' || e.code === 'Space')) {
    e.preventDefault();
    toMenu();
  }
});

// ===== Gameplay =====

function handleInput(event) {
  switch (event.type) {
    case 'escape':
      // Playing, it pauses; paused, it goes to the menu
      if (game.phase === 'paused') toMenu();
      else pauseToggled();
      return;
    case 'pause':
      pauseToggled();
      return;
    case 'confirm':
      if (game.phase === 'paused') pauseToggled();
      else handleGameEvents(rotate(game, 1));
      return;
    case 'move':
      moveCursorDir(game, event.direction);
      return;
    case 'rotate':
      handleGameEvents(rotate(game, event.dir));
      return;
    case 'drag': {
      if (game.phase !== 'playing') return;
      const point = toUnit(event.x, event.y, game.grid);
      moveCursorTo(game, game.grid.nearestDial(point.x, point.y));
      return;
    }
    case 'tap': {
      if (game.phase !== 'playing') return;
      const point = toUnit(event.x, event.y, game.grid);
      const dial = game.grid.nearestDial(point.x, point.y, 1.2);
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
        // Powers only arrive on new pieces, so this is where a glow first shows
        if (!glowSeen && [...game.board.values()].some(p => p.power)) {
          glowSeen = true;
          feed.post('glow');
        }
        break;
      case 'clear':
        for (const hex of event.hexes) {
          playSound('clear', { colorIndex: hex.color });
          const center = toScreen(game.grid.vertexXY(hex.k, hex.j), game.grid);
          animations.spawnClearParticles(center.x, center.y, skin.pieces[hex.color]);
        }
        if (hardCut()) flashTimer = HARD_CUT_FLASH;
        animations.triggerShake();
        break;
      case 'power':
        animations.triggerShake(300, 4);
        if (event.rescue) feed.post('rescue');
        else if (event.power === 'drain') feed.post('drain');
        else feed.post('swap', {}, game.lastSwap ? [game.lastSwap.from, game.lastSwap.to] : []);
        break;
      case 'levelup':
        playSound('levelup', { colorIndex: event.color });
        startDrone(game.activeColors.length);
        feed.post('levelUp', {
          level: game.level,
          points: Math.round(100 * game.level * SPEEDS[game.speed].points),
        }, [event.color]);
        break;
      case 'gameover':
        finishGame();
        break;
    }
  }
}

/** Keep a finished daily's score as the day's first try or a new best. */
function finishDaily(daily, score) {
  const latest = latestDailyDay();
  // The clock is behind a day already played: it was set forward to play early, or back since
  if (latest !== null && daily.day < latest) {
    return {
      newBest: false,
      finish: { first: false, result: dailyResult(daily.day), streak: dailyStreak(daily.day), unkept: true },
    };
  }
  const outcome = recordDaily(score, daily.day);
  return {
    // A first try is its own line, so "new best" is only for beating it
    newBest: outcome.best && !outcome.first,
    finish: { first: outcome.first, result: dailyResult(daily.day), streak: dailyStreak(daily.day), unkept: false },
  };
}

function finishGame() {
  const text = copy();
  playSound('gameover');
  stopDrone();
  if (game.assisted) countAssistedGame(game.won);

  let newBest;
  let daily = null;
  if (game.daily) {
    const outcome = finishDaily(game.daily, game.score);
    newBest = outcome.newBest;
    daily = outcome.finish;
  } else {
    newBest = saveHighScore(game.mode, game.score, game.boardSize);
  }
  recordGame();

  hint = null;
  setInputActive(false);
  setLayout('result', settings.leftHanded);
  const timeUp = game.sprintTimeRemaining === 0;
  const headline = game.won ? text.cleared : timeUp ? text.timeUp : text.binFull;
  showResult({ headline, score: game.score, newBest, unlocked: unlockedNow, daily });
}

/** In an assisted game, mark a hex one turn away once it's gone unnoticed for a few seconds. */
function watchForHint(dt) {
  if (!game.assisted || game.phase !== 'playing') return;
  hintSearchLeft -= dt;
  if (hintSearchLeft > 0) return;
  hintSearchLeft = HINT_SEARCH_GAP;

  const stillGood = hint && finishesHex(game.grid, game.board, hint.k, hint.j);
  const found = stillGood ? hint : oneTurnFromHex(game.grid, game.board, game.cursor);
  if (!found) {
    hint = null;
    hintWait = 0;
    return;
  }
  hintWait += HINT_SEARCH_GAP;
  if (hintWait < HINT_DELAY) return;
  if (!hint) feed.post('hint');
  hint = found;
}

/** The shifts no event names: the dial holding a piece up, a filling bin, and a sprint's last stretch. */
function watchShifts(dt) {
  if (game.phase !== 'playing') return;
  feed.tick(dt);
  const fill = binFill(game);
  const tense = wasTense ? fill >= TENSE_OFF : fill >= TENSE_ON;
  if (tense && !wasTense) feed.post('danger');
  wasTense = tense;
  if (game.sprintTimeRemaining !== null && !finaleCalled && game.sprintTimeRemaining <= SPRINT_FINISH) {
    finaleCalled = true;
    feed.post('finale', { seconds: SPRINT_FINISH });
  }
  if (feed.wants('held') && isHoldingPiece(game)) feed.post('held');
}

function tickCountdown(dt) {
  if (resumeCountdown === null) return;
  resumeCountdown -= dt;
  if (resumeCountdown <= 0) {
    resumeCountdown = null;
    if (game.phase === 'paused') togglePause(game);
  }
}

function frameMenu(dt, t) {
  demoPlayer.update(demo, dt);
  if (demo.phase !== 'playing' || binFill(demo) > DEMO_RESTART_FILL) startDemo();
  renderFrame(demo, null, { hideAbove: logoFloor() });
  logoAlpha = Math.min(1, logoAlpha + dt / LOGO_FADE);
  ctx.save();
  ctx.globalAlpha = logoAlpha;
  drawLogoInBin(ctx, t);
  ctx.restore();
  tickUI(dt);
}

function framePlay(dtMs, dt, w, h) {
  for (const event of drainInputQueue()) {
    handleInput(event);
    if (screen !== 'playing') return false;
  }
  tickCountdown(dt);
  handleGameEvents(update(game, dt));
  if (screen !== 'playing') return false;
  watchForHint(dt);
  watchShifts(dt);
  animations.update(dtMs);
  tickSpinner(dt);

  renderFrame(game, animations, { hint });
  if (game.phase !== 'gameover') drawHUD(ctx, game, w, h, feed);
  if (resumeCountdown !== null) drawCountdown(ctx, Math.ceil(resumeCountdown), w, h);
  if (flashTimer > 0) {
    flashTimer -= dtMs;
    ctx.fillStyle = skin.ink;
    ctx.fillRect(0, 0, w, h);
  }
  return true;
}

const reduceMotion = window.matchMedia?.('(prefers-reduced-motion: reduce)');

function gameLoop(timestamp) {
  const dtMs = lastTime ? Math.min(timestamp - lastTime, 50) : 16;
  lastTime = timestamp;
  const dt = dtMs / 1000;
  const w = window.innerWidth;
  const h = window.innerHeight;

  tickLayout(dt);
  if (screen === 'playing' && framePlay(dtMs, dt, w, h)) {
    // drawn
  } else if (screen === 'menu') {
    frameMenu(dt, reduceMotion?.matches ? 0 : timestamp / 1000);
  }
  requestAnimationFrame(gameLoop);
}

startDemo();
setLayout('menu', settings.leftHanded, true);
tickLayout(0);
refreshEffects();
showMenu();
requestAnimationFrame(gameLoop);
