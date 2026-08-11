/* Global rick roll counter.
   Shared count lives at abacus.jasoncameron.dev (keyless, free). The page talks to
   that origin for this counter only: one read on load, one hit on the first play of
   the visit, and a 12 second read poll while the tab is visible. Every failure is
   silent: the stat stays hidden until a read succeeds and freezes if one fails. */
(function () {
  "use strict";

  var API = "https://abacus.jasoncameron.dev";
  var KEY_PATH = "/topnotch-site/rickrolls";
  var POLL_MS = 12000;
  var MIN_DIGITS = 4;
  var SESSION_KEY = "tn-rickrolled";

  var stat = document.getElementById("rr-stat");
  var digitsEl = document.getElementById("rr-digits");
  var playBtn = document.getElementById("mp-play");
  if (!stat || !digitsEl) return;

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)");
  var shown = false;
  var current = null;

  function buildCell() {
    var cell = document.createElement("span");
    cell.className = "rr-cell";
    var col = document.createElement("span");
    col.className = "rr-col";
    for (var d = 0; d <= 9; d++) {
      var s = document.createElement("span");
      s.textContent = String(d);
      col.appendChild(s);
    }
    cell.appendChild(col);
    return cell;
  }

  function render(value, animate) {
    var str = String(value);
    while (str.length < MIN_DIGITS) str = "0" + str;
    while (digitsEl.children.length < str.length) {
      digitsEl.insertBefore(buildCell(), digitsEl.firstChild);
    }
    while (digitsEl.children.length > str.length) {
      digitsEl.removeChild(digitsEl.firstChild);
    }
    var snap = !animate || reduced.matches;
    for (var i = 0; i < str.length; i++) {
      var col = digitsEl.children[i].firstChild;
      /* the column is 10 cells tall, so one cell is 10% of its own height */
      col.style.transition = snap ? "none" : "";
      col.style.transform = "translateY(-" + Number(str[i]) * 10 + "%)";
    }
    current = value;
    stat.setAttribute("aria-label", value + " visitors rick rolled");
    if (!shown) {
      shown = true;
      stat.hidden = false;
    }
  }

  function accept(data, animate) {
    var v = data && data.value;
    if (typeof v !== "number" || !isFinite(v) || v < 0) return;
    v = Math.floor(v);
    if (shown && v === current) return;
    render(v, animate && shown);
  }

  function fetchCount(path) {
    return fetch(API + path + KEY_PATH).then(function (r) {
      /* a key nobody has hit yet reads back 404; that is a real zero */
      if (r.status === 404) return { value: 0 };
      if (!r.ok) throw new Error(String(r.status));
      return r.json();
    });
  }

  function silent() { /* hidden or frozen, never an error in the UI */ }

  fetchCount("/get").then(function (d) { accept(d, false); }).catch(silent);

  /* ---- first play of the visit increments the shared counter ---- */

  var counted = false;
  try {
    counted = sessionStorage.getItem(SESSION_KEY) === "1";
  } catch (err) { /* storage blocked; the in-memory flag still guards this page */ }

  if (playBtn) {
    playBtn.addEventListener("click", function () {
      if (counted) return; /* pause and replay spam never inflates the count */
      counted = true;
      try { sessionStorage.setItem(SESSION_KEY, "1"); } catch (err) { /* same guard */ }
      fetchCount("/hit").then(function (d) { accept(d, true); }).catch(silent);
    });
  }

  /* ---- live poll, only while the tab is visible ---- */

  var timer = null;

  function poll() {
    fetchCount("/get").then(function (d) { accept(d, true); }).catch(silent);
  }

  function setPolling(on) {
    if (on && !timer) timer = setInterval(poll, POLL_MS);
    else if (!on && timer) {
      clearInterval(timer);
      timer = null;
    }
  }

  document.addEventListener("visibilitychange", function () {
    setPolling(!document.hidden);
  });
  setPolling(!document.hidden);
})();
