// scoring.js — Score calculation and high score persistence

const STORAGE_KEY = 'dialhex_highscores';

/**
 * Calculate score for hex clears.
 * @param {number} count - Number of hexes cleared simultaneously
 * @param {number} level - Current level (color count, 2-8)
 * @returns {number} - Points earned
 */
export function calculateScore(count, level) {
  return count * 100 * level;
}

/**
 * Load high scores from localStorage.
 * @returns {{ main: number, endless: number, sprint: number }}
 */
export function loadHighScores() {
  try {
    const data = localStorage.getItem(STORAGE_KEY);
    if (data) {
      return JSON.parse(data);
    }
  } catch (e) {
    // localStorage unavailable or corrupted
  }
  return { main: 0, endless: 0, sprint: 0 };
}

/**
 * Save a high score if it beats the current record.
 * @param {string} mode - 'main', 'endless', or 'sprint'
 * @param {number} score - Score to save
 * @returns {boolean} - True if new high score
 */
export function saveHighScore(mode, score) {
  const scores = loadHighScores();
  if (score > (scores[mode] || 0)) {
    scores[mode] = score;
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(scores));
    } catch (e) {
      // localStorage unavailable
    }
    return true;
  }
  return false;
}
