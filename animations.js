// animations.js — Visual effects: particles, screen shake, rotation animation, gravity cascade

import { triangleToPixel, triEqual } from './grid.js';

/**
 * Animation manager — tracks and updates all active visual effects.
 */
export class AnimationManager {
  constructor() {
    this.particles = [];
    this.shakeTimer = 0;
    this.shakeIntensity = 0;
    this.rotationAnim = null;
    this.gravityAnims = [];
    this.gravityAnimElapsed = 0;
    this.gravityAnimTotal = 0;
  }

  /**
   * Update all animations by dt milliseconds.
   */
  update(dt) {
    // Update particles
    this.particles = this.particles.filter(p => {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 0.0002 * dt; // gravity
      p.alpha = Math.max(0, p.life / p.maxLife);
      return p.life > 0;
    });

    // Update screen shake
    if (this.shakeTimer > 0) {
      this.shakeTimer -= dt;
    }

    // Update rotation animation
    if (this.rotationAnim) {
      this.rotationAnim.elapsed += dt;
      if (this.rotationAnim.elapsed >= this.rotationAnim.duration) {
        this.rotationAnim = null;
      }
    }

    // Update gravity cascade animation
    if (this.gravityAnimTotal > 0) {
      this.gravityAnimElapsed += dt;
      if (this.gravityAnimElapsed >= this.gravityAnimTotal) {
        this.gravityAnims = [];
        this.gravityAnimTotal = 0;
        this.gravityAnimElapsed = 0;
      }
    }
  }

  /**
   * Spawn particle burst for a hex clear.
   * @param {number} cx - Center X in screen coords
   * @param {number} cy - Center Y in screen coords
   * @param {string} color - CSS color string
   */
  spawnClearParticles(cx, cy, color) {
    for (let i = 0; i < 12; i++) {
      const angle = (Math.PI * 2 * i) / 12 + (Math.random() - 0.5) * 0.3;
      const speed = 0.1 + Math.random() * 0.15;
      this.particles.push({
        x: cx,
        y: cy,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        size: 3 + Math.random() * 4,
        color,
        alpha: 1,
        life: 500,
        maxLife: 500,
      });
    }
  }

  /**
   * Trigger screen shake.
   */
  triggerShake(duration = 200, intensity = 2) {
    this.shakeTimer = duration;
    this.shakeIntensity = intensity;
  }

  /**
   * Get current screen shake offset.
   */
  getScreenShake() {
    if (this.shakeTimer <= 0) return { x: 0, y: 0 };
    const factor = this.shakeTimer / 200;
    return {
      x: (Math.random() - 0.5) * 2 * this.shakeIntensity * factor,
      y: (Math.random() - 0.5) * 2 * this.shakeIntensity * factor,
    };
  }

  /**
   * Start a rotation animation.
   */
  startRotationAnim(mappings, duration = 150) {
    this.rotationAnim = {
      mappings,
      duration,
      elapsed: 0,
    };
  }

  /**
   * Get rotation animation progress (0 to 1), or null if not animating.
   */
  getRotationProgress() {
    if (!this.rotationAnim) return null;
    const t = this.rotationAnim.elapsed / this.rotationAnim.duration;
    // Ease-out
    return 1 - (1 - t) * (1 - t);
  }

  /**
   * Start a gravity cascade animation from a moveLog.
   * Each pass in moveLog is animated sequentially, with stepDuration ms per pass.
   * @param {Array<Array<{from, to}>>} moveLog - passes of gravity moves
   * @param {number} stepDuration - ms per gravity step (controls cascade speed)
   */
  startGravityAnimation(moveLog, stepDuration = 60) {
    this.gravityAnims = [];
    for (let pass = 0; pass < moveLog.length; pass++) {
      for (const move of moveLog[pass]) {
        this.gravityAnims.push({
          from: move.from,
          to: move.to,
          startTime: pass * stepDuration,
          duration: stepDuration,
        });
      }
    }
    this.gravityAnimElapsed = 0;
    this.gravityAnimTotal = moveLog.length * stepDuration;
  }

  /**
   * Get the pixel offset for a triangle currently being animated by gravity.
   * Returns {dx, dy} in unit-size coordinates, or null if not animating.
   * The renderer multiplies by currentSize to get screen pixels.
   */
  getTriangleOffset(triID) {
    if (!this.gravityAnims.length) return null;

    for (const anim of this.gravityAnims) {
      if (triEqual(anim.to, triID)) {
        const t = (this.gravityAnimElapsed - anim.startTime) / anim.duration;
        if (t >= 0 && t < 1) {
          // Interpolate from 'from' position toward 'to' position
          const fromPx = triangleToPixel(anim.from, 1);
          const toPx = triangleToPixel(anim.to, 1);
          const ease = 1 - (1 - t) * (1 - t); // ease-out quadratic
          return {
            dx: (fromPx.x - toPx.x) * (1 - ease),
            dy: (fromPx.y - toPx.y) * (1 - ease),
          };
        }
      }
    }
    return null;
  }

  /**
   * Whether a gravity cascade animation is currently playing.
   */
  isGravityAnimating() {
    return this.gravityAnimTotal > 0;
  }

  /**
   * Draw particles onto the canvas context.
   */
  drawParticles(ctx, offsetX, offsetY) {
    for (const p of this.particles) {
      ctx.save();
      ctx.globalAlpha = p.alpha;
      ctx.fillStyle = p.color;

      // Draw small triangle particle
      const s = p.size * p.alpha;
      ctx.beginPath();
      ctx.moveTo(p.x, p.y - s);
      ctx.lineTo(p.x - s * 0.866, p.y + s * 0.5);
      ctx.lineTo(p.x + s * 0.866, p.y + s * 0.5);
      ctx.closePath();
      ctx.fill();

      ctx.restore();
    }
  }
}
