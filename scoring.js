// scoring.js — Each mode's best score, one table per board size
// Big-board games are an easier game, so they keep their own bests.

const storageKey = board => (board === 'big' ? 'dialhex_highscores_big' : 'dialhex_highscores');

/** Load best scores for a board: { main, endless, sprint }. */
export function loadHighScores(board = 'standard') {
  try {
    const data = localStorage.getItem(storageKey(board));
    if (data) return JSON.parse(data);
  } catch (e) {
    // localStorage unavailable or corrupted
  }
  return { main: 0, endless: 0, sprint: 0 };
}

/** Save a score if it beats the record. Returns true if it's a new best. */
export function saveHighScore(mode, score, board = 'standard') {
  const scores = loadHighScores(board);
  if (score <= (scores[mode] || 0)) return false;
  scores[mode] = score;
  try {
    localStorage.setItem(storageKey(board), JSON.stringify(scores));
  } catch (e) {
    // localStorage unavailable
  }
  return true;
}
