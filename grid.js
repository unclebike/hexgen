// grid.js — Triangular lattice inside a hexagonal bin
//
// The bin is a hexagon of side `size` (in triangle edges) tiled by 6·size²
// equilateral triangles laid out in rows. Units: triangle side = 1, origin at
// the centre of the bin, y pointing down.
//
//   Cell (r, c)   — row r (0 = top), centred at x = c/2. It points up when
//                   r + c + size is even, and down otherwise.
//   Vertex (k, j) — on the line between rows k-1 and k, at x = j/2.
//
// The six cells around an interior vertex form a small hexagon. That is the
// dial the player turns, and six same-coloured cells around one vertex make a
// Hex. Every interior vertex can host one, so hexes overlap.
//
// On screen the lattice is turned 90° so the bin stands on a vertex: lattice
// x runs down the screen and lattice y runs right to left.

export const SQRT3 = Math.sqrt(3);
export const ROW_H = SQRT3 / 2;

const EPS = 1e-9;
const parity = n => ((n % 2) + 2) % 2;

export const key = (r, c) => `${r},${c}`;

/** The six cells around vertex (k, j), clockwise from top-left. The same in any bin. */
export function dialCells(k, j) {
  return [
    { r: k - 1, c: j - 1 }, { r: k - 1, c: j }, { r: k - 1, c: j + 1 },
    { r: k, c: j + 1 }, { r: k, c: j }, { r: k, c: j - 1 },
  ];
}

/** One bin's lattice. Cells and dials only mean anything alongside the grid they came from. */
export class Grid {
  constructor(size) {
    this.size = size;
    this.rows = size * 2;

    const inside = ({ x, y }) =>
      Math.abs(y) <= size * ROW_H + EPS && Math.abs(x) + Math.abs(y) / SQRT3 <= size + EPS;

    this.cells = [];
    this.cellSet = new Set();
    for (let r = 0; r < this.rows; r++) {
      for (let c = -2 * size; c <= 2 * size; c++) {
        if (this.cellVertices(r, c).every(inside)) {
          this.cells.push({ r, c });
          this.cellSet.add(key(r, c));
        }
      }
    }

    this.dials = [];
    this.dialSet = new Set();
    for (let k = 1; k < this.rows; k++) {
      for (let j = -2 * size; j <= 2 * size; j++) {
        if (parity(k + j + size) !== 0) continue;
        if (dialCells(k, j).every(({ r, c }) => this.isCell(r, c))) {
          this.dials.push({ k, j });
          this.dialSet.add(key(k, j));
        }
      }
    }

    // Column r, top to bottom
    this.columns = Array.from({ length: this.rows }, (_, r) =>
      this.cells.filter(cell => cell.r === r).sort((a, b) => a.c - b.c));
    // The top cell of every column: where new triangles enter
    this.spawnCells = this.columns.map(column => column[0]);
    // Bottom of each column first, so a falling stack moves together; ties go top row first
    this.gravityOrder = [...this.cells].sort((a, b) => (a.c !== b.c ? b.c - a.c : a.r - b.r));

    // For every dial, the dials that share a cell with it (itself included)
    this.touching = new Map(this.dials.map(v => {
      const around = new Set(dialCells(v.k, v.j).map(({ r, c }) => key(r, c)));
      const near = this.dials.filter(d => dialCells(d.k, d.j).some(({ r, c }) => around.has(key(r, c))));
      return [key(v.k, v.j), near];
    }));
  }

  isCell(r, c) { return this.cellSet.has(key(r, c)); }
  isDial(k, j) { return this.dialSet.has(key(k, j)); }
  isUp(r, c) { return parity(r + c + this.size) === 0; }

  /** Position of vertex (k, j). */
  vertexXY(k, j) {
    return { x: j / 2, y: (k - this.size) * ROW_H };
  }

  /** The three corners of cell (r, c). */
  cellVertices(r, c) {
    return this.isUp(r, c)
      ? [this.vertexXY(r, c), this.vertexXY(r + 1, c + 1), this.vertexXY(r + 1, c - 1)]
      : [this.vertexXY(r, c - 1), this.vertexXY(r, c + 1), this.vertexXY(r + 1, c)];
  }

  /** Centroid of cell (r, c). Also defined off the board, for the spawn animation. */
  cellCenter(r, c) {
    return { x: c / 2, y: (r - this.size + (this.isUp(r, c) ? 2 / 3 : 1 / 3)) * ROW_H };
  }

  /** Outer corners of the dial around vertex (k, j), clockwise from the right. */
  dialOutline(k, j) {
    return [
      this.vertexXY(k, j + 2), this.vertexXY(k + 1, j + 1), this.vertexXY(k + 1, j - 1),
      this.vertexXY(k, j - 2), this.vertexXY(k - 1, j - 1), this.vertexXY(k - 1, j + 1),
    ];
  }

  /** The six corners of the bin itself. */
  binOutline() {
    const s = this.size;
    const h = s * ROW_H;
    return [
      { x: s, y: 0 }, { x: s / 2, y: h }, { x: -s / 2, y: h },
      { x: -s, y: 0 }, { x: -s / 2, y: -h }, { x: s / 2, y: -h },
    ];
  }

  /** Nearest dial to a point, or null if none is within maxDist. */
  nearestDial(x, y, maxDist = Infinity) {
    let best = null;
    let bestD = maxDist * maxDist;
    for (const dial of this.dials) {
      const v = this.vertexXY(dial.k, dial.j);
      const d = (v.x - x) ** 2 + (v.y - y) ** 2;
      if (d < bestD) {
        bestD = d;
        best = dial;
      }
    }
    return best;
  }
}

/** The bins, by board size. The big one has fewer, larger triangles. */
export const GRIDS = { standard: new Grid(6), big: new Grid(4) };
