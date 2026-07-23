(() => {
  'use strict';

  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const coarsePointer = window.matchMedia('(pointer: coarse)').matches;

  // ---------- Custom cursor (dot + lagging ring) ----------
  if (!reducedMotion && !coarsePointer) {
    const dot = document.createElement('div');
    dot.className = 'cursor-dot';
    const ring = document.createElement('div');
    ring.className = 'cursor-ring';
    document.body.append(dot, ring);

    let mouseX = window.innerWidth / 2;
    let mouseY = window.innerHeight / 2;
    let ringX = mouseX;
    let ringY = mouseY;

    window.addEventListener('mousemove', (e) => {
      mouseX = e.clientX;
      mouseY = e.clientY;
      dot.style.transform = `translate(${mouseX}px, ${mouseY}px) translate(-50%, -50%)`;
    });

    document.addEventListener('mousedown', () => ring.classList.add('click'));
    document.addEventListener('mouseup', () => ring.classList.remove('click'));

    const hoverTargets = 'a, button, .btn, .platform-card, .feature-card, .source-chip, .mockup-sidebar .m-item';
    document.addEventListener('mouseover', (e) => {
      if (e.target.closest(hoverTargets)) ring.classList.add('hover');
    });
    document.addEventListener('mouseout', (e) => {
      if (e.target.closest(hoverTargets)) ring.classList.remove('hover');
    });

    function raf() {
      ringX += (mouseX - ringX) * 0.18;
      ringY += (mouseY - ringY) * 0.18;
      ring.style.transform = `translate(${ringX}px, ${ringY}px) translate(-50%, -50%)`;
      requestAnimationFrame(raf);
    }
    requestAnimationFrame(raf);
  }

  // ---------- Scroll progress bar ----------
  const progress = document.createElement('div');
  progress.className = 'scroll-progress';
  document.body.appendChild(progress);
  function updateProgress() {
    const h = document.documentElement;
    const scrolled = h.scrollTop / (h.scrollHeight - h.clientHeight || 1);
    progress.style.width = `${Math.min(1, Math.max(0, scrolled)) * 100}%`;
  }
  window.addEventListener('scroll', updateProgress, { passive: true });
  updateProgress();

  // ---------- Hero: scramble-text headline reveal ----------
  const CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  function scrambleInto(el, finalText, delayBase) {
    const chars = finalText.split('');
    el.innerHTML = '';
    chars.forEach((ch, i) => {
      const span = document.createElement('span');
      span.className = 'char';
      span.textContent = ch === ' ' ? ' ' : ch;
      span.style.animationDelay = `${delayBase + i * 12}ms`;
      el.appendChild(span);
    });
    if (reducedMotion) {
      el.querySelectorAll('.char').forEach((s) => {
        s.style.animation = 'none';
        s.style.opacity = '1';
        s.style.filter = 'none';
        s.style.transform = 'none';
      });
      return;
    }
    // Brief character-scramble flicker before each letter settles into place.
    chars.forEach((ch, i) => {
      if (ch === ' ') return;
      const span = el.querySelectorAll('.char')[i];
      const settleAt = delayBase + i * 12;
      let ticks = 0;
      const maxTicks = 5;
      const iv = setInterval(() => {
        if (ticks >= maxTicks) {
          span.textContent = ch;
          clearInterval(iv);
          return;
        }
        span.textContent = CHARS[Math.floor(Math.random() * CHARS.length)];
        ticks += 1;
      }, Math.max(16, settleAt / maxTicks / 3));
    });
  }

  const heroLines = document.querySelectorAll('.hero h1 .line');
  heroLines.forEach((line, idx) => {
    const text = line.dataset.text || line.textContent;
    scrambleInto(line, text, 140 + idx * 320);
  });

  // ---------- Hero spotlight + particles follow the cursor ----------
  const hero = document.querySelector('.hero');
  const spotlight = document.querySelector('.hero-spotlight');
  if (hero && spotlight) {
    hero.addEventListener('pointermove', (e) => {
      const rect = hero.getBoundingClientRect();
      spotlight.style.setProperty('--mx', `${e.clientX - rect.left}px`);
      spotlight.style.setProperty('--my', `${e.clientY - rect.top}px`);
    });
  }

  const particleField = document.querySelector('.hero-particles');
  if (particleField && !reducedMotion) {
    for (let i = 0; i < 28; i++) {
      const p = document.createElement('span');
      p.className = 'particle';
      p.style.left = `${Math.random() * 100}%`;
      p.style.bottom = `-10px`;
      p.style.setProperty('--drift', `${(Math.random() - 0.5) * 80}px`);
      p.style.animationDuration = `${8 + Math.random() * 10}s`;
      p.style.animationDelay = `${Math.random() * 10}s`;
      particleField.appendChild(p);
    }
  }

  // ---------- Section heading word-by-word stagger ----------
  document.querySelectorAll('.section-head h2').forEach((h2) => {
    const words = h2.textContent.trim().split(/\s+/);
    h2.innerHTML = words
      .map((w, i) => `<span class="word-reveal" style="transition-delay:${i * 45}ms">${w}</span>`)
      .join(' ');
  });

  // ---------- Scroll reveal (grouped stagger, directional) ----------
  const revealEls = document.querySelectorAll('.reveal');
  const REVEAL_GROUPS = '.feature-grid, .markets-grid, .platform-grid, .pricing-grid, .trust-logos';
  const io = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        const el = entry.target;
        if (entry.isIntersecting) {
          el.classList.remove('leaving');
          el.classList.add('in');
        } else if (el.classList.contains('in')) {
          // Was visible and just left the viewport — if it left via the
          // top (scrolled up and out) fade/blur it away; if it left via
          // the bottom (rare: user scrolled back up past it) just reset
          // it to the pre-entrance state so it can play in again cleanly.
          if (entry.boundingClientRect.top < 0) {
            el.classList.add('leaving');
          } else {
            el.classList.remove('in');
            el.classList.remove('leaving');
          }
        }
      });
    },
    { threshold: 0.15, rootMargin: '0px 0px -6% 0px' }
  );
  revealEls.forEach((el) => {
    const group = el.closest(REVEAL_GROUPS);
    let delay = 0;
    if (group) {
      const siblings = Array.from(group.children).filter((c) => c.classList.contains('reveal'));
      delay = Math.min(siblings.indexOf(el), 8) * 80;
    }
    el.style.transitionDelay = `${delay}ms`;
    io.observe(el);
  });

  // ---------- Scroll-pinned screenshot gallery ----------
  // Each .pin-track is a tall runway; the card inside stays glued to the
  // viewport center (position: sticky) for that runway's length. The raw
  // scroll progress is smoothed with a per-frame lerp (not bound 1:1 to
  // the scroll event) so the motion feels fluid/damped rather than
  // snapping instantly to the scrollbar, like a slow-follow camera.
  const pinTracks = document.querySelectorAll('.pin-track');
  if (pinTracks.length && !reducedMotion) {
    const easeOutCubic = (x) => 1 - Math.pow(1 - x, 3);
    const easeInCubic = (x) => x * x * x;
    const clamp01 = (x) => Math.max(0, Math.min(1, x));
    const LERP = 0.07;

    const state = Array.from(pinTracks).map((track) => ({
      track,
      card: track.querySelector('.screenshot-card'),
      copy: track.querySelector('.screenshot-copy'),
      current: 0,
      target: 0,
    }));

    function readTargets() {
      const vh = window.innerHeight;
      state.forEach((s) => {
        const rect = s.track.getBoundingClientRect();
        const runway = rect.height - vh;
        s.target = runway > 0 ? clamp01(-rect.top / runway) : 0;
      });
    }

    function render() {
      state.forEach((s) => {
        if (!s.card) return;
        s.current += (s.target - s.current) * LERP;
        if (Math.abs(s.target - s.current) < 0.0004) s.current = s.target;
        const p = s.current;

        // Image: gentle pop in, a long untouched hold, gentle exit at the very end.
        const enter = clamp01(p / 0.14);
        const exit = clamp01((p - 0.92) / 0.08);
        const scale = 0.84 + 0.16 * easeOutCubic(enter) - 0.08 * easeInCubic(exit);
        const opacity = easeOutCubic(enter) * (1 - easeInCubic(exit));
        const cardBlur = Math.max((1 - easeOutCubic(enter)) * 10, easeInCubic(exit) * 14);
        s.card.style.transform = `scale(${scale.toFixed(4)})`;
        s.card.style.opacity = opacity.toFixed(3);
        s.card.style.filter = `blur(${cardBlur.toFixed(2)}px)`;

        if (s.copy) {
          // Text waits until the image has been sitting there a while, then holds until exit —
          // and once you've scrolled past it, it blurs away like everything else, not just fades.
          const textIn = clamp01((p - 0.68) / 0.2);
          const textOut = clamp01((p - 0.92) / 0.08);
          const textOpacity = easeOutCubic(textIn) * (1 - easeInCubic(textOut));
          const textBlur = Math.max((1 - easeOutCubic(textIn)) * 8, easeInCubic(textOut) * 14);
          s.copy.style.opacity = textOpacity.toFixed(3);
          s.copy.style.transform = `translateY(${((1 - easeOutCubic(textIn)) * 26).toFixed(1)}px)`;
          s.copy.style.filter = `blur(${textBlur.toFixed(2)}px)`;
        }
      });
      requestAnimationFrame(render);
    }

    readTargets();
    state.forEach((s) => { s.current = s.target; });
    window.addEventListener('scroll', readTargets, { passive: true });
    window.addEventListener('resize', readTargets);
    requestAnimationFrame(render);
  }

  // ---------- Live-looking ticker values ----------
  const tickerSymbols = [
    { sym: 'ZC (CORN)', base: 452.25 },
    { sym: 'ZW (WHEAT)', base: 601.5 },
    { sym: 'ZS (SOYBEANS)', base: 1332.0 },
    { sym: 'BASIS IL', base: -18.0 },
    { sym: 'BASIS IA', base: -22.5 },
    { sym: 'DXY', base: 104.32 },
    { sym: 'WASDE', base: 0, text: 'NEXT RELEASE IN 6D' },
    { sym: 'CRUDE (CL)', base: 78.4 },
  ];

  function buildTicker() {
    const track = document.getElementById('ticker-track');
    if (!track) return;

    const items = tickerSymbols.map((t) => {
      if (t.text) {
        return `<span class="ticker-item" data-sym="${t.sym}"><span class="sym">${t.sym}</span><span class="val">${t.text}</span></span>`;
      }
      return `<span class="ticker-item" data-sym="${t.sym}"><span class="sym">${t.sym}</span><span class="val">0.00</span><span class="chg">—</span></span>`;
    });

    // Duplicate the sequence once so the 50% translate loop is seamless.
    track.innerHTML = items.join('') + items.join('');
  }

  function updateTicker() {
    const track = document.getElementById('ticker-track');
    if (!track) return;
    if (!track.children.length) buildTicker();

    tickerSymbols.forEach((t) => {
      if (t.text) return;
      const delta = (Math.random() - 0.45) * (t.base * 0.01);
      const price = (t.base + delta).toFixed(2);
      const pct = ((delta / t.base) * 100).toFixed(2);
      const up = delta >= 0;
      track.querySelectorAll(`.ticker-item[data-sym="${t.sym}"]`).forEach((el) => {
        el.classList.add('flash');
        el.querySelector('.val').textContent = price;
        const chg = el.querySelector('.chg');
        chg.className = `chg ${up ? 'up' : 'down'}`;
        chg.textContent = `${up ? '▲' : '▼'} ${Math.abs(pct)}%`;
      });
    });

    requestAnimationFrame(() => {
      track.querySelectorAll('.flash').forEach((el) => el.classList.remove('flash'));
    });
  }

  function startTickerScroll() {
    const track = document.getElementById('ticker-track');
    if (!track) return;
    if (!track.children.length) buildTicker();

    // The track contains two identical sequences; scroll one sequence width then wrap.
    let sequenceWidth = track.scrollWidth / 2;
    if (!sequenceWidth) return;

    let x = 0;
    let lastTime = performance.now();
    // Match the previous ~38s loop speed: px/s = sequenceWidth / 38.
    const baseSpeed = sequenceWidth / 38;

    function measure() {
      sequenceWidth = track.scrollWidth / 2;
    }

    function frame(now) {
      if (document.hidden || reducedMotion) {
        lastTime = now;
        requestAnimationFrame(frame);
        return;
      }

      const dt = (now - lastTime) / 1000;
      lastTime = now;
      x -= baseSpeed * dt;
      if (x <= -sequenceWidth) {
        x += sequenceWidth;
      }

      track.style.transform = `translate3d(${x.toFixed(2)}px, 0, 0)`;
      requestAnimationFrame(frame);
    }

    window.addEventListener('resize', measure, { passive: true });
    requestAnimationFrame(frame);
  }

  buildTicker();
  startTickerScroll();
  updateTicker();
  setInterval(updateTicker, 3500);

  // ---------- Platform detection ----------
  function detectPlatform() {
    const ua = navigator.userAgent || '';
    const platform = navigator.platform || '';
    if (/Mac/i.test(platform) || /Macintosh/i.test(ua)) return 'macos';
    if (/Win/i.test(platform) || /Windows/i.test(ua)) return 'windows';
    if (/Linux/i.test(platform) && !/Android/i.test(ua)) return 'linux';
    return null;
  }

  const detected = detectPlatform();
  if (detected) {
    const card = document.querySelector(`[data-platform="${detected}"]`);
    if (card) card.classList.add('show-badge');

    const heroBtn = document.getElementById('hero-primary-download');
    const heroNote = document.getElementById('hero-recommend-note');
    const labels = { macos: 'macOS', windows: 'Windows', linux: 'Linux' };
    const hrefs = {
      macos: 'downloads/croploo-macos.dmg',
      windows: 'downloads/croploo-windows-setup.exe',
      linux: 'downloads/croploo-linux.AppImage',
    };
    if (heroBtn) {
      heroBtn.href = hrefs[detected];
      heroBtn.querySelector('.btn-label').textContent = `Download for ${labels[detected]}`;
    }
    if (heroNote) {
      heroNote.querySelector('.recommend').textContent = `Auto-detected: ${labels[detected]}`;
    }
  }

  // ---------- Animated stat counters ----------
  const COUNT_DURATION = 1400;
  function animateCount(el, target, decimals = 2, duration = COUNT_DURATION) {
    const start = performance.now();
    function tick(now) {
      const p = Math.min(1, (now - start) / duration);
      const eased = 1 - Math.pow(1 - p, 3);
      el.textContent = (target * eased).toFixed(decimals);
      if (p < 1) requestAnimationFrame(tick);
      else el.textContent = target.toFixed(decimals);
    }
    requestAnimationFrame(tick);
  }

  const counters = document.querySelectorAll('[data-count]');
  const countIo = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          const el = entry.target;
          const target = parseFloat(el.dataset.count);
          const decimals = el.dataset.decimals ? parseInt(el.dataset.decimals, 10) : 2;
          animateCount(el, target, decimals);
          countIo.unobserve(el);

          // Gentle continuous jitter after the initial count-up, echoing a live feed.
          setTimeout(() => {
            setInterval(() => {
              const jitter = target * (1 + (Math.random() - 0.5) * 0.01);
              el.textContent = jitter.toFixed(decimals);
            }, 2600 + Math.random() * 1400);
          }, COUNT_DURATION + 200);
        }
      });
    },
    { threshold: 0.4 }
  );
  counters.forEach((el) => countIo.observe(el));

  // ---------- Mockup chart: (re)draw on scroll into view, looping ----------
  const chart = document.querySelector('.mockup-chart');
  if (chart) {
    const line = chart.querySelector('.line');
    const fill = chart.querySelector('.fill');
    const dot = chart.querySelector('.dot-end');
    function playChart() {
      line.classList.remove('draw');
      fill.classList.remove('show');
      if (dot) dot.style.animation = 'none';
      void line.getBoundingClientRect(); // force reflow to restart animation
      line.classList.add('draw');
      setTimeout(() => fill.classList.add('show'), 1600);
      if (dot) {
        setTimeout(() => { dot.style.animation = 'dot-pop 400ms cubic-bezier(0.34,1.56,0.64,1) forwards'; }, 2100);
      }
    }
    const chartIo = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            playChart();
            if (!reducedMotion) setInterval(playChart, 9000);
            chartIo.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.4 }
    );
    chartIo.observe(chart);
  }

  // ---------- Magnetic buttons ----------
  if (!reducedMotion && !coarsePointer) {
    document.querySelectorAll('.btn').forEach((btn) => {
      const inner = document.createElement('span');
      inner.className = 'btn-inner';
      while (btn.firstChild) inner.appendChild(btn.firstChild);
      btn.appendChild(inner);

      btn.addEventListener('mousemove', (e) => {
        const rect = btn.getBoundingClientRect();
        const x = e.clientX - rect.left - rect.width / 2;
        const y = e.clientY - rect.top - rect.height / 2;
        inner.style.transform = `translate(${x * 0.18}px, ${y * 0.35}px)`;
      });
      btn.addEventListener('mouseleave', () => {
        inner.style.transform = 'translate(0, 0)';
      });
    });
  }

  // ---------- Button ripple on click ----------
  document.querySelectorAll('.btn').forEach((btn) => {
    btn.addEventListener('click', (e) => {
      const rect = btn.getBoundingClientRect();
      const size = Math.max(rect.width, rect.height);
      const ripple = document.createElement('span');
      ripple.className = 'ripple';
      ripple.style.width = ripple.style.height = `${size}px`;
      ripple.style.left = `${e.clientX - rect.left - size / 2}px`;
      ripple.style.top = `${e.clientY - rect.top - size / 2}px`;
      btn.appendChild(ripple);
      setTimeout(() => ripple.remove(), 650);
    });
  });

  // ---------- 3D tilt on cards ----------
  if (!reducedMotion && !coarsePointer) {
    document.querySelectorAll('.platform-card, .mockup').forEach((card) => {
      card.addEventListener('mousemove', (e) => {
        const rect = card.getBoundingClientRect();
        const px = (e.clientX - rect.left) / rect.width - 0.5;
        const py = (e.clientY - rect.top) / rect.height - 0.5;
        card.style.transform = `perspective(1000px) rotateX(${py * -4}deg) rotateY(${px * 4}deg) translateY(-2px)`;
      });
      card.addEventListener('mouseleave', () => {
        card.style.transform = '';
      });
    });
  }

  // ---------- Blob-field scroll parallax: blobs drift slower than the
  // page scrolls, on top of their own ambient drift animation, so the
  // mesh gradient keeps shifting instead of feeling pinned to the screen.
  const blobField = document.querySelector('.blob-field');
  if (blobField && !reducedMotion) {
    window.addEventListener(
      'scroll',
      () => {
        const shift = window.scrollY * 0.06;
        blobField.style.transform = `translateY(${shift}px)`;
      },
      { passive: true }
    );
  }

})();
