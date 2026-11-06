// input.js — Pointer and keyboard input during play
// Everything is queued as an event for the game loop:
//   { type: 'tap', x, y }        — canvas coords; the loop turns this into a dial
//   { type: 'drag', x, y }       — a finger carrying the dial across the board
//   { type: 'rotate', dir }      — 1 = clockwise, -1 = counter-clockwise
//   { type: 'move', direction }  — 'up' | 'down' | 'left' | 'right'
//   { type: 'pause' } / { type: 'escape' } / { type: 'confirm' }

import { hudZones, spinner } from './hud.js';

const INPUT_QUEUE = [];
const ROTATION_DEBOUNCE_MS = 90;
const TAP_SLOP = 8;              // px a finger can drift and still count as a tap
const TWIST_STEP = Math.PI / 6;  // a two-finger twist turns the dial one step per 30°
const SPIN_STEP = Math.PI / 3;
const SPINNER_DEAD_ZONE = 0.2;   // near the centre the angle jumps about

let lastRotationTime = 0;
let inputActive = false; // menus handle their own input
let lastKind = window.matchMedia?.('(pointer: coarse)').matches ? 'touch' : 'keyboard';

/** The input last used, so hints can name its controls. */
export const inputKind = () => lastKind;

/** Turn gameplay input on or off. */
export function setInputActive(active) {
  inputActive = active;
  pointers.clear();
  spinner.held = false;
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

// Every finger or mouse button down: where it started and what it's doing
const pointers = new Map();
let twistAngle = null;

function zoneAt(x, y) {
  const { pause, spinner: wheel } = hudZones;
  if (pause && x >= pause.x && x <= pause.x + pause.w && y >= pause.y && y <= pause.y + pause.h) return 'pause';
  if (wheel) {
    // Only inside its own hex, standing on a corner
    const dx = Math.abs(x - wheel.x), dy = Math.abs(y - wheel.y);
    if (dx <= wheel.r * Math.sqrt(3) / 2 && dy <= wheel.r - dx / Math.sqrt(3)) return 'spinner';
  }
  return 'board';
}

const pointAngle = (p, wheel) => Math.atan2(p.y - wheel.y, p.x - wheel.x);

/** The finger going round the spinner: it follows, sending a turn for every 60°, either way. */
function spinnerMoved(p) {
  const wheel = hudZones.spinner;
  if (!wheel) return;
  if (Math.hypot(p.x - p.startX, p.y - p.startY) > TAP_SLOP) p.dragged = true;
  if (!p.dragged || Math.hypot(p.x - wheel.x, p.y - wheel.y) <= wheel.r * SPINNER_DEAD_ZONE) return;
  const now = pointAngle(p, wheel);
  if (p.anchor === null) {
    p.anchor = now;
    return;
  }
  let delta = now - p.anchor;
  if (delta > Math.PI) delta -= 2 * Math.PI;
  if (delta < -Math.PI) delta += 2 * Math.PI;
  p.anchor = now;
  spinner.spin += delta;
  if (wheel.clockwiseOnly) spinner.spin = Math.max(0, spinner.spin);
  // A whole step: send it, and take it off the spin (the pieces themselves move a slot)
  while (spinner.spin >= SPIN_STEP) {
    spinner.spin -= SPIN_STEP;
    push({ type: 'rotate', dir: 1 });
  }
  while (spinner.spin <= -SPIN_STEP) {
    spinner.spin += SPIN_STEP;
    push({ type: 'rotate', dir: -1 });
  }
}

function boardFingers() {
  return [...pointers.values()].filter(p => p.zone === 'board');
}

const twistOf = ([a, b]) => Math.atan2(b.y - a.y, b.x - a.x);

export function initInput(canvas) {
  const local = e => {
    const rect = canvas.getBoundingClientRect();
    return { x: e.clientX - rect.left, y: e.clientY - rect.top };
  };

  canvas.addEventListener('pointerdown', (e) => {
    lastKind = e.pointerType === 'touch' ? 'touch' : 'keyboard';
    if (!inputActive || e.button !== 0) return;
    e.preventDefault();
    canvas.setPointerCapture?.(e.pointerId);
    const { x, y } = local(e);
    const zone = zoneAt(x, y);
    if (zone === 'pause') {
      push({ type: 'pause' });
      return;
    }
    pointers.set(e.pointerId, { zone, x, y, startX: x, startY: y, dragged: false, anchor: null });
    if (zone === 'spinner') spinner.held = true;
    const fingers = boardFingers();
    if (fingers.length === 2) twistAngle = twistOf(fingers);
  });

  canvas.addEventListener('pointermove', (e) => {
    const p = pointers.get(e.pointerId);
    if (!inputActive || !p) return;
    Object.assign(p, local(e));
    if (p.zone === 'spinner') {
      spinnerMoved(p);
      return;
    }
    const fingers = boardFingers();
    if (fingers.length >= 2) {
      // Two fingers on the board: a twist turns the dial
      fingers.forEach(finger => { finger.dragged = true; });
      if (twistAngle === null) return;
      let delta = twistOf(fingers) - twistAngle;
      if (delta > Math.PI) delta -= 2 * Math.PI;
      if (delta < -Math.PI) delta += 2 * Math.PI;
      if (Math.abs(delta) > TWIST_STEP) {
        pushRotate(delta > 0 ? 1 : -1);
        twistAngle = twistOf(fingers);
      }
      return;
    }
    // One finger dragged across the board carries the dial with it
    if (Math.hypot(p.x - p.startX, p.y - p.startY) > TAP_SLOP) p.dragged = true;
    if (p.dragged) push({ type: 'drag', x: p.x, y: p.y });
  });

  const release = (e) => {
    const p = pointers.get(e.pointerId);
    if (!p) return;
    pointers.delete(e.pointerId);
    if (e.type === 'pointerup' && !p.dragged) {
      if (p.zone === 'spinner') pushRotate(1);
      else if (boardFingers().length === 0) push({ type: 'tap', x: p.x, y: p.y });
    }
    if (p.zone === 'spinner') spinner.held = false;
    if (boardFingers().length < 2) twistAngle = null;
  };
  canvas.addEventListener('pointerup', release);
  canvas.addEventListener('pointercancel', release);

  canvas.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    pushRotate(-1);
  });

  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    pushRotate(e.deltaY > 0 ? 1 : -1);
  }, { passive: false });

  const keyMap = {
    KeyQ: { type: 'rotate', dir: -1 }, KeyZ: { type: 'rotate', dir: -1 },
    KeyE: { type: 'rotate', dir: 1 }, KeyX: { type: 'rotate', dir: 1 },
    KeyW: { type: 'move', direction: 'up' }, ArrowUp: { type: 'move', direction: 'up' },
    KeyS: { type: 'move', direction: 'down' }, ArrowDown: { type: 'move', direction: 'down' },
    KeyA: { type: 'move', direction: 'left' }, ArrowLeft: { type: 'move', direction: 'left' },
    KeyD: { type: 'move', direction: 'right' }, ArrowRight: { type: 'move', direction: 'right' },
    Space: { type: 'pause' },
    Escape: { type: 'escape' },
    Enter: { type: 'confirm' }, NumpadEnter: { type: 'confirm' },
  };

  document.addEventListener('keydown', (e) => {
    lastKind = 'keyboard';
    const event = keyMap[e.code];
    if (!event || !inputActive) return;
    e.preventDefault();
    if (event.type === 'rotate') pushRotate(event.dir);
    else push(event);
  });
}
