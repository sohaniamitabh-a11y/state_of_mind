/**
 * State of Mind — Calm & Subtle Kinetic Grid Engine
 * - Gentle, low-acceleration magnetic warping (doesn't distract from text)
 * - Muted Dusty Rose & Warm Cream palette matching swatch
 * - Slow meditative shockwave ripples on click
 * - Silky 3D frame parallax
 * - Ambient harmonic drone
 */

document.addEventListener('DOMContentLoaded', () => {
  // DOM Elements
  const canvas = document.getElementById('kineticGridCanvas');
  const ctx = canvas.getContext('2d');
  const editorialFrame = document.getElementById('editorialFrame');
  const cursorGlow = document.getElementById('cursorGlow');
  const coordsReadout = document.getElementById('coordsReadout');
  const catalogItems = document.querySelectorAll('.catalog-item');

  // Radial Background Arcs
  const arcOuter = document.getElementById('arcOuter');
  const arcMid = document.getElementById('arcMid');
  const arcCore = document.getElementById('arcCore');

  // Control Buttons
  const btnWarpForce = document.getElementById('btnWarpForce');
  const warpModeLabel = document.getElementById('warpModeLabel');
  const btnPulseTempo = document.getElementById('btnPulseTempo');
  const btnAudioMood = document.getElementById('btnAudioMood');

  // Motion Parallax State
  let mouse = { x: window.innerWidth / 2, y: window.innerHeight / 2 };
  let target = { x: 0, y: 0 };
  let current = { x: 0, y: 0 };
  const EASE = 0.05; // Calm, smooth interpolation

  // Kinetic Grid Physics Configuration (Soft, Subtle, Non-Intrusive)
  const SPACING = 56; // Clean, elegant grid spacing
  let points = [];
  let cols = 0;
  let rows = 0;
  let ripples = [];

  // Calibrated Subtle Warp Modes
  const WARP_MODES = [
    { label: 'Subtle', strength: 0.35, maxPull: 28, radius: 180, spring: 0.04, damping: 0.92 },
    { label: 'Gentle', strength: 0.55, maxPull: 40, radius: 210, spring: 0.035, damping: 0.93 },
    { label: 'Whisper', strength: 0.20, maxPull: 18, radius: 150, spring: 0.045, damping: 0.91 }
  ];
  let currentWarpModeIndex = 0;

  // Resize Canvas and Build Grid
  function resizeCanvas() {
    canvas.width = window.innerWidth;
    canvas.height = window.innerHeight;
    initGrid();
  }

  function initGrid() {
    points = [];
    cols = Math.ceil(canvas.width / SPACING) + 2;
    rows = Math.ceil(canvas.height / SPACING) + 2;

    const startX = (canvas.width - (cols - 1) * SPACING) / 2;
    const startY = (canvas.height - (rows - 1) * SPACING) / 2;

    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const ox = startX + c * SPACING;
        const oy = startY + r * SPACING;
        points.push({
          ox,
          oy,
          x: ox,
          y: oy,
          vx: 0,
          vy: 0,
          col: c,
          row: r
        });
      }
    }
  }

  window.addEventListener('resize', resizeCanvas);
  resizeCanvas();

  // Pointer Listeners
  window.addEventListener('mousemove', (e) => {
    mouse.x = e.clientX;
    mouse.y = e.clientY;

    target.x = (e.clientX / window.innerWidth - 0.5) * 2;
    target.y = (e.clientY / window.innerHeight - 0.5) * 2;

    if (cursorGlow) {
      cursorGlow.style.left = `${e.clientX}px`;
      cursorGlow.style.top = `${e.clientY}px`;
    }
  });

  window.addEventListener('touchmove', (e) => {
    if (e.touches.length > 0) {
      const touch = e.touches[0];
      mouse.x = touch.clientX;
      mouse.y = touch.clientY;

      target.x = (touch.clientX / window.innerWidth - 0.5) * 2;
      target.y = (touch.clientY / window.innerHeight - 0.5) * 2;

      if (cursorGlow) {
        cursorGlow.style.left = `${touch.clientX}px`;
        cursorGlow.style.top = `${touch.clientY}px`;
      }
    }
  }, { passive: true });

  // Click -> Soft, Gentle Water Ripple
  window.addEventListener('pointerdown', (e) => {
    createShockwave(e.clientX, e.clientY);
  });

  function createShockwave(x, y) {
    ripples.push({
      x,
      y,
      radius: 0,
      maxRadius: Math.max(window.innerWidth, window.innerHeight) * 0.5,
      speed: 9, // Slower, calmer speed
      strength: 14 // Soft impulse
    });
  }

  // Update Points with Damped, Smooth Physics (No violent acceleration)
  function updatePhysics() {
    const config = WARP_MODES[currentWarpModeIndex];
    const mouseRadius = config.radius;
    const warpForce = config.strength;
    const maxPull = config.maxPull;
    const k = config.spring;
    const damping = config.damping;

    // Update ripples
    for (let i = ripples.length - 1; i >= 0; i--) {
      const rip = ripples[i];
      rip.radius += rip.speed;
      rip.strength *= 0.965;
      if (rip.radius > rip.maxRadius || rip.strength < 0.1) {
        ripples.splice(i, 1);
      }
    }

    // Apply forces smoothly
    for (let i = 0; i < points.length; i++) {
      const p = points[i];

      // 1. Gentle Hooke's Law restoration
      const fSpringX = (p.ox - p.x) * k;
      const fSpringY = (p.oy - p.y) * k;
      p.vx += fSpringX;
      p.vy += fSpringY;

      // 2. Smooth, clamped magnetic pull towards cursor
      const dx = mouse.x - p.x;
      const dy = mouse.y - p.y;
      const dist = Math.hypot(dx, dy);

      if (dist < mouseRadius && dist > 1) {
        const factor = (1 - dist / mouseRadius);
        // Soft cubic easing for organic gentle warp without sudden snaps
        const pull = Math.min(maxPull, factor * factor * warpForce * 18);
        p.vx += (dx / dist) * pull * 0.12;
        p.vy += (dy / dist) * pull * 0.12;
      }

      // 3. Ripple displacement
      for (let r = 0; r < ripples.length; r++) {
        const rip = ripples[r];
        const rdx = p.x - rip.x;
        const rdy = p.y - rip.y;
        const rDist = Math.hypot(rdx, rdy);
        const waveDist = Math.abs(rDist - rip.radius);

        if (waveDist < 50 && rDist > 1) {
          const waveFactor = (1 - waveDist / 50) * rip.strength;
          p.vx += (rdx / rDist) * waveFactor * 0.3;
          p.vy += (rdy / rDist) * waveFactor * 0.3;
        }
      }

      // 4. Apply velocity with high damping (calm motion)
      p.vx *= damping;
      p.vy *= damping;
      p.x += p.vx;
      p.y += p.vy;
    }
  }

  // Draw Subtle Grid with Exact Palette Shades
  function drawGrid() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Subtle Muted Rose Lines (#D77FA0 at 0.10 opacity)
    ctx.strokeStyle = 'rgba(215, 127, 160, 0.10)';
    ctx.lineWidth = 1;

    // Horizontal Lines
    for (let r = 0; r < rows; r++) {
      ctx.beginPath();
      for (let c = 0; c < cols; c++) {
        const idx = r * cols + c;
        const p = points[idx];
        if (c === 0) {
          ctx.moveTo(p.x, p.y);
        } else {
          ctx.lineTo(p.x, p.y);
        }
      }
      ctx.stroke();
    }

    // Vertical Lines
    for (let c = 0; c < cols; c++) {
      ctx.beginPath();
      for (let r = 0; r < rows; r++) {
        const idx = r * cols + c;
        const p = points[idx];
        if (r === 0) {
          ctx.moveTo(p.x, p.y);
        } else {
          ctx.lineTo(p.x, p.y);
        }
      }
      ctx.stroke();
    }

    // Subtle Dots (#BC5A75 / Warm Cream near pointer)
    const config = WARP_MODES[currentWarpModeIndex];
    const highlightRadius = config.radius;

    for (let i = 0; i < points.length; i++) {
      const p = points[i];
      const dist = Math.hypot(mouse.x - p.x, mouse.y - p.y);
      const isNear = dist < highlightRadius;

      const radius = isNear ? 1.8 + (1 - dist / highlightRadius) * 1.2 : 1.4;

      ctx.beginPath();
      ctx.arc(p.x, p.y, radius, 0, Math.PI * 2);

      if (isNear) {
        const factor = 1 - dist / highlightRadius;
        // Blend softly towards warm cream (#FAF4EE)
        ctx.fillStyle = `rgba(250, 244, 238, ${0.25 + factor * 0.45})`;
      } else {
        // Base dusty rose dot (#D77FA0 at 0.18 opacity)
        ctx.fillStyle = 'rgba(215, 127, 160, 0.18)';
      }
      ctx.fill();
    }
  }

  // Main Render Loop
  function mainLoop() {
    updatePhysics();
    drawGrid();

    // Smooth, slow 3D Parallax for Editorial Frame
    current.x += (target.x - current.x) * EASE;
    current.y += (target.y - current.y) * EASE;

    const rotX = -current.y * 9;
    const rotY = current.x * 12;
    const transX = current.x * 18;
    const transY = current.y * 14;

    if (editorialFrame) {
      editorialFrame.style.transform = `
        translate3d(${transX}px, ${transY}px, 0)
        rotateX(${rotX}deg)
        rotateY(${rotY}deg)
      `;
    }

    // Subtle Parallax on Background Radial Arcs
    if (arcOuter && arcMid && arcCore) {
      arcOuter.style.transform = `translateX(calc(-50% + ${transX * 0.25}px))`;
      arcMid.style.transform = `translateX(calc(-50% + ${transX * 0.4}px))`;
      arcCore.style.transform = `translateX(calc(-50% + ${transX * 0.55}px))`;
    }

    if (coordsReadout) {
      coordsReadout.textContent = `${rotX.toFixed(1)}° / ${rotY.toFixed(1)}°`;
    }

    requestAnimationFrame(mainLoop);
  }

  requestAnimationFrame(mainLoop);

  // Button 1: Magnetic Pull Force Mode
  if (btnWarpForce) {
    btnWarpForce.addEventListener('click', () => {
      currentWarpModeIndex = (currentWarpModeIndex + 1) % WARP_MODES.length;
      warpModeLabel.textContent = WARP_MODES[currentWarpModeIndex].label;
      btnWarpForce.classList.add('active');
      setTimeout(() => btnWarpForce.classList.remove('active'), 250);

      createShockwave(window.innerWidth / 2, window.innerHeight / 2);
    });
  }

  // Button 2: Breathing Tempo
  let isCalmTempo = false;
  if (btnPulseTempo) {
    btnPulseTempo.addEventListener('click', () => {
      isCalmTempo = !isCalmTempo;
      btnPulseTempo.classList.toggle('active', isCalmTempo);
      const arcs = [arcOuter, arcMid, arcCore];
      arcs.forEach(arc => {
        if (arc) arc.style.animationDuration = isCalmTempo ? '20s' : '14s';
      });
    });
  }

  // Button 3: Ambient Warm Drone Synthesizer (432Hz Harmonic Roots)
  let audioContext = null;
  let isAudioPlaying = false;
  let oscillators = [];
  let gainNode = null;

  if (btnAudioMood) {
    btnAudioMood.addEventListener('click', () => {
      if (!audioContext) {
        const AudioContextClass = window.AudioContext || window.webkitAudioContext;
        audioContext = new AudioContextClass();
      }

      if (!isAudioPlaying) {
        if (audioContext.state === 'suspended') {
          audioContext.resume();
        }
        startWarmDrone();
        btnAudioMood.classList.add('active');
        isAudioPlaying = true;
      } else {
        stopWarmDrone();
        btnAudioMood.classList.remove('active');
        isAudioPlaying = false;
      }
    });
  }

  function startWarmDrone() {
    const freqs = [108, 162, 216]; // Meditative harmonic chords
    gainNode = audioContext.createGain();
    gainNode.gain.setValueAtTime(0.001, audioContext.currentTime);
    gainNode.gain.exponentialRampToValueAtTime(0.05, audioContext.currentTime + 3);
    gainNode.connect(audioContext.destination);

    oscillators = freqs.map((freq, i) => {
      const osc = audioContext.createOscillator();
      const oscGain = audioContext.createGain();
      osc.type = 'sine';
      osc.frequency.setValueAtTime(freq, audioContext.currentTime);

      const lfo = audioContext.createOscillator();
      const lfoGain = audioContext.createGain();
      lfo.frequency.value = 0.08 + i * 0.03;
      lfoGain.gain.value = 0.3;
      lfo.connect(osc.frequency);
      lfo.start();

      oscGain.gain.value = 0.25 / freqs.length;
      osc.connect(oscGain);
      oscGain.connect(gainNode);
      osc.start();
      return { osc, lfo };
    });
  }

  function stopWarmDrone() {
    if (gainNode && audioContext) {
      gainNode.gain.exponentialRampToValueAtTime(0.0001, audioContext.currentTime + 1.5);
      setTimeout(() => {
        oscillators.forEach(o => {
          o.osc.stop();
          o.lfo.stop();
        });
        oscillators = [];
      }, 1500);
    }
  }

  // Button 4: Trigger Shockwave Button
  const btnShockwave = document.getElementById('btnShockwave');
  if (btnShockwave) {
    btnShockwave.addEventListener('click', (e) => {
      e.stopPropagation();
      createShockwave(window.innerWidth / 2, window.innerHeight / 2);
      btnShockwave.classList.add('active');
      setTimeout(() => btnShockwave.classList.remove('active'), 300);
    });
  }

  // Catalog item selection
  catalogItems.forEach(item => {
    item.addEventListener('click', () => {
      catalogItems.forEach(i => i.classList.remove('active'));
      item.classList.add('active');
    });
  });
});
