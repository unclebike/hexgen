// input.js — Input handling: mouse, touch, keyboard
// All inputs produce InputEvent objects queued for the game loop

import { pixelToTriangle } from './grid.js';

const INPUT_QUEUE = [];
const ROTATION_DEBOUNCE_MS = 125; // max 8 per second
let lastRotationTime = 0;

/**
 * Initialize input handlers on the canvas.
 * @param {HTMLCanvasElement} canvas
 * @param {Function} getRenderParams - Returns { size, offsetX, offsetY }
 */
export function initInput(canvas, getRenderParams) {
  // ===== MOUSE =====
  canvas.addEventListener('click', (e) => {
    if (e.shiftKey) {
      pushEvent({ type: 'expandCursor', timestamp: e.timeStamp });
      return;
    }
    const { size, offsetX, offsetY } = getRenderParams();
    const rect = canvas.getBoundingClientRect();
    const px = e.clientX - rect.left - offsetX;
    const py = e.clientY - rect.top - offsetY;
    const tri = pixelToTriangle(px, py, size);
    if (tri) {
      pushEvent({ type: 'moveCursor', target: tri, timestamp: e.timeStamp });
    }
  });

  canvas.addEventListener('contextmenu', (e) => {
    e.preventDefault();
    pushEvent({ type: 'shrinkCursor', timestamp: e.timeStamp });
  });

  canvas.addEventListener('wheel', (e) => {
    e.preventDefault();
    const now = performance.now();
    if (now - lastRotationTime < ROTATION_DEBOUNCE_MS) return;
    lastRotationTime = now;
    pushEvent({
      type: e.deltaY > 0 ? 'rotateCW' : 'rotateCCW',
      timestamp: e.timeStamp,
    });
  }, { passive: false });

  // ===== KEYBOARD =====
  const keyMap = {
    'KeyQ': 'rotateCCW', 'KeyZ': 'rotateCCW',
    'KeyE': 'rotateCW', 'KeyX': 'rotateCW',
    'Equal': 'expandCursor', 'NumpadAdd': 'expandCursor',
    'Minus': 'shrinkCursor', 'NumpadSubtract': 'shrinkCursor',
    'Space': 'pause',
    'Escape': 'escape',
  };

  // Direction keys map to cursor movement (handled specially)
  const dirKeys = {
    'KeyW': 'up', 'ArrowUp': 'up',
    'KeyS': 'down', 'ArrowDown': 'down',
    'KeyA': 'left', 'ArrowLeft': 'left',
    'KeyD': 'right', 'ArrowRight': 'right',
  };

  document.addEventListener('keydown', (e) => {
    const action = keyMap[e.code];
    if (action) {
      e.preventDefault();
      if (action === 'rotateCW' || action === 'rotateCCW') {
        const now = performance.now();
        if (now - lastRotationTime < ROTATION_DEBOUNCE_MS) return;
        lastRotationTime = now;
      }
      pushEvent({ type: action, timestamp: e.timeStamp });
      return;
    }

    const dir = dirKeys[e.code];
    if (dir) {
      e.preventDefault();
      pushEvent({ type: 'moveCursorDir', direction: dir, timestamp: e.timeStamp });
    }
  });

  // ===== TOUCH =====
  let touchStartPos = null;
  let touchStartAngle = null;
  let touchStartDist = null;
  let isTwoFinger = false;

  canvas.addEventListener('touchstart', (e) => {
    e.preventDefault();
    if (e.touches.length === 1) {
      touchStartPos = { x: e.touches[0].clientX, y: e.touches[0].clientY };
      isTwoFinger = false;
    } else if (e.touches.length === 2) {
      isTwoFinger = true;
      const dx = e.touches[1].clientX - e.touches[0].clientX;
      const dy = e.touches[1].clientY - e.touches[0].clientY;
      touchStartAngle = Math.atan2(dy, dx);
      touchStartDist = Math.sqrt(dx * dx + dy * dy);
    }
  }, { passive: false });

  canvas.addEventListener('touchmove', (e) => {
    e.preventDefault();
    if (e.touches.length === 2 && isTwoFinger) {
      const dx = e.touches[1].clientX - e.touches[0].clientX;
      const dy = e.touches[1].clientY - e.touches[0].clientY;
      const angle = Math.atan2(dy, dx);
      const dist = Math.sqrt(dx * dx + dy * dy);

      // Rotation detection: snap to 60° increments
      if (touchStartAngle !== null) {
        const delta = angle - touchStartAngle;
        if (Math.abs(delta) > Math.PI / 6) { // 30° threshold
          const now = performance.now();
          if (now - lastRotationTime >= ROTATION_DEBOUNCE_MS) {
            lastRotationTime = now;
            pushEvent({
              type: delta > 0 ? 'rotateCCW' : 'rotateCW',
              timestamp: e.timeStamp,
            });
            touchStartAngle = angle;
          }
        }
      }

      // Pinch detection for cursor resize
      if (touchStartDist !== null) {
        const ratio = dist / touchStartDist;
        if (ratio > 1.4) {
          pushEvent({ type: 'expandCursor', timestamp: e.timeStamp });
          touchStartDist = dist;
        } else if (ratio < 0.7) {
          pushEvent({ type: 'shrinkCursor', timestamp: e.timeStamp });
          touchStartDist = dist;
        }
      }
    }
  }, { passive: false });

  canvas.addEventListener('touchend', (e) => {
    e.preventDefault();
    if (!isTwoFinger && touchStartPos && e.changedTouches.length === 1) {
      const t = e.changedTouches[0];
      const dx = t.clientX - touchStartPos.x;
      const dy = t.clientY - touchStartPos.y;
      // Only treat as tap if finger didn't move much
      if (Math.sqrt(dx * dx + dy * dy) < 20) {
        const { size, offsetX, offsetY } = getRenderParams();
        const rect = canvas.getBoundingClientRect();
        const px = t.clientX - rect.left - offsetX;
        const py = t.clientY - rect.top - offsetY;
        const tri = pixelToTriangle(px, py, size);
        if (tri) {
          pushEvent({ type: 'moveCursor', target: tri, timestamp: e.timeStamp });
        }
      }
    }
    if (e.touches.length === 0) {
      touchStartPos = null;
      touchStartAngle = null;
      touchStartDist = null;
      isTwoFinger = false;
    }
  }, { passive: false });
}

/**
 * Push an event into the queue.
 */
function pushEvent(event) {
  INPUT_QUEUE.push(event);
}

/**
 * Drain all queued input events.
 */
export function drainInputQueue() {
  const events = INPUT_QUEUE.splice(0);
  return events;
}

/**
 * Push a raw event (used by menu system).
 */
export function pushRawEvent(event) {
  INPUT_QUEUE.push(event);
}
