// settings.js — The player's choices, kept between visits

import { SPEEDS, BOARDS, ASSISTED_GAMES } from './progression.js';

const SPEED_KEY = 'dialhex_speed';
const BOARD_KEY = 'dialhex_board';
const HAND_KEY = 'dialhex_left_handed';
const ASSISTED_KEY = 'dialhex_assisted_games';

function storageGet(k) {
  try { return localStorage.getItem(k); } catch (e) { return null; }
}

function storageSet(k, v) {
  try { localStorage.setItem(k, v); } catch (e) { /* storage unavailable */ }
}

const saved = (k, options, fallback) => {
  const value = storageGet(k);
  return value in options ? value : fallback;
};

export const settings = {
  speed: saved(SPEED_KEY, SPEEDS, 'normal'),
  board: saved(BOARD_KEY, BOARDS, 'standard'),
  leftHanded: storageGet(HAND_KEY) === 'true',
};

export function setSpeed(speed) {
  settings.speed = speed;
  storageSet(SPEED_KEY, speed);
}

export function setBoard(board) {
  settings.board = board;
  storageSet(BOARD_KEY, board);
}

/** Move the spinner to the other side of the bin. */
export function toggleHand() {
  settings.leftHanded = !settings.leftHanded;
  storageSet(HAND_KEY, settings.leftHanded);
}

const assistedPlayed = () => Number(storageGet(ASSISTED_KEY)) || 0;

/** A new player's first few games are eased in; a sprint is always the real thing. */
export const shouldAssist = mode => mode !== 'sprint' && assistedPlayed() < ASSISTED_GAMES;

/** Count a finished assisted game. A win ends the easing at once. */
export function countAssistedGame(won) {
  storageSet(ASSISTED_KEY, won ? ASSISTED_GAMES : assistedPlayed() + 1);
}
