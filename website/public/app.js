"use strict";

/* ---------- i18n ---------- */
// Chinese lives in index.html; English replaces it when ?lang=en. Keys marked html contain trusted markup.
const EN = {
  skip: "Skip to content",
  navLabel: "Main navigation",
  navResolution: "Resolution",
  navBrightness: "Brightness",
  navKeys: "Keys",
  navInstall: "Install",
  download: "Download",
  eyebrowFree: "Free & open source",
  heroTitle: { html: "Crisp, native<br>external displays." },
  heroLede: "Pick the right HiDPI resolution for every external display, and adjust its brightness, contrast and volume directly. A quiet native menu bar utility that never modifies the system and never goes online.",
  downloadVersion: "Download v0.3.1",
  viewSource: "View source",
  heroFine: "Notarized by Apple · 2.2 MB · MIT license",
  tagSoft: "1× scaled",
  compareAria: "Drag to compare ordinary scaling with HiDPI",
  compareCaption: "Drag the divider: the same 2560 × 1440 screen, ordinary scaling vs HiDPI.",
  shotMainAlt: "PixelFit main window: display arrangement, HiDPI resolution, refresh rate and display controls",
  shotMenuAlt: "PixelFit menu bar panel: resolution, brightness and volume for each display",
  resTitle: { html: "Use what macOS really offers.<br>Add what's missing." },
  resLede: "PixelFit lists only the HiDPI modes macOS actually provides, recommends sizes that match each screen's shape, and marks every size as pixel-matched, integer-scaled or scaled.",
  resPoint1: { html: "<strong>15-second confirmation.</strong> A prompt appears on the changed display; without “Keep”, the previous mode comes back, so a wrong pick never leaves you stuck." },
  resPoint2: { html: "<strong>Resolution presets.</strong> Save a multi-display setup and switch with ⌃⌘1–9. Matched by model and serial, so they survive reconnecting." },
  resPoint3: { html: "<strong>More HiDPI.</strong> When a size is missing, add a scaling configuration with your explicit approval. It writes only to <code>/Library</code>: no <code>/System</code>, no EDID edits, no SIP changes." },
  chipExact: "Pixel matched",
  chipScaled: "Scaled",
  current: "Current",
  keepQuestion: "Keep this resolution?",
  brTitle: { html: "Control the monitor itself.<br>Even the stubborn ones." },
  brLede: "PixelFit writes brightness, contrast and volume to the monitor over DDC/CI, just like its own buttons. Each display gets a brightness mode:",
  modeHardware: "Hardware (DDC)",
  modeHardwareNote: "Backlight only.",
  modeCombined: "Hardware + Software",
  modeCombinedNote: "Once the backlight bottoms out, software keeps dimming: darker than the monitor allows.",
  modeSoftware: "Software Only",
  modeSoftwareNote: "For displays that lack DDC, or store DDC brightness without applying it.",
  brRobust: "Software dimming comes back by itself after macOS resets colors (resolution changes, wake, another color app quitting). If an app like f.lux keeps rewriting colors, PixelFit switches to an overlay that screenshots don't capture.",
  modeGroup: "Brightness mode",
  brightness: "Brightness",
  meterBacklight: "Backlight DDC",
  meterSoftware: "Software",
  unchanged: "untouched",
  keysTitle: { html: "Your brightness keys,<br>finally for external displays." },
  keysLede: "Brightness keys adjust the display under the pointer. Volume keys take over only while sound plays through a display, and go to macOS otherwise. Hold ⌥⇧ for fine steps; a HUD appears on that display.",
  keysNote: "Requires permission in System Settings › Privacy & Security › Accessibility. Built-in and Apple displays keep using system brightness.",
  keyDown: "Brightness down",
  keyUp: "Brightness up",
  keyFine: "⌥⇧ fine steps",
  fine: "Fine",
  keysTry: "Try the keys",
  trustTitle: "Quiet, verifiable, reversible.",
  fact1Title: "Free & open source",
  fact1: "MIT licensed. Source and build steps on GitHub.",
  fact2Title: "Notarized",
  fact2: "Developer ID signed with hardened runtime. Gatekeeper opens it; no security settings to turn off.",
  fact3Title: "Offline",
  fact3: "No account, no analytics, no network requests. Settings stay on your Mac.",
  fact4Title: "Reversible",
  fact4: "Resolutions revert in 15 seconds unless kept; dimming is undone on quit; scaling configurations restore the exact original files after approval.",
  installTitle: "Three steps.",
  step1: { html: "Download <code>PixelFit-v0.3.1-macos-arm64.zip</code> and unzip it." },
  step2: "Drag PixelFit.app into Applications. It appears in the menu bar.",
  step3: "For brightness keys, click “Grant Access” in Settings › Keyboard.",
  checksum: "SHA-256 checksums",
  allReleases: "All releases",
  reqTitle: "Requirements",
  req: "An Apple Silicon Mac with macOS 14 Sonoma or later. DDC control needs DDC/CI enabled on the monitor; some HDMI ports, adapters and docks don't pass DDC through.",
  verifiedTitle: "Tested on real hardware",
  thDisplay: "Display",
  thLink: "Link",
  thResult: "Result",
  tdSculptor: "1600×1000 HiDPI · DDC brightness / combined dimming",
  tdRV: "DDC reads and writes, but ignores brightness → Software Only",
  matrix: "Full compatibility record and untested cases",
  faqTitle: "FAQ",
  q1: "Can I use it alongside MonitorControl, BetterDisplay or Lunar?",
  a1: "Better not. They also intercept brightness keys and talk DDC, so running both makes them fight over keys and interrupt each other. PixelFit tells you when one of them is running.",
  q2: "The picture doesn't change when I drag Brightness?",
  a2: "Some monitors store DDC brightness without applying it. Set that display's Brightness Control to Software Only in the main window.",
  q3: "Does it support Intel Macs?",
  a3: "Only Apple Silicon builds are released and tested for now.",
  q4: "Does it update automatically?",
  a4: "No. PixelFit never goes online. New versions appear on GitHub Releases and on this page.",
  q5: "How do I uninstall completely?",
  a5: { html: "If you used “More HiDPI”, first click “Restore Original Configuration” under Advanced in the main window, then delete the app. Deleting the app does not undo system scaling configurations; see the <a href=\"https://github.com/rockythink/PixelFit#恢复配置与卸载\">README</a>." },
  q6: "Why PixelFit? What happened to HiDPIBuddy?",
  a6: "It's the same tool, renamed. To keep old presets and restore records working, the bundle ID and data folder still use HiDPIBuddy.",
  footerLine: "External displays, treated as first-class.",
  footerNav: "Footer navigation",
  feedback: "Report an issue",
  otherWorks: "MORE FROM ELAZER",
};

