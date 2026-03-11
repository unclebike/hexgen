// grid.js — Hexagonal grid data structure and coordinate math
// Axial coordinate system (q, r) for a hex-of-hexes board
// Each hex cell subdivided into 6 equilateral triangles (indices 0-5, CW from right)
// Pointy-top hex orientation: hexToPixel gives x = √3*q + √3/2*r, y = 3/2*r

const SQRT3 = Math.sqrt(3);

// The 6 axial direction vectors for hex neighbors
// Index matches triangle index: tri i faces direction i, cross-hex neighbor at HEX_DIRECTIONS[i]
const HEX_DIRECTIONS = [
  { q: 1, r: 0 },   // 0: E  (right)       — tri 0 faces right
  { q: 0, r: 1 },   // 1: SE (lower-right)  — tri 1 faces lower-right
  { q: -1, r: 1 },  // 2: SW (lower-left)   — tri 2 faces lower-left
  { q: -1, r: 0 },  // 3: W  (left)         — tri 3 faces left
  { q: 0, r: -1 },  // 4: NW (upper-left)   — tri 4 faces upper-left
  { q: 1, r: -1 },  // 5: NE (upper-right)  — tri 5 faces upper-right
];

/**
 * Get all valid hex coordinates for a hex-shaped board of given radius.
 * Radius 4 means the center hex plus 4 rings around it.
 */
export function getValidHexCoords(radius) {
  const coords = [];
  for (let q = -radius; q <= radius; q++) {
    for (let r = -radius; r <= radius; r++) {
      if (Math.abs(q + r) <= radius) {
        coords.push({ q, r });
      }
    }
  }
  return coords;
}

/**
 * Create a board key from hex coordinates.
 */
export function hexKey(q, r) {
  return `${q},${r}`;
}

/**
 * Parse a board key back to coordinates.
 */
export function parseHexKey(key) {
  const [q, r] = key.split(',').map(Number);
  return { q, r };
}

/**
 * Check if a hex coordinate is valid on the board.
 */
export function isValidHex(q, r, radius) {
  return Math.abs(q) <= radius && Math.abs(r) <= radius && Math.abs(q + r) <= radius;
}

/**
 * Create an empty board — Map<string, Triangle[]> with 6 triangles per hex cell.
 */
export function createBoard(radius = 4) {
  const board = new Map();
  const coords = getValidHexCoords(radius);
  for (const { q, r } of coords) {
    const triangles = [];
    for (let i = 0; i < 6; i++) {
      triangles.push({
        id: { q, r, triIndex: i },
        color: -1,
        isPowerUp: null,
        isGlowing: false,
      });
    }
    board.set(hexKey(q, r), triangles);
  }
  return board;
}

/**
 * Get the pixel position of a hex cell center.
 * Pointy-top orientation.
 */
export function hexToPixel(q, r, size) {
  return {
    x: size * (SQRT3 * q + (SQRT3 / 2) * r),
    y: size * (1.5 * r),
  };
}

/**
 * Get the pixel position of a triangle's centroid within its hex cell.
 * Triangle indices 0-5, clockwise from right.
 * tri 0=right(0°), 1=lower-right(60°), 2=lower-left(120°), 3=left(180°), 4=upper-left(240°), 5=upper-right(300°)
 */
export function triangleToPixel(triID, size) {
  const { q, r, triIndex } = triID;
  const center = hexToPixel(q, r, size);
  const angle = (60 * triIndex) * (Math.PI / 180);
  const dist = size * 0.5;
  return {
    x: center.x + dist * Math.cos(angle),
    y: center.y + dist * Math.sin(angle),
  };
}

/**
 * Get the 3 vertices of a triangle for rendering.
 * Each hex is divided into 6 equilateral triangles sharing the hex center.
 * Triangle i has vertices: hex center, hex vertex at (60*i - 30)°, hex vertex at (60*i + 30)°.
 */
export function triangleVertices(triID, size) {
  const { q, r, triIndex } = triID;
  const center = hexToPixel(q, r, size);

  const vertexAngle1 = (60 * triIndex - 30) * (Math.PI / 180);
  const vertexAngle2 = (60 * triIndex + 30) * (Math.PI / 180);

  return [
    { x: center.x, y: center.y }, // hex center
    { x: center.x + size * Math.cos(vertexAngle1), y: center.y + size * Math.sin(vertexAngle1) },
    { x: center.x + size * Math.cos(vertexAngle2), y: center.y + size * Math.sin(vertexAngle2) },
  ];
}

/**
 * Convert pixel coordinates back to the nearest TriangleID.
 * Used for hit testing (mouse/touch input).
 */
export function pixelToTriangle(px, py, size, radius = 4) {
  // First find the hex cell
  const q_frac = ((SQRT3 / 3) * px - (1 / 3) * py) / size;
  const r_frac = ((2 / 3) * py) / size;

  // Round to nearest hex (cube coordinate rounding)
  const s_frac = -q_frac - r_frac;
  let q = Math.round(q_frac);
  let r = Math.round(r_frac);
  let s = Math.round(s_frac);

  const q_diff = Math.abs(q - q_frac);
  const r_diff = Math.abs(r - r_frac);
  const s_diff = Math.abs(s - s_frac);

  if (q_diff > r_diff && q_diff > s_diff) {
    q = -r - s;
  } else if (r_diff > s_diff) {
    r = -q - s;
  }

  if (!isValidHex(q, r, radius)) return null;

  // Find which triangle within the hex
  const center = hexToPixel(q, r, size);
  const dx = px - center.x;
  const dy = py - center.y;

  // Angle from center, mapped to triangle index
  // tri 0 spans -30° to 30° (centered at 0°), so offset by +30 to align bucket boundaries
  let angle = Math.atan2(dy, dx) * (180 / Math.PI);
  angle = ((angle + 30) % 360 + 360) % 360;
  const triIndex = Math.floor(angle / 60);

  return { q, r, triIndex: triIndex % 6 };
}

