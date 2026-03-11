// audio.js — Procedural Web Audio sound engine
// All sounds generated with oscillators and filters — no audio files

let audioCtx = null;
let masterGain = null;
let muted = false;
let droneOsc = null;
let droneGain = null;

// Base frequencies for color-mapped tones (C4 to C5, chromatic)
const COLOR_FREQUENCIES = [
  261.63, // C4  — green
  277.18, // C#4 — orange
  293.66, // D4  — yellow
  311.13, // D#4 — red
  329.63, // E4  — blue
  349.23, // F4  — purple
  369.99, // F#4 — cyan
  392.00, // G4  — dark green
];

/**
 * Initialize the audio context (must be called from user interaction).
 */
export function initAudio() {
  if (audioCtx) return;
  try {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    masterGain = audioCtx.createGain();
    masterGain.gain.value = muted ? 0 : 0.5;
    masterGain.connect(audioCtx.destination);

    // Load mute preference
    try {
      muted = localStorage.getItem('dialhex_muted') === 'true';
      masterGain.gain.value = muted ? 0 : 0.5;
    } catch (e) {}
  } catch (e) {
    // Web Audio not available — silent mode
    audioCtx = null;
  }
}

/**
 * Ensure audio context is running (call after user interaction).
 */
export function resumeAudio() {
  if (audioCtx && audioCtx.state === 'suspended') {
    audioCtx.resume();
  }
}

/**
 * Play a sound by type.
 */
export function playSound(type, params = {}) {
  if (!audioCtx || muted) return;

  switch (type) {
    case 'place': playSoundPlace(params.colorIndex || 0); break;
    case 'rotate': playSoundRotate(); break;
    case 'clear': playSoundClear(params.colorIndex || 0); break;
    case 'levelup': playSoundLevelUp(params.colorIndex || 0); break;
    case 'gameover': playSoundGameOver(); break;
  }
}

/**
 * Triangle place sound: short sine tone mapped to color.
 */
function playSoundPlace(colorIndex) {
  const freq = COLOR_FREQUENCIES[colorIndex] || 261.63;
  const osc = audioCtx.createOscillator();
  const gain = audioCtx.createGain();

  osc.type = 'sine';
  osc.frequency.value = freq;
  gain.gain.setValueAtTime(0.15, audioCtx.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.08);

  osc.connect(gain);
  gain.connect(masterGain);
  osc.start();
  osc.stop(audioCtx.currentTime + 0.08);
}

/**
 * Rotation sound: soft white noise click.
 */
function playSoundRotate() {
  const bufferSize = audioCtx.sampleRate * 0.02;
  const buffer = audioCtx.createBuffer(1, bufferSize, audioCtx.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < bufferSize; i++) {
    data[i] = (Math.random() * 2 - 1) * (1 - i / bufferSize);
  }

  const source = audioCtx.createBufferSource();
  source.buffer = buffer;

  const filter = audioCtx.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.value = 2000;
  filter.Q.value = 1;

  const gain = audioCtx.createGain();
  gain.gain.value = 0.1;

  source.connect(filter);
  filter.connect(gain);
  gain.connect(masterGain);
  source.start();
}

/**
 * Hex clear sound: rising arpeggio + shimmer.
 */