const lang = new URLSearchParams(location.search).get("lang") === "en" ? "en" : "zh";
const t = (key, fallback) => (lang === "en" && EN[key] !== undefined ? EN[key] : fallback);

function applyLanguage() {
  if (lang !== "en") return;
  document.documentElement.lang = "en";
  document.title = "PixelFit — Crisp, native external displays on Mac";
  const description = document.querySelector('meta[name="description"]');
  if (description) description.content = "PixelFit is a free, open-source macOS menu bar utility: the right HiDPI resolution for external displays, DDC/CI brightness, contrast and volume, and software dimming for displays that need it.";
  document.querySelectorAll("[data-i18n]").forEach((el) => {
    const value = EN[el.dataset.i18n];
    if (value === undefined) return;
    if (typeof value === "object") el.innerHTML = value.html;
    else el.textContent = value;
  });
  document.querySelectorAll("[data-i18n-aria]").forEach((el) => {
    const value = EN[el.dataset.i18nAria];
    if (typeof value === "string") el.setAttribute("aria-label", value);
  });
  document.querySelectorAll("[data-i18n-alt]").forEach((el) => {
    const value = EN[el.dataset.i18nAlt];
    if (typeof value === "string") el.alt = value;
  });
  const toggle = document.querySelector("[data-lang-toggle]");
  if (toggle) { toggle.href = "/"; toggle.textContent = "中文"; toggle.hreflang = "zh-CN"; }
  document.querySelectorAll("[data-lang-link]").forEach((a) => { a.href = "/?lang=en"; });
}

