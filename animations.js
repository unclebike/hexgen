// animations.js — Visual effects: particles and screen shake

export class AnimationManager {
  constructor() {
    this.particles = [];
    this.shakeTimer = 0;
    this.shakeIntensity = 0;
  }

  update(dt) {
    this.particles = this.particles.filter(p => {
      p.life -= dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.vy += 0.0002 * dt; // gravity
      p.alpha = Math.max(0, p.life / p.maxLife);
      return p.life > 0;
    });
    if (this.shakeTimer > 0) this.shakeTimer -= dt;
  }

  /** Burst of triangle confetti from a cleared hex, in screen coords. */
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

  triggerShake(duration = 200, intensity = 2) {
    this.shakeTimer = duration;
    this.shakeIntensity = intensity;
  }

  getScreenShake() {
    if (this.shakeTimer <= 0) return { x: 0, y: 0 };
    const factor = this.shakeTimer / 200;
    return {
      x: (Math.random() - 0.5) * 2 * this.shakeIntensity * factor,
      y: (Math.random() - 0.5) * 2 * this.shakeIntensity * factor,
    };
  }

  drawParticles(ctx) {
    for (const p of this.particles) {
      ctx.save();
      ctx.globalAlpha = p.alpha;
      ctx.fillStyle = p.color;
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
