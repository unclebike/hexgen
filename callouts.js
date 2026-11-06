// callouts.js — One quiet line beside the bin when play shifts
//
// Callouts say what just changed while it happens, in the HUD and never over
// the bin. Each one explains itself the first few times it shows, then shrinks
// to its title. The first-time kinds stop once they've explained.

import { copy } from './skins.js';

const SEEN_KEY = 'dialhex_callouts_seen';
const EXPLAINED_SHOWINGS = 3;  // showings that carry the explaining line
const BRIEF_TIME = 1.6;        // seconds on screen with just a title
const EXPLAINED_TIME = 3.4;    // and with the explaining line too
const GAP_TIME = 0.25;         // seconds of nothing between two, so one fades before the next
const MAX_WAITING = 2;         // callouts waiting beyond this are stale by the time they'd show
export const FADE_TIME = 0.25;

// Most important first: a more important one cuts a less important one short
const KINDS = ['rescue', 'drain', 'swap', 'levelUp', 'finale', 'danger', 'hint', 'glow', 'held'];
const FIRST_TIMES_ONLY = new Set(['glow', 'held', 'hint']);
const rank = kind => KINDS.indexOf(kind);

function loadSeen() {
  try {
    return JSON.parse(localStorage.getItem(SEEN_KEY)) || {};
  } catch (e) {
    return {};
  }
}

/** Queues callouts and shows them one at a time, on the game's clock so a pause holds them. */
export class CalloutFeed {
  constructor() {
    this.current = null;
    this.age = 0;
    this.timeLeft = 0;
    this.gapLeft = 0;
    this.waiting = [];
    this.posted = new Set();
    this.seen = loadSeen();
    this.onShow = null; // told each callout as it appears, for screen readers
  }

  /** Whether posting `kind` now would show anything. */
  wants(kind) {
    return !FIRST_TIMES_ONLY.has(kind) || (!this.posted.has(kind) && (this.seen[kind] || 0) < EXPLAINED_SHOWINGS);
  }

  /** Say `kind` happened. `fill` replaces {key} placeholders in its copy. */
  post(kind, fill = {}, colors = []) {
    if (!this.wants(kind)) return;
    this.posted.add(kind);
    const text = copy().callouts[kind];
    const filled = line => Object.entries(fill).reduce((out, [k, v]) => out.replaceAll(`{${k}}`, v), line);
    // The web game has no conductor to hold its breath, so `danger` keeps to its title
    const detail = kind !== 'danger' && text.detail ? filled(text.detail) : null;
    const callout = { kind, title: filled(text.title), detail, colors };

    // A newer one of the same kind replaces the old; a more important one cuts in
    this.waiting = this.waiting.filter(c => c.kind !== kind);
    if (this.current && (rank(this.current.kind) > rank(kind) || this.current.kind === kind)) {
      this.show(callout);
      return;
    }
    this.waiting.push(callout);
    this.waiting.sort((a, b) => rank(a.kind) - rank(b.kind));
    this.waiting.length = Math.min(this.waiting.length, MAX_WAITING);
    if (!this.current && this.gapLeft <= 0) this.showNext();
  }

  /** Advance by dt seconds of play. */
  tick(dt) {
    if (this.current) {
      this.age += dt;
      this.timeLeft -= dt;
      if (this.timeLeft <= 0) {
        this.current = null;
        this.gapLeft = GAP_TIME;
      }
    } else if (this.gapLeft > 0) {
      this.gapLeft -= dt;
      if (this.gapLeft <= 0) this.showNext();
    }
  }

  /** How visible the current callout is now (0…1). */
  get opacity() {
    if (!this.current) return 0;
    return Math.min(1, this.age / FADE_TIME, this.timeLeft / FADE_TIME);
  }

  /** A new game: nothing showing or waiting, and the first-time kinds may teach again. */
  reset() {
    this.current = null;
    this.waiting = [];
    this.gapLeft = 0;
    this.posted = new Set();
  }

  showNext() {
    if (this.waiting.length) this.show(this.waiting.shift());
  }

  show(callout) {
    const shown = (this.seen[callout.kind] || 0);
    if (shown >= EXPLAINED_SHOWINGS) callout.detail = null;
    this.seen[callout.kind] = shown + 1;
    try {
      localStorage.setItem(SEEN_KEY, JSON.stringify(this.seen));
    } catch (e) { /* storage unavailable */ }
    this.current = callout;
    this.age = 0;
    this.timeLeft = callout.detail ? EXPLAINED_TIME : BRIEF_TIME;
    this.gapLeft = 0;
    this.onShow?.(callout);
  }
}