/* ---------- Sharpness comparator ---------- */
function drawScene(ctx, w, h) {
  const g = ctx.createLinearGradient(0, 0, w, h);
  g.addColorStop(0, "#14204a");
  g.addColorStop(1, "#0b1330");
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, w, h);
  const pad = w * 0.07;
  // window chrome
  ctx.fillStyle = "rgba(255,255,255,0.06)";
  roundRect(ctx, pad * 0.6, pad * 0.6, w - pad * 1.2, h - pad * 1.2, w * 0.02);
  ctx.fill();
  ["#ff5f57", "#febc2e", "#28c840"].forEach((c, i) => {
    ctx.fillStyle = c;
    ctx.beginPath();
    ctx.arc(pad + i * w * 0.028, pad * 1.05, w * 0.008, 0, Math.PI * 2);
    ctx.fill();
  });
  const sans = '-apple-system, "SF Pro Display", "PingFang SC", "Helvetica Neue", sans-serif';
  const mono = '"Plex Mono", ui-monospace, Menlo, monospace';
  ctx.fillStyle = "#eef2ff";
  ctx.textBaseline = "alphabetic";
  ctx.font = `700 ${w * 0.072}px ${sans}`;
  ctx.fillText(lang === "en" ? "Sharp text" : "清晰原生的文字", pad, h * 0.33);
  ctx.fillStyle = "#8fb6ff";
  ctx.font = `500 ${w * 0.03}px ${mono}`;
  ctx.fillText("2560 × 1440 · HiDPI · 60Hz", pad, h * 0.43);
  ctx.fillStyle = "rgba(233,237,249,0.78)";
  ctx.font = `400 ${w * 0.026}px ${sans}`;
  const lines = lang === "en"
    ? ["Thin strokes, small type and icon edges", "stay sharp instead of soft and smeared.", "The quick brown fox jumps over the lazy dog."]
    : ["细笔画、小字号和图标边缘都保持锐利，", "不再发虚、发糊，长时间阅读也不累。", "永和九年，岁在癸丑，暮春之初。The quick brown fox."];
  lines.forEach((line, i) => ctx.fillText(line, pad, h * (0.56 + i * 0.075)));
  // icon row
  for (let i = 0; i < 5; i++) {
    const x = pad + i * w * 0.085, y = h * 0.8, s = w * 0.055;
    ctx.fillStyle = ["#5b8cff", "#34c759", "#ff9f0a", "#bf5af2", "#ff375f"][i];
    roundRect(ctx, x, y, s, s, s * 0.24);
    ctx.fill();
    ctx.strokeStyle = "rgba(255,255,255,0.9)";
    ctx.lineWidth = w * 0.0035;
    ctx.beginPath();
    ctx.arc(x + s / 2, y + s / 2, s * 0.2, 0, Math.PI * 2);
    ctx.stroke();
  }
}

function roundRect(ctx, x, y, w, h, r) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function setupCompare() {
  const root = document.querySelector("[data-compare]");
  if (!root) return;
  const frame = root.querySelector(".compare-frame");
  const soft = root.querySelector(".compare-soft");
  const sharp = root.querySelector(".compare-sharp");
  const handle = root.querySelector(".compare-handle");
  let split = 50;

  const render = () => {
    const { width, height } = frame.getBoundingClientRect();
    if (!width) return;
    const dpr = Math.min(window.devicePixelRatio || 1, 3);
    // A non-HiDPI scaled mode renders fewer pixels and stretches them: draw small, let the browser upscale.
    const softScale = 0.42;
    soft.width = Math.round(width * softScale);
    soft.height = Math.round(height * softScale);
    const s = soft.getContext("2d");
    s.setTransform(softScale, 0, 0, softScale, 0, 0);
    drawScene(s, width, height);
    sharp.width = Math.round(width * dpr);
    sharp.height = Math.round(height * dpr);
    const c = sharp.getContext("2d");
    c.setTransform(dpr, 0, 0, dpr, 0, 0);
    drawScene(c, width, height);
  };

  const setSplit = (value) => {
    split = Math.max(0, Math.min(100, value));
    root.style.setProperty("--split", `${split}%`);
    handle.setAttribute("aria-valuenow", String(Math.round(split)));
  };
  const fromPointer = (event) => {
    const rect = frame.getBoundingClientRect();
    setSplit(((event.clientX - rect.left) / rect.width) * 100);
  };
  let dragging = false;
  frame.addEventListener("pointerdown", (e) => { dragging = true; frame.setPointerCapture(e.pointerId); fromPointer(e); });
  frame.addEventListener("pointermove", (e) => { if (dragging) fromPointer(e); });
  frame.addEventListener("pointerup", () => { dragging = false; });
  frame.addEventListener("pointercancel", () => { dragging = false; });
  handle.addEventListener("keydown", (e) => {
    const step = e.shiftKey ? 10 : 2;
    if (e.key === "ArrowLeft") { setSplit(split - step); e.preventDefault(); }
    if (e.key === "ArrowRight") { setSplit(split + step); e.preventDefault(); }
    if (e.key === "Home") { setSplit(0); e.preventDefault(); }
    if (e.key === "End") { setSplit(100); e.preventDefault(); }
  });

  new ResizeObserver(render).observe(frame);
  (document.fonts ? document.fonts.ready : Promise.resolve()).then(render);
  setSplit(50);

  // One gentle sweep on load hints that the divider moves.
  if (!matchMedia("(prefers-reduced-motion: reduce)").matches) {
    const start = performance.now();
    const sweep = (now) => {
      if (dragging) return;
      const p = Math.min((now - start) / 2200, 1);
      setSplit(50 + Math.sin(p * Math.PI * 2) * 22 * (1 - p));
      if (p < 1) requestAnimationFrame(sweep);
    };
    setTimeout(() => requestAnimationFrame(sweep), 900);
  }
}

