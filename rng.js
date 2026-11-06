// rng.js — Seeded random numbers that match the iOS app bit for bit
//
// The Daily Dial is the same for everyone, so its generator, and the way Swift's
// standard library turns raw bits into choices, are reproduced exactly here.
// 64-bit arithmetic needs BigInt. Everything else in the game uses Math.random.

const MASK = (1n << 64n) - 1n;

/** SplitMix64, as `SeededGenerator` in Players.swift. */
export class SeededGenerator {
  constructor(seed) {
    this.state = BigInt.asUintN(64, seed);
  }

  /** The next 64 random bits, as a BigInt. */
  next() {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK;
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & MASK;
    return z ^ (z >> 31n);
  }

  clone() {
    const copy = new SeededGenerator(0n);
    copy.state = this.state;
    return copy;
  }
}

/** A whole number in 0..<upper: Lemire's method, as Swift's `next(upperBound:)`. */
export function below(rng, upper) {
  const bound = BigInt(upper);
  let m = rng.next() * bound;
  if ((m & MASK) < bound) {
    const threshold = BigInt.asUintN(64, -bound) % bound;
    while ((m & MASK) < threshold) m = rng.next() * bound;
  }
  return Number(m >> 64n);
}

/** Swift's `randomElement(using:)`. */
export function randomElement(items, rng) {
  return items[below(rng, items.length)];
}

/** Swift's `shuffled(using:)`: returns a new array. */
export function shuffled(items, rng) {
  const out = [...items];
  for (let at = 0, amount = out.length; amount > 1; at++) {
    const offset = below(rng, amount);
    amount--;
    [out[at], out[at + offset]] = [out[at + offset], out[at]];
  }
  return out;
}

/** The bits' top 53 as a fraction in 0..<1, as `DealStream.unit`. */
export const unit = bits => Number(bits >> 11n) / 2 ** 53;
