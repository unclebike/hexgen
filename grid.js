// grid.js — Triangular lattice inside a flat-topped hexagonal bin
//
// The bin is a hexagon of side SIZE (in triangle edges) tiled by 6·SIZE²
// equilateral triangles laid out in horizontal rows. Units: triangle side = 1,
// origin at the centre of the bin, y pointing down.
//
//   Cell (r, c)   — row r (0 = top), centred at x = c/2. It points up when
//                   r + c + SIZE is even, and down otherwise.
//   Vertex (k, j) — on the line between rows k-1 and k, at x = j/2.
//
// The six cells around an interior vertex form a small hexagon. That is the
// dial the player turns, and six same-coloured cells around one vertex make a
// Hex. Every interior vertex can host one, so hexes overlap.

export const SIZE = 6;
export const ROWS = SIZE * 2;
export const SQRT3 = Math.sqrt(3);
export const ROW_H = SQRT3 / 2;

const EPS = 1e-9;
const parity = n => ((n % 2) + 2) % 2;

export const key = (r, c) => `${r},${c}`;
export const isUp = (r, c) => parity(r + c + SIZE) === 0;

/** Position of vertex (k, j). */
export function vertexXY(k, j) {
  return { x: j / 2, y: (k - SIZE) * ROW_H };
}

/** The three corners of cell (r, c). */
export function cellVertices(r, c) {
  return isUp(r, c)
    ? [vertexXY(r, c), vertexXY(r + 1, c + 1), vertexXY(r + 1, c - 1)]
    : [vertexXY(r, c - 1), vertexXY(r, c + 1), vertexXY(r + 1, c)];
}

/** Centroid of cell (r, c). Also defined off the board, for spawn animation. */
export function cellCenter(r, c) {
  return { x: c / 2, y: (r - SIZE + (isUp(r, c) ? 2 / 3 : 1 / 3)) * ROW_H };
}

function insideBin({ x, y }) {
  return Math.abs(y) <= SIZE * ROW_H + EPS && Math.abs(x) + Math.abs(y) / SQRT3 <= SIZE + EPS;
}

/** Every cell in the bin, top row first. */
export const CELLS = [];
const cellSet = new Set();
for (let r = 0; r < ROWS; r++) {
  for (let c = -2 * SIZE; c <= 2 * SIZE; c++) {
    if (cellVertices(r, c).every(insideBin)) {
      CELLS.push({ r, c });
      cellSet.add(key(r, c));
    }
  }
}
export const isCell = (r, c) => cellSet.has(key(r, c));
export const TOP_CELLS = CELLS.filter(cell => cell.r === 0);

/** The six cells around vertex (k, j), clockwise from top-left. */
export function dialCells(k, j) {
  return [
    { r: k - 1, c: j - 1 }, { r: k - 1, c: j }, { r: k - 1, c: j + 1 },
    { r: k, c: j + 1 }, { r: k, c: j }, { r: k, c: j - 1 },
  ];
}

/** Every vertex whose six surrounding cells are all inside the bin. */
export const DIALS = [];
const dialSet = new Set();
for (let k = 1; k < ROWS; k++) {
  for (let j = -2 * SIZE; j <= 2 * SIZE; j++) {
    if (parity(k + j + SIZE) !== 0) continue;
    if (dialCells(k, j).every(({ r, c }) => isCell(r, c))) {
      DIALS.push({ k, j });
      dialSet.add(key(k, j));
    }
  }
}
export const isDial = (k, j) => dialSet.has(key(k, j));

/** Outer corners of the dial around vertex (k, j), clockwise from the right. */
export function dialOutline(k, j) {
  return [
    vertexXY(k, j + 2), vertexXY(k + 1, j + 1), vertexXY(k + 1, j - 1),
    vertexXY(k, j - 2), vertexXY(k - 1, j - 1), vertexXY(k - 1, j + 1),
  ];
}

/** Nearest dial to a point, or null if none is within maxDist. */
export function nearestDial(x, y, maxDist = Infinity) {
  let best = null;
  let bestD = maxDist * maxDist;
  for (const dial of DIALS) {
    const v = vertexXY(dial.k, dial.j);
    const d = (v.x - x) ** 2 + (v.y - y) ** 2;
    if (d < bestD) {
      bestD = d;
      best = dial;
    }
  }
  return best;
}