/* ---------- Brightness modes (same split as the app's BrightnessSplit) ---------- */
function parts(level, mode) {
  if (mode === "hardware") return { ddc: level, sw: 1 };
  if (mode === "software") return { ddc: null, sw: level };
  return level >= 0.5 ? { ddc: (level - 0.5) / 0.5, sw: 1 } : { ddc: 0, sw: level / 0.5 };
}

function setupDimmer() {
  const root = document.querySelector("[data-dimmer]");
  if (!root) return;
  const range = root.querySelector("[data-level]");
  const out = root.querySelector("[data-level-out]");
  const backlight = root.querySelector(".dim-backlight");
  const gamma = root.querySelector(".dim-gamma");
  const meter = (k) => root.querySelector(`[data-meter="${k}"]`);
  const meterOut = (k) => root.querySelector(`[data-meter-out="${k}"]`);
  let mode = "combined";

  const update = () => {
    const level = Number(range.value) / 100;
    const p = parts(level, mode);
    // Backlight cannot go fully dark: model a monitor minimum of 30% luminance.
    const backlightLum = p.ddc === null ? 1 : 0.3 + 0.7 * p.ddc;
    const gammaMul = 0.15 + 0.85 * p.sw;
    backlight.style.opacity = String(1 - backlightLum);
    gamma.style.opacity = String(1 - gammaMul);
    out.textContent = `${Math.round(level * 100)}%`;
    range.style.setProperty("--fill", `${level * 100}%`);
    meter("ddc").style.width = p.ddc === null ? "100%" : `${p.ddc * 100}%`;
    meter("ddc").style.opacity = p.ddc === null ? "0.25" : "1";
    meterOut("ddc").textContent = p.ddc === null ? t("unchanged", "不变") : `${Math.round(p.ddc * 100)}%`;
    meter("sw").style.width = `${p.sw * 100}%`;
    meterOut("sw").textContent = `${Math.round(p.sw * 100)}%`;
  };

  root.querySelectorAll("[data-mode]").forEach((button) => {
    button.addEventListener("click", () => {
      mode = button.dataset.mode;
      root.querySelectorAll("[data-mode]").forEach((b) => b.setAttribute("aria-checked", String(b === button)));
      update();
    });
  });
  range.addEventListener("input", update);
  update();
}

/* ---------- Keys + HUD ---------- */
function setupKeys() {
  const root = document.querySelector("[data-keys]");
  if (!root) return;
  const fill = root.querySelector("[data-hud-fill]");
  const out = root.querySelector("[data-hud-out]");
  const hud = root.querySelector(".hud");
  const fineKey = root.querySelector("[data-fine]");
  let value = 0.75;
  let fine = false;
  const render = () => {
    fill.style.width = `${value * 100}%`;
    out.textContent = String(Math.round(value * 100));
  };
  const step = (dir) => {
    const steps = fine ? 64 : 16;
    value = Math.max(0, Math.min(1, (Math.round(value * steps) + dir) / steps));
    render();
    hud.classList.remove("pulse");
    void hud.offsetWidth;
    hud.classList.add("pulse");
    setTimeout(() => hud.classList.remove("pulse"), 180);
  };
  root.querySelectorAll("[data-step]").forEach((key) => key.addEventListener("click", () => step(Number(key.dataset.step))));
  fineKey.addEventListener("click", () => {
    fine = !fine;
    fineKey.setAttribute("aria-pressed", String(fine));
  });
  render();
}

/* ---------- Section reveal ---------- */
function setupReveal() {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches || !("IntersectionObserver" in window)) return;
  const targets = document.querySelectorAll(".band .split > *, .facts article, .band h2.center, #faq details");
  const io = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) { entry.target.classList.add("in"); io.unobserve(entry.target); }
    });
  }, { rootMargin: "0px 0px -10% 0px" });
  targets.forEach((el, i) => {
    el.classList.add("reveal");
    el.style.transitionDelay = `${(i % 4) * 60}ms`;
    io.observe(el);
  });
}

applyLanguage();
setupCompare();
setupDimmer();
setupKeys();
setupReveal();
