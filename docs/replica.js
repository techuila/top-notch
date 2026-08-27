/* TopNotch live replica.
   Mirrors the shipped app: geometry from ShellMetrics/Metrics, motion from Motion.swift,
   palette from Style.swift. The music pane really plays: a hidden YouTube IFrame player
   is created lazily on the first play click and nothing from youtube.com loads before
   that. If the embed is blocked the transport degrades to a fake 3:33 clock. */
(function () {
  "use strict";

  var tn = document.getElementById("tn");
  var screenEl = document.getElementById("replica-screen");
  if (!tn || !screenEl) return;

  // ---- geometry, mirroring ShellMetrics / Metrics ----
  var PANES = ["music", "drop", "notes", "focus"];
  var CONTENT_H = { music: 136, drop: 122, notes: 170, focus: 132 };
  var NOTES_EDITOR_H = 236;
  var notesOpen = false;
  var PANE_TOP = 94; /* paneTop 76 + pill breathing room 18 */
  var PANE_BOTTOM = 18;
  var IDLE_H = 44, PROX_H = 47; /* ShellMetrics.idleHeight / proximityHeight */
  var PAD_IDLE = 11, PAD_PROX = 14; /* shoulder padding */
  var ART = 24, WAVE = 27, CHIP = 52, SLOT_GAP = 8;
  var EXPANDED_W = 520; /* Metrics.expandedWidth */
  var PROXIMITY_RADIUS = 120; /* Motion.proximityRadius */
  var CLOSE_GRACE = 140; /* Motion.closeGrace */

  var state = "idle"; /* idle | proximity | expanded */
  var pane = "music";

  var panelEl = tn.querySelector(".tn-panel");
  var track = tn.querySelector(".tn-track");
  var pills = [].slice.call(tn.querySelectorAll(".tn-pill"));
  var paneEls = [].slice.call(tn.querySelectorAll(".tn-pane"));

  function housingWidth() {
    return Math.min(148, Math.round(screenEl.clientWidth * 0.34));
  }

  function chipVisible() {
    return pomo.running && state !== "expanded";
  }

  function applySize() {
    var w, h;
    if (state === "expanded") {
      w = Math.min(EXPANDED_W, screenEl.clientWidth - 16);
      var content = pane === "notes" && notesOpen ? NOTES_EDITOR_H : CONTENT_H[pane];
      h = PANE_TOP + content + PANE_BOTTOM;
    } else {
      var pad = state === "proximity" ? PAD_PROX : PAD_IDLE;
      var left = ART + (chipVisible() ? CHIP + SLOT_GAP : 0);
      var shoulder = Math.max(left, WAVE) + pad * 2;
      w = housingWidth() + 2 * shoulder;
      h = state === "proximity" ? PROX_H : IDLE_H;
    }
    tn.style.setProperty("--tn-housing", housingWidth() + "px");
    tn.style.width = w + "px";
    tn.style.height = h + "px";
  }

  function setState(next) {
    if (next === state) return;
    state = next;
    tn.dataset.state = next;
    tn.dataset.chip = chipVisible() ? "1" : "0";
    tn.setAttribute("aria-expanded", next === "expanded" ? "true" : "false");
    panelEl.inert = next !== "expanded";
    applySize();
  }

  function setPane(next) {
    pane = next;
    tn.dataset.pane = next;
    var idx = PANES.indexOf(next);
    track.style.transform = "translateX(-" + idx * 100 + "%)";
    pills.forEach(function (p) {
      p.setAttribute("aria-selected", p.dataset.pane === next ? "true" : "false");
    });
    paneEls.forEach(function (el) {
      el.inert = el.dataset.pane !== next;
    });
    applySize();
  }

  pills.forEach(function (p) {
    p.addEventListener("click", function () {
      setPane(p.dataset.pane);
    });
  });

  // ---- cursor: proximity breathe, hover expand, grace on leave ----
  var last = { x: -1e4, y: -1e4 };
  var graceTimer = null;
  var moveQueued = false;

  function rectDist(x, y, r) {
    var dx = Math.max(r.left - x, 0, x - r.right);
    var dy = Math.max(r.top - y, 0, y - r.bottom);
    return Math.sqrt(dx * dx + dy * dy);
  }

  function onSurface(x, y) {
    var r = tn.getBoundingClientRect();
    return x >= r.left - 2 && x <= r.right + 2 && y >= r.top - 2 && y <= r.bottom + 2;
  }

  function settle() {
    var d = rectDist(last.x, last.y, tn.getBoundingClientRect());
    setState(d <= PROXIMITY_RADIUS ? "proximity" : "idle");
  }

  function evaluatePointer() {
    if (onSurface(last.x, last.y)) {
      clearTimeout(graceTimer);
      graceTimer = null;
      setState("expanded");
      return;
    }
    if (state === "expanded") {
      if (tn.contains(document.activeElement)) return; /* keyboard user parked inside */
      if (!graceTimer) {
        graceTimer = setTimeout(function () {
          graceTimer = null;
          if (state !== "expanded" || onSurface(last.x, last.y)) return;
          if (tn.contains(document.activeElement)) return;
          settle();
        }, CLOSE_GRACE);
      }
      return;
    }
    settle();
  }

  document.addEventListener("pointermove", function (e) {
    if (e.pointerType !== "mouse") return;
    last.x = e.clientX;
    last.y = e.clientY;
    if (moveQueued) return;
    moveQueued = true;
    requestAnimationFrame(function () {
      moveQueued = false;
      evaluatePointer();
    });
  }, { passive: true });

  // Touch: tap opens, tap outside closes.
  tn.addEventListener("click", function () {
    if (state !== "expanded") setState("expanded");
  });
  document.addEventListener("click", function (e) {
    if (state !== "expanded") return;
    if (tn.contains(e.target)) return;
    if (window.matchMedia("(hover: none)").matches) setState("idle");
  });

  // ---- keyboard: reachable, never trapping ----
  tn.addEventListener("keydown", function (e) {
    var tag = e.target.tagName;
    if (e.key === "Escape") {
      setState("idle");
      tn.focus();
      return;
    }
    if (e.target === tn && (e.key === "Enter" || e.key === " ")) {
      e.preventDefault();
      setState(state === "expanded" ? "idle" : "expanded");
      return;
    }
    if (state === "expanded" && (e.key === "ArrowLeft" || e.key === "ArrowRight")) {
      if (tag === "TEXTAREA" || tag === "INPUT") return;
      var idx = PANES.indexOf(pane) + (e.key === "ArrowRight" ? 1 : -1);
      if (idx >= 0 && idx < PANES.length) {
        e.preventDefault();
        setPane(PANES[idx]);
      }
    }
  });
  tn.addEventListener("focusout", function () {
    setTimeout(function () {
      if (state !== "expanded") return;
      if (tn.contains(document.activeElement)) return;
      if (onSurface(last.x, last.y)) return;
      settle();
    }, 0);
  });

  // ---- music: the hidden player and the transport ----
  var VIDEO_ID = "dQw4w9WgXcQ";
  var DURATION_FALLBACK = 213; /* 3:33 */
  var duration = DURATION_FALLBACK;
  var fraction = 0;
  var playing = false;
  var wantPlay = false;
  var repeatMode = 0; /* 0 off, 1 all, 2 one */
  var yt = null;
  var ytPhase = "none"; /* none | loading | ready | dead */
  var failTimer = null;
  var pollTimer = null;
  var fake = { on: false, base: 0, started: 0 };

  var playBtn = document.getElementById("mp-play");
  var playIco = playBtn.querySelector(".ico-play");
  var pauseIco = playBtn.querySelector(".ico-pause");
  var scrubEl = document.getElementById("mp-scrub");
  var scrubFill = document.getElementById("mp-scrub-fill");
  var borderFill = document.getElementById("tn-borderfill");
  var elapsedEl = document.getElementById("mp-elapsed");
  var totalEl = document.getElementById("mp-total");
  var shuffleBtn = document.getElementById("mp-shuffle");
  var repeatBtn = document.getElementById("mp-repeat");

  function fmt(s) {
    s = Math.max(0, Math.round(s));
    var m = Math.floor(s / 60);
    var r = s % 60;
    return m + ":" + (r < 10 ? "0" : "") + r;
  }

  function paintProgress() {
    var pct = (Math.min(Math.max(fraction, 0), 1) * 100).toFixed(2) + "%";
    scrubFill.style.width = pct;
    borderFill.style.width = pct;
    elapsedEl.textContent = fmt(fraction * duration);
    totalEl.textContent = fmt(duration);
    scrubEl.setAttribute("aria-valuenow", String(Math.round(fraction * 100)));
  }

  function setPlaying(on) {
    playing = on;
    tn.dataset.playing = on ? "1" : "0";
    playIco.style.display = on ? "none" : "";
    pauseIco.style.display = on ? "" : "none";
    playBtn.setAttribute("aria-label", on ? "Pause" : "Play");
    if (on) startPoll();
    else stopPoll();
  }

  function currentFakeT() {
    return playing ? fake.base + (performance.now() - fake.started) / 1000 : fake.base;
  }

  function startPoll() {
    stopPoll();
    pollTimer = setInterval(function () {
      if (scrubEl.classList.contains("dragging")) return;
      if (fake.on) {
        var t = currentFakeT();
        if (t >= duration) {
          if (repeatMode > 0) {
            fake.base = 0;
            fake.started = performance.now();
            t = 0;
          } else {
            fake.base = duration;
            setPlaying(false);
            t = duration;
          }
        }
        fraction = t / duration;
      } else if (yt && ytPhase === "ready") {
        try {
          var d = yt.getDuration();
          if (d && d > 0) duration = d;
          fraction = (yt.getCurrentTime() || 0) / duration;
        } catch (err) { /* player mid-teardown; keep the last frame */ }
      }
      paintProgress();
    }, 250);
  }

  function stopPoll() {
    clearInterval(pollTimer);
    pollTimer = null;
  }

  function enterFake() {
    if (fake.on) return;
    ytPhase = "dead";
    fake.on = true;
    fake.base = fraction * duration;
    fake.started = performance.now();
    duration = DURATION_FALLBACK;
    if (wantPlay) setPlaying(true);
  }

  function loadYouTube() {
    ytPhase = "loading";
    /* Created only now, inside the first play gesture. 1x1 and offscreen. */
    var host = document.createElement("div");
    host.id = "tn-yt";
    host.style.cssText =
      "position:fixed;left:-9999px;bottom:0;width:1px;height:1px;overflow:hidden;";
    document.body.appendChild(host);

    window.onYouTubeIframeAPIReady = function () {
      yt = new YT.Player("tn-yt", {
        width: 1,
        height: 1,
        videoId: VIDEO_ID,
        playerVars: { autoplay: 1, playsinline: 1, controls: 0, disablekb: 1 },
        events: {
          onReady: function (e) {
            ytPhase = "ready";
            if (wantPlay) e.target.playVideo();
          },
          onStateChange: function (e) {
            if (e.data === YT.PlayerState.PLAYING) {
              clearTimeout(failTimer);
              failTimer = null;
              fake.on = false;
              setPlaying(true);
            } else if (e.data === YT.PlayerState.PAUSED) {
              if (!fake.on) setPlaying(false);
            } else if (e.data === YT.PlayerState.ENDED) {
              if (repeatMode > 0) {
                yt.seekTo(0, true);
                yt.playVideo();
              } else {
                fraction = 1;
                paintProgress();
                setPlaying(false);
              }
            }
          },
          onError: function () {
            enterFake();
          },
        },
      });
    };

    var s = document.createElement("script");
    s.src = "https://www.youtube.com/iframe_api";
    s.onerror = function () {
      enterFake();
    };
    document.head.appendChild(s);

    /* Nothing audibly playing a few seconds after the gesture means the embed is
       blocked; degrade to the fake clock rather than leaving a dead transport. */
    failTimer = setTimeout(function () {
      if (!playing) enterFake();
    }, 3500);
  }

  function seekTo(f) {
    fraction = Math.min(Math.max(f, 0), 1);
    if (fake.on) {
      fake.base = fraction * duration;
      fake.started = performance.now();
    } else if (yt && ytPhase === "ready") {
      try {
        yt.seekTo(fraction * duration, true);
      } catch (err) { /* not seekable yet */ }
    }
    paintProgress();
  }

  function togglePlay() {
    if (playing) {
      wantPlay = false;
      if (fake.on) {
        fake.base = Math.min(currentFakeT(), duration);
        setPlaying(false);
      } else if (yt && ytPhase === "ready") {
        yt.pauseVideo();
      } else {
        setPlaying(false);
      }
      return;
    }
    wantPlay = true;
    if (fraction >= 0.999) seekTo(0);
    if (ytPhase === "none") loadYouTube();
    else if (fake.on) {
      fake.started = performance.now();
      setPlaying(true);
    } else if (ytPhase === "ready") yt.playVideo();
    /* while loading, onReady starts it */
  }

  playBtn.addEventListener("click", togglePlay);
  document.getElementById("mp-prev").addEventListener("click", function () {
    seekTo(0); /* one track on this shelf, and we are never giving it up */
  });
  document.getElementById("mp-next").addEventListener("click", function () {
    seekTo(0);
  });

  shuffleBtn.addEventListener("click", function () {
    var on = shuffleBtn.getAttribute("aria-pressed") === "true";
    shuffleBtn.setAttribute("aria-pressed", on ? "false" : "true");
    shuffleBtn.setAttribute("aria-label", on ? "Shuffle off" : "Shuffle on");
  });
  repeatBtn.addEventListener("click", function () {
    repeatMode = (repeatMode + 1) % 3;
    repeatBtn.setAttribute("aria-pressed", repeatMode > 0 ? "true" : "false");
    repeatBtn.dataset.mode = ["off", "all", "one"][repeatMode];
    repeatBtn.setAttribute(
      "aria-label",
      ["Repeat off", "Repeat all", "Repeat one"][repeatMode]
    );
  });

  // Scrubbing: preview while dragging, commit on release. Arrow keys nudge 5 seconds.
  function scrubFraction(e) {
    var r = scrubEl.getBoundingClientRect();
    return Math.min(Math.max((e.clientX - r.left) / r.width, 0), 1);
  }
  scrubEl.addEventListener("pointerdown", function (e) {
    e.preventDefault();
    scrubEl.classList.add("dragging");
    scrubEl.setPointerCapture(e.pointerId);
    fraction = scrubFraction(e);
    paintProgress();
  });
  scrubEl.addEventListener("pointermove", function (e) {
    if (!scrubEl.classList.contains("dragging")) return;
    fraction = scrubFraction(e);
    paintProgress();
  });
  scrubEl.addEventListener("pointerup", function (e) {
    scrubEl.classList.remove("dragging");
    seekTo(scrubFraction(e));
  });
  scrubEl.addEventListener("keydown", function (e) {
    var step = 5 / duration;
    if (e.key === "ArrowLeft") {
      e.preventDefault();
      e.stopPropagation();
      seekTo(fraction - step);
    } else if (e.key === "ArrowRight") {
      e.preventDefault();
      e.stopPropagation();
      seekTo(fraction + step);
    }
  });

  // ---- pomodoro: a real 25:00, ring drains, chip parks at the idle left ----
  var PHASES = [
    { name: "Focus", secs: 25 * 60 },
    { name: "Break", secs: 5 * 60 },
  ];
  var pomo = {
    running: false,
    phase: 0,
    total: PHASES[0].secs,
    remaining: PHASES[0].secs,
    timer: null,
    lastTick: 0,
  };
  var RING_C = 270.18; /* 2 * pi * 43 */
  var CHIP_C = 37.7; /* 2 * pi * 6 */

  var fpClock = document.getElementById("fp-clock");
  var fpPhase = document.getElementById("fp-phase");
  var fpRing = document.getElementById("fp-ringfill");
  var fpToggle = document.getElementById("fp-toggle");
  var fpPlayIco = fpToggle.querySelector(".ico-play");
  var fpPauseIco = fpToggle.querySelector(".ico-pause");
  var chipRing = document.getElementById("tn-chip-ring");
  var chipTime = document.getElementById("tn-chip-time");

  function pomoPaint() {
    var remainingFrac = pomo.remaining / pomo.total;
    fpClock.textContent = fmt(pomo.remaining);
    chipTime.textContent = fmt(pomo.remaining);
    fpRing.style.strokeDashoffset = String(RING_C * (1 - remainingFrac));
    chipRing.style.strokeDashoffset = String(CHIP_C * (1 - remainingFrac));
    fpPhase.textContent = PHASES[pomo.phase].name;
    Array.prototype.forEach.call(document.querySelectorAll(".fp-step em"), function (label, i) {
      label.classList.toggle("on", i === pomo.phase);
    });
  }

  function pomoAdvance() {
    pomo.phase = (pomo.phase + 1) % PHASES.length;
    pomo.total = PHASES[pomo.phase].secs;
    pomo.remaining = pomo.total;
  }

  function pomoTick() {
    var now = performance.now();
    pomo.remaining -= (now - pomo.lastTick) / 1000;
    pomo.lastTick = now;
    if (pomo.remaining <= 0) {
      if (pomo.phase === 0) { rounds += 1; paintRounds(); }
      pomoAdvance();
      if (!autoStart) {
        clearInterval(pomo.timer);
        pomo.timer = null;
        pomo.running = false;
        pomoPaintChrome();
      }
    }
    pomoPaint();
  }

  function pomoPaintChrome() {
    fpPlayIco.style.display = pomo.running ? "none" : "";
    fpPauseIco.style.display = pomo.running ? "" : "none";
    fpToggle.setAttribute("aria-label", pomo.running ? "Pause" : "Start");
    tn.dataset.chip = chipVisible() ? "1" : "0";
    applySize();
  }

  document.getElementById("fp-toggle").addEventListener("click", function () {
    pomo.running = !pomo.running;
    if (pomo.running) {
      pomo.lastTick = performance.now();
      pomo.timer = setInterval(pomoTick, 250);
    } else {
      clearInterval(pomo.timer);
      pomo.timer = null;
    }
    pomoPaintChrome();
  });
  document.getElementById("fp-skip").addEventListener("click", function () {
    pomoAdvance();
    pomo.lastTick = performance.now();
    pomoPaint();
    pomoPaintChrome();
  });
  document.getElementById("fp-reset").addEventListener("click", function () {
    clearInterval(pomo.timer);
    pomo.timer = null;
    pomo.running = false;
    pomo.phase = 0;
    pomo.total = PHASES[0].secs;
    pomo.remaining = pomo.total;
    pomoPaint();
    pomoPaintChrome();
  });

  // ---- notes: a card grows into the editor, back shrinks it ----
  var npRoot = document.getElementById("np");
  var npTitle = document.getElementById("np-title");
  var npScratch = document.getElementById("np-scratch");

  function openNote(card) {
    npTitle.textContent = card.dataset.title;
    npScratch.value = card.dataset.body.replace(/\\n/g, "\n");
    notesOpen = true;
    npRoot.dataset.open = "1";
    applySize();
    npScratch.focus();
  }

  function closeNote() {
    notesOpen = false;
    npRoot.dataset.open = "0";
    applySize();
  }

  Array.prototype.forEach.call(document.querySelectorAll(".np-card"), function (card) {
    card.addEventListener("click", function () { openNote(card); });
  });
  document.getElementById("np-back").addEventListener("click", closeNote);
  npScratch.addEventListener("keydown", function (e) {
    if (e.key === "Escape") { e.stopPropagation(); closeNote(); }
  });

  // ---- focus: durations, auto-start, rounds today ----
  var fpRounds = document.getElementById("fp-rounds");
  var fpAuto = document.getElementById("fp-auto");
  var rounds = 0;
  var autoStart = false;

  function paintRounds() {
    fpRounds.textContent = rounds === 0 ? "No rounds done today"
      : rounds === 1 ? "1 round done today" : rounds + " rounds done today";
  }

  Array.prototype.forEach.call(document.querySelectorAll(".fp-step"), function (step) {
    var idx = Number(step.dataset.phase);
    var value = step.querySelector("b");
    var buttons = step.querySelectorAll(".tn-btn");
    function adjust(delta) {
      var mins = Math.min(Math.max(PHASES[idx].secs / 60 + delta, 1), idx === 0 ? 90 : 60);
      PHASES[idx].secs = mins * 60;
      value.textContent = String(mins);
      if (!pomo.running && pomo.phase === idx) {
        pomo.total = pomo.remaining = PHASES[idx].secs;
        pomoPaint();
      }
    }
    buttons[0].addEventListener("click", function () { adjust(-1); });
    buttons[1].addEventListener("click", function () { adjust(1); });
  });

  fpAuto.addEventListener("click", function () {
    autoStart = !autoStart;
    fpAuto.setAttribute("aria-pressed", autoStart ? "true" : "false");
  });

  // ---- init ----
  panelEl.inert = true;
  tn.dataset.playing = "0";
  tn.dataset.chip = "0";
  paintProgress();
  pomoPaint();
  setPane("music");
  applySize();
  window.addEventListener("resize", applySize);
})();
