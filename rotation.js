// rotation.js — Core rotation mechanic
// Rotates selected triangles 60° CW or CCW around a center point

import { hexToPixel, triangleToPixel, pixelToTriangle, getTriangle, triKey, triEqual } from './grid.js';

/**
 * Compute rotation mappings: where each selected triangle moves after 60° rotation.
 * @param {TriangleID} center - The center triangle of rotation
 * @param {TriangleID[]} selectedIDs - All triangles in the selection (including center)
 * @param {number} direction - 1 for CW, -1 for CCW
 * @param {number} size - Hex size for pixel calculations
 * @param {number} boardRadius - Board radius for validation
 * @returns {Array<{from, to}>|null} - Mappings, or null if rotation is invalid
 */
export function computeRotation(center, selectedIDs, direction, size, boardRadius = 4) {
  const centerPixel = triangleToPixel(center, size);
  const angle = direction * (Math.PI / 3); // ±60°
  const cosA = Math.cos(angle);
  const sinA = Math.sin(angle);

  const mappings = [];

  for (const tri of selectedIDs) {
    // Get pixel position relative to rotation center
    const pixel = triangleToPixel(tri, size);
    const dx = pixel.x - centerPixel.x;
    const dy = pixel.y - centerPixel.y;

    // Apply 2D rotation
    const rx = dx * cosA - dy * sinA;
    const ry = dx * sinA + dy * cosA;

    // Convert back to absolute pixel position
    const newX = centerPixel.x + rx;
    const newY = centerPixel.y + ry;

    // Find the triangle at the new position
    const newTri = pixelToTriangle(newX, newY, size, boardRadius);

    if (!newTri) {
      // Rotation moves a triangle off-board — invalid
      return null;
    }

    mappings.push({ from: tri, to: newTri });
  }

  // Validate: no two triangles map to the same destination
  const destKeys = new Set();
  for (const m of mappings) {
    const k = triKey(m.to);
    if (destKeys.has(k)) return null; // collision
    destKeys.add(k);
  }

  return mappings;
}

/**
 * Apply rotation to the board — move triangle data according to mappings.
 * Returns a new board (immutable update).
 * @param {Map} board - Current board state
 * @param {Array<{from, to}>} mappings - Rotation mappings from computeRotation
 * @returns {Map} - New board with triangles rotated
 */
export function applyRotation(board, mappings) {
  // Clone the board
  const newBoard = new Map();
  for (const [key, cell] of board) {
    newBoard.set(key, cell.map(t => ({ ...t })));
  }

  // Collect triangle data from source positions
  const sourceData = mappings.map(m => {
    const cell = board.get(`${m.from.q},${m.from.r}`);
    return { ...cell[m.from.triIndex] };
  });

  // Clear source positions (set to empty)
  for (const m of mappings) {
    const cell = newBoard.get(`${m.from.q},${m.from.r}`);
    cell[m.from.triIndex] = {
      id: m.from,
      color: -1,
      isPowerUp: null,
      isGlowing: false,
    };
  }

  // Place triangle data at destination positions
  for (let i = 0; i < mappings.length; i++) {
    const dest = mappings[i].to;
    const cell = newBoard.get(`${dest.q},${dest.r}`);
    cell[dest.triIndex] = {
      ...sourceData[i],
      id: dest,
    };
  }

  return newBoard;
}

/**
 * Perform a full rotation: compute + apply.
 * Returns { board, mappings } or null if invalid.
 */
export function rotate(board, center, selectedIDs, direction, size, boardRadius = 4) {
  const mappings = computeRotation(center, selectedIDs, direction, size, boardRadius);
  if (!mappings) return null;
  const newBoard = applyRotation(board, mappings);
  return { board: newBoard, mappings };
}