/**
 * Get all triangles adjacent to a given triangle.
 * Each triangle has 3 edges:
 * - 2 edges shared with triangles in the same hex cell
 * - 1 edge shared with a triangle in a neighboring hex cell
 */
export function getAdjacentTriangles(triID, radius = 4) {
  const { q, r, triIndex } = triID;
  const neighbors = [];

  // Same-hex neighbors: (triIndex + 1) % 6 and (triIndex + 5) % 6
  neighbors.push({ q, r, triIndex: (triIndex + 1) % 6 });
  neighbors.push({ q, r, triIndex: (triIndex + 5) % 6 });

  // Cross-hex neighbor: triangle triIndex shares its outer edge with
  // triangle (triIndex + 3) % 6 in the hex at direction triIndex
  const dir = HEX_DIRECTIONS[triIndex];
  const nq = q + dir.q;
  const nr = r + dir.r;
  if (isValidHex(nq, nr, radius)) {
    neighbors.push({ q: nq, r: nr, triIndex: (triIndex + 3) % 6 });
  }

  return neighbors;
}

/**
 * Get all TriangleIDs within a given radius of rings around a center triangle.
 * Uses BFS by triangle adjacency.
 */
export function getTrianglesInRadius(center, radius, boardRadius = 4) {
  const visited = new Set();
  const key = (t) => `${t.q},${t.r},${t.triIndex}`;

  let current = [center];
  visited.add(key(center));

  for (let ring = 0; ring < radius; ring++) {
    const next = [];
    for (const tri of current) {
      for (const neighbor of getAdjacentTriangles(tri, boardRadius)) {
        const k = key(neighbor);
        if (!visited.has(k)) {
          visited.add(k);
          next.push(neighbor);
        }
      }
    }
    current = next;
  }

  return [...visited].map(k => {
    const [q, r, triIndex] = k.split(',').map(Number);
    return { q, r, triIndex };
  });
}

/**
 * Get the set of all valid TriangleIDs on the board.
 */
export function getBoardBounds(radius = 4) {
  const bounds = [];
  const coords = getValidHexCoords(radius);
  for (const { q, r } of coords) {
    for (let i = 0; i < 6; i++) {
      bounds.push({ q, r, triIndex: i });
    }
  }
  return bounds;
}

/**
 * Get a triangle from the board.
 */
export function getTriangle(board, triID) {
  const cell = board.get(hexKey(triID.q, triID.r));
  if (!cell) return null;
  return cell[triID.triIndex];
}

/**
 * Set a triangle on the board (returns new board — immutable).
 */
export function setTriangle(board, triID, triangle) {
  const newBoard = new Map(board);
  const key = hexKey(triID.q, triID.r);
  const cell = [...board.get(key)];
  cell[triID.triIndex] = { ...triangle, id: triID };
  newBoard.set(key, cell);
  return newBoard;
}

/**
 * Get the top-edge hex cells (where new triangles drop in).
 * Returns the topmost cell (minimum r) for each q column,
 * covering the entire upper perimeter of the hex board.
 */
export function getTopEdgeCells(radius = 4) {
  const coords = getValidHexCoords(radius);
  const topByQ = new Map();
  for (const { q, r } of coords) {
    if (!topByQ.has(q) || r < topByQ.get(q)) {
      topByQ.set(q, r);
    }
  }
  return [...topByQ.entries()].map(([q, r]) => ({ q, r }));
}

/**
 * Get the bottom-edge hex cells.
 */
export function getBottomEdgeCells(radius = 4) {
  const coords = getValidHexCoords(radius);
  const maxR = Math.max(...coords.map(c => c.r));
  return coords.filter(c => c.r === maxR);
}

/**
 * Get the y-coordinate of a triangle's centroid (for gravity calculations).
 * Uses unit size — only for relative comparisons.
 */
export function getCentroidY(triID) {
  return 1.5 * triID.r + 0.5 * Math.sin(triID.triIndex * Math.PI / 3);
}

/**
 * Get neighboring hex cells (for cursor movement between hexes).
 */
export function getHexNeighbors(q, r, radius = 4) {
  const neighbors = [];
  for (const dir of HEX_DIRECTIONS) {
    const nq = q + dir.q;
    const nr = r + dir.r;
    if (isValidHex(nq, nr, radius)) {
      neighbors.push({ q: nq, r: nr });
    }
  }
  return neighbors;
}

/**
 * Get the 6 outer vertices of a hex cell (for drawing hex outline).
 */
export function hexVertices(q, r, size) {
  const center = hexToPixel(q, r, size);
  const verts = [];
  for (let i = 0; i < 6; i++) {
    const angle = (60 * i - 30) * (Math.PI / 180);
    verts.push({
      x: center.x + size * Math.cos(angle),
      y: center.y + size * Math.sin(angle),
    });
  }
  return verts;
}

/**
 * TriangleID equality check.
 */
export function triEqual(a, b) {
  return a.q === b.q && a.r === b.r && a.triIndex === b.triIndex;
}

/**
 * TriangleID to string key.
 */
export function triKey(t) {
  return `${t.q},${t.r},${t.triIndex}`;
}

export { HEX_DIRECTIONS, SQRT3 };
