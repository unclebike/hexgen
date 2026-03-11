// animations.js — Visual effects: particles, screen shake, rotation animation

/**
 * Animation manager — tracks and updates all active visual effects.
 */
export class AnimationManager {
  constructor() {
    this.particles = [];
    this.shakeTimer = 0;
    this.shakeIntensity = 0;
    this.rotationAnim = null;
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
