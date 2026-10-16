// input.js — Mouse, touch, and keyboard input during play
// Everything is queued as an event for the game loop:
//   { type: 'tap', x, y }        — canvas coords; the loop turns this into a dial
//   { type: 'rotate', dir }      — 1 = clockwise, -1 = counter-clockwise
//   { type: 'move', direction }  — 'up' | 'down' | 'left' | 'right'
//   { type: 'pause' } / { type: 'escape' }

import { touchButtons } from './hud.js';

const INPUT_QUEUE = [];
const ROTATION_DEBOUNCE_MS = 90;
const TAP_SLOP = 20; // px a finger can drift and still count as a tap
let lastRotationTime = 0;
let lastTouchTime = 0; // suppresses the click a browser synthesizes after a tap
let inputActive = false; // menus handle their own taps

/** Turn gameplay input on or off. */
export function setInputActive(active) {
  inputActive = active;
}

export function drainInputQueue() {
  return INPUT_QUEUE.splice(0);
}

function push(event) {
  if (inputActive) INPUT_QUEUE.push(event);
}

function pushRotate(dir) {
  const now = performance.now();
  if (now - lastRotationTime < ROTATION_DEBOUNCE_MS) return;
  lastRotationTime = now;
  push({ type: 'rotate', dir });
}

/** A tap or click: an on-screen rotate button, or a spot on the board. */
function handleTap(canvas, clientX, clientY) {
  const rect = canvas.getBoundingClientRect();
  const x = clientX - rect.left;
  const y = clientY - rect.top;
  if (touchButtons.visible) {
    for (const [button, dir] of [[touchButtons.rotateCCW, -1], [touchButtons.rotateCW, 1]]) {
      if (Math.hypot(x - button.x, y - button.y) <= button.radius * 1.5) {
        pushRotate(dir);
        return;
      }
    }
  }
  push({ type: 'tap', x, y });
}

export function initInput(canvas) {
  // ===== MOUSE =====
  canvas.addEventListener('click', (e) => {
    if (performance.now() - lastTouchTime < 500) return;
    handleTap(canvas, e.clientX, e.clientY);
  });

  canvas.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    pushRotate(-1);
  });

  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    pushRotate(e.deltaY > 0 ? 1 : -1);
  }, { passive: false });

  // ===== KEYBOARD =====
  const keyMap = {
    KeyQ: { type: 'rotate', dir: -1 }, KeyZ: { type: 'rotate', dir: -1 },
    KeyE: { type: 'rotate', dir: 1 }, KeyX: { type: 'rotate', dir: 1 },
    KeyW: { type: 'move', direction: 'up' }, ArrowUp: { type: 'move', direction: 'up' },
    KeyS: { type: 'move', direction: 'down' }, ArrowDown: { type: 'move', direction: 'down' },
    KeyA: { type: 'move', direction: 'left' }, ArrowLeft: { type: 'move', direction: 'left' },
    KeyD: { type: 'move', direction: 'right' }, ArrowRight: { type: 'move', direction: 'right' },
    Space: { type: 'pause' },
    Escape: { type: 'escape' },
  };

  document.addEventListener('keydown', (e) => {
    const event = keyMap[e.code];
    if (!event || !inputActive) return;
    e.preventDefault();
    if (event.type === 'rotate') pushRotate(event.dir);
    else push(event);
  });

  // ===== TOUCH =====
  let touchStartPos = null;
  let touchStartAngle = null;
  let isTwoFinger = false;

  canvas.addEventListener('touchstart', (e) => {
    if (!inputActive) return;
    e.preventDefault();
    if (e.touches.length === 1) {
      touchStartPos = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      isTwoFinger = false;
    } else if (e.touches.length === 2) {
      isTwoFinger = true;
      touchStartAngle = Math.atan2(
        e.touches[1].clientY - e.touches[0].clientY,
        e.touches[1].clientX - e.touches[0].clientX,
      );
    }
  }, { passive: false });

  canvas.addEventListener('touchmove', (e) => {
    if (!inputActive) return;
    e.preventDefault();
    if (e.touches.length !== 2 || !isTwoFinger || touchStartAngle === null) return;
    // Two-finger twist turns the dial, one step per 30°
    const angle = Math.atan2(
      e.touches[1].clientY - e.touches[0].clientY,
      e.touches[1].clientX - e.touches[0].clientX,
    );
    const delta = angle - touchStartAngle;
    if (Math.abs(delta) > Math.PI / 6) {
      pushRotate(delta > 0 ? 1 : -1);
      touchStartAngle = angle;
    }
  }, { passive: false });

  canvas.addEventListener('touchend', (e) => {
    lastTouchTime = performance.now();
    if (!inputActive) {
      touchStartPos = null;
      isTwoFinger = false;
      return;
    }
    e.preventDefault();
    if (!isTwoFinger && touchStartPos && e.changedTouches.length === 1) {
      const t = e.changedTouches[0];
      if (Math.hypot(t.clientX - touchStartPos.x, t.clientY - touchStartPos.y) < TAP_SLOP) {
        handleTap(canvas, t.clientX, t.clientY);
      }
    }
    if (e.touches.length === 0) {
      touchStartPos = null;
      touchStartAngle = null;
      isTwoFinger = false;
    }
  }, { passive: false });
}