function playSoundClear(colorIndex) {
  const baseFreq = COLOR_FREQUENCIES[colorIndex] || 261.63;
  const notes = [baseFreq, baseFreq * 1.25, baseFreq * 1.5]; // root, third, fifth approx

  notes.forEach((freq, i) => {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    const startTime = audioCtx.currentTime + i * 0.05;
    gain.gain.setValueAtTime(0.2, startTime);
    gain.gain.exponentialRampToValueAtTime(0.001, startTime + 0.1);
    osc.connect(gain);
    gain.connect(masterGain);
    osc.start(startTime);
    osc.stop(startTime + 0.1);
  });

  // Shimmer: high white noise with fade
  const shimmerLen = audioCtx.sampleRate * 0.4;
  const shimmerBuf = audioCtx.createBuffer(1, shimmerLen, audioCtx.sampleRate);
  const shimmerData = shimmerBuf.getChannelData(0);
  for (let i = 0; i < shimmerLen; i++) {
    shimmerData[i] = (Math.random() * 2 - 1);
  }
  const shimmerSource = audioCtx.createBufferSource();
  shimmerSource.buffer = shimmerBuf;

  const hpf = audioCtx.createBiquadFilter();
  hpf.type = 'highpass';
  hpf.frequency.value = 4000;

  const shimmerGain = audioCtx.createGain();
  const shimmerStart = audioCtx.currentTime + 0.15;
  shimmerGain.gain.setValueAtTime(0.08, shimmerStart);
  shimmerGain.gain.exponentialRampToValueAtTime(0.001, shimmerStart + 0.4);

  shimmerSource.connect(hpf);
  hpf.connect(shimmerGain);
  shimmerGain.connect(masterGain);
  shimmerSource.start(shimmerStart);
}

/**
 * Level up sound: major chord.
 */
function playSoundLevelUp(colorIndex) {
  const root = COLOR_FREQUENCIES[colorIndex] || 261.63;
  const chord = [root, root * 5 / 4, root * 3 / 2]; // major chord

  chord.forEach(freq => {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();
    osc.type = 'sine';
    osc.frequency.value = freq;
    gain.gain.setValueAtTime(0.15, audioCtx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, audioCtx.currentTime + 0.5);
    osc.connect(gain);
    gain.connect(masterGain);
    osc.start();
    osc.stop(audioCtx.currentTime + 0.5);
  });
}

/**
 * Game over sound: descending chromatic run.
 */
function playSoundGameOver() {
  const notes = [392, 369.99, 349.23, 329.63]; // G4 down to E4
  notes.forEach((freq, i) => {
    const osc = audioCtx.createOscillator();
    const gain = audioCtx.createGain();

    const lpf = audioCtx.createBiquadFilter();
    lpf.type = 'lowpass';
    lpf.frequency.value = 1000;

    osc.type = 'sawtooth';
    osc.frequency.value = freq;
    const startTime = audioCtx.currentTime + i * 0.15;
    gain.gain.setValueAtTime(0.12, startTime);
    gain.gain.exponentialRampToValueAtTime(0.001, startTime + 0.15);

    osc.connect(lpf);
    lpf.connect(gain);
    gain.connect(masterGain);
    osc.start(startTime);
    osc.stop(startTime + 0.15);
  });
}

/**
 * Start background drone.
 */
export function startDrone(colorCount) {
  if (!audioCtx) return;
  stopDrone();

  droneOsc = audioCtx.createOscillator();
  droneGain = audioCtx.createGain();

  droneOsc.type = 'sine';
  droneOsc.frequency.value = 40;
  droneGain.gain.value = 0.03;

  // Add vibrato based on color count
  const lfo = audioCtx.createOscillator();
  const lfoGain = audioCtx.createGain();
  lfo.type = 'sine';
  lfo.frequency.value = colorCount; // 1Hz per color
  lfoGain.gain.value = 2; // 2Hz frequency deviation
  lfo.connect(lfoGain);
  lfoGain.connect(droneOsc.frequency);
  lfo.start();

  droneOsc.connect(droneGain);
  droneGain.connect(masterGain);
  droneOsc.start();
}

/**
 * Stop background drone.
 */
export function stopDrone() {
  if (droneOsc) {
    try { droneOsc.stop(); } catch (e) {}
    droneOsc = null;
  }
  if (droneGain) {
    droneGain = null;
  }
}

/**
 * Toggle mute.
 */
export function toggleMute() {
  muted = !muted;
  if (masterGain) {
    masterGain.gain.value = muted ? 0 : 0.5;
  }
  try {
    localStorage.setItem('dialhex_muted', muted.toString());
  } catch (e) {}
  return muted;
}

/**
 * Check if muted.
 */
export function isMuted() {
  return muted;
}

/**
 * Set master volume (0-1).
 */
export function setVolume(v) {
  if (masterGain && !muted) {
    masterGain.gain.value = v * 0.5;
  }
}
