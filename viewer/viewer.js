// TunICA viewer.
// Copyright (c) 2026 Arelius-D | AGPL-3.0-only
import mermaid from "./vendor/mermaid/mermaid.esm.min.mjs";
import elk from "./vendor/layout-elk/mermaid-layout-elk.esm.min.mjs";

const STORED_THEME = "tunica-theme";
const STORED_SCALE = "tunica-scale";
const STORED_VIEW = "tunica-index-view";

const root = document.documentElement;
const el = (id) => document.getElementById(id);

function remember(key, value) {
  try {
    localStorage.setItem(key, value);
  } catch (ignored) {
  }
}

function recall(key) {
  try {
    return localStorage.getItem(key);
  } catch (ignored) {
    return null;
  }
}

/* ── theme ────────────────────────────────────────── */
function applyTheme(name) {
  root.classList.add("is-theming");
  window.setTimeout(() => root.classList.remove("is-theming"), 450);
  root.setAttribute("data-theme", name);
  remember(STORED_THEME, name);
}

function currentTheme() {
  const set = root.getAttribute("data-theme");
  if (set) return set;
  return window.matchMedia("(prefers-color-scheme: light)").matches ? "paper" : "deep-field";
}

function initTheme() {
  el("theme-toggle").addEventListener("click", () => {
    applyTheme(currentTheme() === "paper" ? "deep-field" : "paper");
  });
}

/* ── the map surface ──────────────────────────────── */
const view = { scale: 1, x: 0, y: 0 };
const MIN_SCALE = 0.2;
const MAX_SCALE = 6;

function applyView() {
  root.style.setProperty("--scale", String(view.scale));
  root.style.setProperty("--pan-x", `${view.x}px`);
  root.style.setProperty("--pan-y", `${view.y}px`);
  el("zoom-reset").textContent = `${Math.round(view.scale * 100)}%`;
  remember(STORED_SCALE, String(view.scale));
}

function zoomAt(factor, originX, originY) {
  const next = Math.min(MAX_SCALE, Math.max(MIN_SCALE, view.scale * factor));
  const ratio = next / view.scale;
  view.x = originX - (originX - view.x) * ratio;
  view.y = originY - (originY - view.y) * ratio;
  view.scale = Math.round(next * 100) / 100;
  applyView();
}

function resetView() {
  view.scale = 1;
  view.x = 0;
  view.y = 0;
  applyView();
}

function initSurface() {
  const frame = el("frame");
  const stored = Number.parseFloat(recall(STORED_SCALE));
  view.scale = Number.isFinite(stored) ? Math.min(MAX_SCALE, Math.max(MIN_SCALE, stored)) : 1;
  applyView();

  el("zoom-reset").addEventListener("click", resetView);
  frame.addEventListener("dblclick", resetView);

  frame.addEventListener(
    "wheel",
    (event) => {
      event.preventDefault();
      const box = frame.getBoundingClientRect();
      zoomAt(
        event.deltaY < 0 ? 1.12 : 1 / 1.12,
        event.clientX - (box.left + box.width / 2),
        event.clientY - (box.top + box.height / 2),
      );
    },
    { passive: false },
  );

  let dragging = null;
  frame.addEventListener("pointerdown", (event) => {
    if (event.button !== 0 || event.target.closest("a, button")) return;
    dragging = { id: event.pointerId, x: event.clientX - view.x, y: event.clientY - view.y };
    frame.setPointerCapture(event.pointerId);
    frame.classList.add("is-panning");
  });

  frame.addEventListener("pointermove", (event) => {
    if (!dragging || dragging.id !== event.pointerId) return;
    view.x = event.clientX - dragging.x;
    view.y = event.clientY - dragging.y;
    applyView();
  });

  for (const done of ["pointerup", "pointercancel"]) {
    frame.addEventListener(done, (event) => {
      if (!dragging || dragging.id !== event.pointerId) return;
      dragging = null;
      frame.classList.remove("is-panning");
    });
  }
}

function initZen() {
  const button = el("zen");
  button.addEventListener("click", async () => {
    try {
      if (document.fullscreenElement) await document.exitFullscreen();
      else await document.documentElement.requestFullscreen();
    } catch (ignored) {
      button.title = "Fullscreen refused by this browser";
    }
  });

  document.addEventListener("fullscreenchange", () => {
    const on = Boolean(document.fullscreenElement);
    document.body.classList.toggle("focus-mode", on);
    button.setAttribute("aria-pressed", String(on));
    button.title = on ? "Leave focus mode" : "Focus mode (fullscreen)";
    button.setAttribute("aria-label", button.title);
  });
}

/* ── links ────────────────────────────────────────── */
let currentRepo = "";
let canGenerate = false;
let underService = false;
let runner = null;
let prefill = null;

function linkTarget(anchor) {
  const href = anchor.getAttribute("href") || anchor.getAttribute("xlink:href") || "";
  const written = /^(?:\.\/)?([A-Za-z0-9_.-]+)\.md$/.exec(href);
  if (written) return written[1];
  const rewritten = /[?&]name=([A-Za-z0-9_.%-]+)/.exec(href);
  return rewritten ? decodeURIComponent(rewritten[1]) : null;
}

function relink(repo) {
  for (const anchor of el("diagram").querySelectorAll("a")) {
    const name = linkTarget(anchor);
    if (!name) continue;
    const url = `?repo=${encodeURIComponent(repo)}&name=${encodeURIComponent(name)}`;
    anchor.setAttribute("href", url);
    anchor.setAttribute("xlink:href", url);
    anchor.removeAttribute("target");
  }
}

function initDiagramLinks() {
  el("diagram").addEventListener("click", (event) => {
    const anchor = event.target.closest("a");
    if (!anchor) return;
    const name = linkTarget(anchor);
    if (!name) return;
    event.preventDefault();
    event.stopPropagation();
    go(currentRepo, name);
  }, true);
}

function go(repo, name) {
  history.pushState({ repo, name }, "", `?repo=${encodeURIComponent(repo)}&name=${encodeURIComponent(name)}`);
  showMap(repo, name);
}

/* ── where you are ────────────────────────────────── */
function crumbs(repo, name) {
  const trail = [{ label: "All maps", href: "./" }];
  if (repo) trail.push({ label: repo, href: `?repo=${encodeURIComponent(repo)}&name=overview` });
  if (repo && name !== "overview") trail.push({ label: name, href: null });

  const nav = el("crumbs");
  nav.replaceChildren();
  trail.forEach((step, index) => {
    if (index) {
      const sep = document.createElement("span");
      sep.className = "crumbs__sep";
      sep.textContent = "/";
      sep.setAttribute("aria-hidden", "true");
      nav.append(sep);
    }
    const last = index === trail.length - 1;
    const node = document.createElement(step.href && !last ? "a" : "span");
    node.className = last ? "crumbs__here" : "crumbs__step";
    node.textContent = step.label;
    if (step.href && !last) node.href = step.href;
    if (step.href && !last && step.href.startsWith("?repo=")) {
      node.addEventListener("click", (event) => {
        event.preventDefault();
        go(repo, "overview");
      });
    }
    if (last) node.setAttribute("aria-current", "page");
    nav.append(node);
  });
}

/* ── the run log ──────────────────────────────────── */
const RUN_RECORD = "tunica-run";

function keepRun(record) {
  try {
    sessionStorage.setItem(RUN_RECORD, JSON.stringify(record));
  } catch (ignored) {
  }
}

function lastRun() {
  try {
    return JSON.parse(sessionStorage.getItem(RUN_RECORD) || "null");
  } catch (ignored) {
    return null;
  }
}

const term = {
  running: false,
  record: { repo: "", title: "", log: "", failed: false },

  set(state) {
    const panel = el("term");
    panel.classList.toggle("term--open", state !== "closed");
    panel.classList.toggle("term--max", state === "max");
    el("term-toggle").setAttribute("aria-expanded", String(state !== "closed"));
    el("term-toggle").classList.toggle("term-toggle--busy", this.running && state === "closed");
    panel.classList.toggle("term--busy", this.running);
    this.state = state;
  },

  toggle() {
    this.set(this.state === "closed" ? "open" : "closed");
  },

  title(text, failed) {
    const title = el("term-title");
    title.textContent = text;
    title.classList.toggle("term__title--failed", Boolean(failed));
    this.record.title = text;
    this.record.failed = Boolean(failed);
    keepRun(this.record);
  },

  write(text) {
    const log = el("term-log");
    log.textContent = text;
    log.scrollTop = log.scrollHeight;
    this.record.log = text;
    keepRun(this.record);
  },

  recall() {
    const record = lastRun();
    if (!record || !record.log) return null;
    this.record = record;
    el("term-title").textContent = record.title || "";
    el("term-title").classList.toggle("term__title--failed", Boolean(record.failed));
    const log = el("term-log");
    log.textContent = record.log;
    log.scrollTop = log.scrollHeight;
    return record;
  },

  busy(on) {
    this.running = on;
    this.set(this.state);
  },

  done() {
    const toggle = el("term-toggle");
    toggle.classList.remove("term-toggle--done");
    void toggle.offsetWidth;
    toggle.classList.add("term-toggle--done");
  },
};

function initTerminal() {
  term.recall();
  term.set("closed");
  el("term-toggle").addEventListener("click", () => term.toggle());
  el("term-close").addEventListener("click", () => term.set("closed"));
  el("term-min").addEventListener("click", () => term.set("closed"));
  el("term-max").addEventListener("click", () => term.set(term.state === "max" ? "open" : "max"));
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && term.state !== "closed") term.set("closed");
  });
}

/* ── the stored maps ──────────────────────────────── */
async function initMapper() {
  let allowed = false;
  try {
    allowed = (await (await fetch("api/config")).json()).generate === true;
  } catch (ignored) {
    allowed = false;
  }
  if (!allowed) return;
  canGenerate = true;

  const form = el("mapper");
  const head = el("stored-head");
  const opener = el("mapper-open");
  opener.hidden = false;

  function reveal(open) {
    head.dataset.mapper = open ? "open" : "shut";
    opener.setAttribute("aria-expanded", String(open));
    opener.title = open ? "Cancel" : "Map a repository";
    opener.setAttribute("aria-label", opener.title);
    if (open) el("target").focus();
  }
  reveal(false);

  prefill = (name) => {
    reveal(true);
    el("target").value = name;
    el("target").select();
  };

  opener.addEventListener("click", () => reveal(head.dataset.mapper !== "open"));
  form.addEventListener("keydown", (event) => {
    if (event.key === "Escape") reveal(false);
  });

  function failed(message) {
    term.busy(false);
    term.set("open");
    term.title(message, true);
    el("target").disabled = false;
  }

  function followRun(repo) {
    term.busy(true);
    el("target").disabled = true;

    const poll = window.setInterval(async () => {
      let state;
      try {
        state = await (await fetch(`api/status?repo=${encodeURIComponent(repo)}`)).json();
      } catch (ignored) {
        return;
      }
      if (state.lines && state.lines.length) term.write(state.lines.join("\n"));

      if (state.running) return;

      window.clearInterval(poll);
      term.busy(false);
      el("target").disabled = false;

      if (!state.ready) {
        failed(`${repo} stopped without producing a map.`);
        return;
      }
      term.title(`${repo} mapped`);
      term.done();
      await refreshIndex();
      el("target").value = "";
    }, 2000);
  }

  runner = async function remake(target, depth, repo) {
    if (term.running) {
      term.set("open");
      return;
    }
    term.set("open");
    term.record.repo = repo;
    term.title(`Remaking ${repo}`);
    term.write("starting…");
    try {
      const response = await fetch("api/map", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target, depth, replace: true }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || `refused (${response.status})`);
    } catch (error) {
      failed(String(error.message || error));
      return;
    }
    followRun(repo);
  };

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const target = el("target").value.trim();
    if (!target) return;
    if (term.running) {
      term.set("open");
      return;
    }

    el("target").disabled = true;
    term.busy(true);
    term.set("open");
    term.record.repo = "";
    term.title(`Mapping ${target}`);
    term.write("starting…");

    let repo;
    try {
      const response = await fetch("api/map", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ target, depth: el("deep").checked ? 2 : 1 }),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || `refused (${response.status})`);
      repo = body.repo;
    } catch (error) {
      failed(String(error.message || error));
      return;
    }

    term.record.repo = repo;
    reveal(false);
    followRun(repo);
  });

  const record = term.recall();
  if (!record || !record.repo) return;
  try {
    const state = await (await fetch(`api/status?repo=${encodeURIComponent(record.repo)}`)).json();
    if (state.running) followRun(record.repo);
  } catch (ignored) {
  }
}

const when = (seconds) =>
  new Date(seconds * 1000).toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" });

function cardOf(map) {
  const item = document.createElement("article");
  item.className = "card";

  const link = document.createElement("a");
  link.className = "card__link";
  link.href = `?repo=${encodeURIComponent(map.name)}&name=overview`;

  const name = document.createElement("span");
  name.className = "card__name";
  name.textContent = map.name;

  const facts = document.createElement("span");
  facts.className = "card__facts";
  facts.textContent = map.components
    ? `${map.components} component ${map.components === 1 ? "map" : "maps"} · ${when(map.updated)}`
    : `system map only · ${when(map.updated)}`;

  if (map.cover) {
    const cover = document.createElement("img");
    cover.className = "card__cover";
    cover.src = `out/${encodeURIComponent(map.name)}/${map.cover}`;
    cover.alt = "";
    cover.loading = "lazy";
    link.append(cover);
  }
  link.append(name, facts);

  const actions = document.createElement("span");
  actions.className = "card__actions";
  if (canGenerate) actions.append(refreshButton(map));
  actions.append(removeButton(map.name, item));
  item.append(link, actions);
  return item;
}

async function storedMaps() {
  try {
    return (await (await fetch("api/maps")).json()).maps || [];
  } catch (ignored) {
    return [];
  }
}

function paintIndex(maps) {
  el("index").replaceChildren(...maps.map(cardOf));
  el("stored-title").textContent = `Stored maps (${maps.length})`;
  el("stored").hidden = false;
  initArrangement();
}

async function renderIndex(status) {
  const maps = await storedMaps();
  if (!maps.length) {
    el("stored-title").textContent = "Stored maps (0)";
    el("stored").hidden = false;
    status.textContent = "No maps stored yet. Map a repository, or run tunica on the host.";
    return;
  }
  paintIndex(maps);
  status.hidden = true;
}

async function refreshIndex() {
  const maps = await storedMaps();
  if (maps.length) paintIndex(maps);
}

function refreshButton(map) {
  const known = Boolean(map.source);
  const deep = String(map.depth) === "2" || map.components > 0;
  const button = document.createElement("button");
  button.type = "button";
  button.className = "card__refresh";
  button.title = !known
    ? `Where the ${map.name} map came from was not recorded. Press to say.`
    : deep
      ? `Remake the ${map.name} map, every component`
      : `Remake the ${map.name} map. Hold to map every component.`;
  button.setAttribute("aria-label", `Remake the ${map.name} map`);
  button.innerHTML = `<svg class="control__glyph" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="M20 11a8 8 0 1 0-.6 4M20 4v5h-5"/></svg>`;

  let held = null;
  let fired = false;

  const release = () => {
    window.clearTimeout(held);
    held = null;
    button.classList.remove("card__refresh--holding");
  };

  button.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    event.preventDefault();
    event.stopPropagation();
    if (!known) return;
    if (event.pointerId !== undefined) button.setPointerCapture?.(event.pointerId);
    fired = false;
    button.classList.add("card__refresh--holding");
    held = window.setTimeout(() => {
      fired = true;
      release();
      runner?.(map.source, 2, map.name);
    }, holdDuration());
  });

  for (const ending of ["pointerup", "pointercancel"]) {
    button.addEventListener(ending, () => {
      const wasHolding = held !== null;
      release();
      if (wasHolding && !fired) runner?.(map.source, deep ? 2 : 1, map.name);
    });
  }

  button.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
    if (!known) prefill?.(map.name);
  });

  return button;
}

function holdDuration() {
  const declared = getComputedStyle(document.documentElement).getPropertyValue("--motion-hold").trim();
  const seconds = parseFloat(declared);
  return Number.isFinite(seconds) ? seconds * 1000 : 900;
}

function removeButton(name, item) {
  const button = document.createElement("button");
  button.type = "button";
  button.className = "card__remove";
  button.title = `Click and hold to remove the ${name} map`;
  button.setAttribute("aria-label", `Remove the ${name} map. Click and hold.`);
  button.innerHTML = `<svg class="control__glyph" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true" focusable="false"><path d="M4 7h16M10 7V5.5A1.5 1.5 0 0 1 11.5 4h1A1.5 1.5 0 0 1 14 5.5V7M6 7l1 12.5A1.5 1.5 0 0 0 8.5 21h7a1.5 1.5 0 0 0 1.5-1.5L18 7M10 11v6M14 11v6"/></svg>`;

  let held = null;

  const release = () => {
    window.clearTimeout(held);
    held = null;
    button.classList.remove("card__remove--holding");
  };

  const remove = async () => {
    release();
    button.disabled = true;
    try {
      const response = await fetch("api/delete", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repo: name }),
      });
      if (!response.ok) throw new Error((await response.json()).error || `refused (${response.status})`);
      item.remove();
      const left = el("index").children.length;
      el("stored-title").textContent = `Stored maps (${left})`;
      if (!left) location.reload();
    } catch (error) {
      const failure = document.createElement("span");
      failure.className = "card__error";
      failure.textContent = String(error.message || error);
      item.append(failure);
      button.disabled = false;
    }
  };

  const hold = (event) => {
    if (event.button !== undefined && event.button !== 0) return;
    event.preventDefault();
    event.stopPropagation();
    if (event.pointerId !== undefined) button.setPointerCapture?.(event.pointerId);
    button.classList.add("card__remove--holding");
    held = window.setTimeout(remove, holdDuration());
  };

  button.addEventListener("pointerdown", hold);
  for (const ending of ["pointerup", "pointercancel"]) {
    button.addEventListener(ending, release);
  }
  button.addEventListener("click", (event) => {
    event.preventDefault();
    event.stopPropagation();
  });
  button.addEventListener("keydown", (event) => {
    if (event.key !== "Enter" && event.key !== " ") return;
    event.preventDefault();
    if (!held) hold(event);
  });
  button.addEventListener("keyup", release);
  button.addEventListener("blur", release);

  return button;
}

let arrangementWired = false;

function initArrangement() {
  const apply = (mode) => {
    root.setAttribute("data-view", mode);
    el("index").classList.toggle("cards--list", mode === "list");
    remember(STORED_VIEW, mode);
  };
  apply(recall(STORED_VIEW) === "list" ? "list" : "grid");
  if (arrangementWired) return;
  arrangementWired = true;
  el("view-toggle").addEventListener("click", () => {
    apply(root.getAttribute("data-view") === "list" ? "grid" : "list");
  });
}

/* ── render ───────────────────────────────────────── */
let mermaidReady = false;

function startMermaid() {
  if (mermaidReady) return;
  mermaidReady = true;
  mermaid.registerLayoutLoaders(elk);
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: "antiscript",
    theme: "base",
    flowchart: { defaultRenderer: "elk", curve: "linear", nodeSpacing: 50, rankSpacing: 50 },
  });
}

async function showMap(repo, name) {
  const status = el("status");
  currentRepo = repo;
  crumbs(repo, name);
  startMermaid();

  try {
    const response = await fetch(`out/${encodeURIComponent(repo)}/${encodeURIComponent(name)}.md`);
    if (!response.ok) throw new Error(`${name}.md could not be read (${response.status})`);
    const source = /```mermaid\n([\s\S]*?)```/.exec(await response.text());
    if (!source) throw new Error(`no diagram found in ${name}.md`);

    el("diagram").replaceChildren();

    const { svg } = await mermaid.render("tunica-diagram", source[1], el("measure"));
    if (!svg) throw new Error(`the renderer returned nothing for ${name}`);
    el("diagram").innerHTML = svg;

    const drawing = el("diagram").querySelector("svg");
    if (drawing) {
      drawing.removeAttribute("width");
      drawing.removeAttribute("height");
      drawing.style.maxWidth = "none";
    }
    relink(repo);
    status.hidden = true;
  } catch (error) {
    const message = String(error.message || error);
    status.hidden = false;
    status.textContent = message;
    status.classList.add("notice--error");
    if (!term.running) {
      term.title(`${name} failed to render`, true);
      term.write(message);
    }
  }
}

async function render() {
  const params = new URLSearchParams(location.search);
  const repo = params.get("repo") || "";
  const name = params.get("name") || "overview";
  const status = el("status");

  if (!repo) {
    crumbs(repo, name);
    el("frame").hidden = true;
    await initMapper();
    await renderIndex(status);
    return;
  }

  initDiagramLinks();
  await showMap(repo, name);
}

window.addEventListener("popstate", () => {
  const params = new URLSearchParams(location.search);
  const repo = params.get("repo");
  if (repo) showMap(repo, params.get("name") || "overview");
  else location.reload();
});

const GH_REPO = "Arelius-D/TunICA";
const GH_API = `https://api.github.com/repos/${GH_REPO}`;
const CHANNEL_LABELS = { dev: "dev build", rc: "release candidate", beta: "beta", alpha: "alpha" };

function describeChannel(version) {
  const suffix = (String(version).split("-")[1] || "").toLowerCase().replace(/[^a-z]/g, "");
  if (!suffix) return "release";
  return CHANNEL_LABELS[suffix] || "pre-release";
}

function compareVersions(left, right) {
  const parse = (value) => {
    const [core, pre = ""] = String(value).split("-", 2);
    return { nums: core.split(".").map((n) => parseInt(n, 10) || 0), pre };
  };
  const a = parse(left);
  const b = parse(right);
  for (let i = 0; i < Math.max(a.nums.length, b.nums.length); i += 1) {
    const one = a.nums[i] || 0;
    const two = b.nums[i] || 0;
    if (one !== two) return one > two ? 1 : -1;
  }
  if (!a.pre && b.pre) return 1;
  if (a.pre && !b.pre) return -1;
  return 0;
}

async function ghJson(url) {
  const response = await fetch(url);
  if (!response.ok) {
    const failure = new Error(`GitHub API ${response.status}`);
    failure.status = response.status;
    throw failure;
  }
  return response.json();
}

async function checkForUpdate() {
  const link = el("gh");
  if (!link) return;

  let installed = "";
  let mayAct = false;
  try {
    const config = await (await fetch("api/config")).json();
    installed = config.version || "";
    mayAct = Boolean(config.generate);
    underService = Boolean(config.service);
  } catch {
  }
  if (!installed) return;

  const channel = describeChannel(installed);
  const branch = channel === "release" ? "main" : "dev";
  const base = `TunICA ${installed} (${channel})`;
  const label = (message) => {
    link.title = message;
    link.setAttribute("aria-label", message);
  };

  label(`${base}: checking for updates`);

  let release;
  try {
    release = await ghJson(`${GH_API}/releases/latest`);
  } catch (failure) {
    label(failure.status === 404
      ? `${base}: no releases published yet`
      : `${base}: update check unavailable`);
    return;
  }

  const latest = String(release.tag_name || "").replace(/^v/, "");
  if (!latest) {
    label(`${base}: update check unavailable`);
    return;
  }
  const published = release.published_at
    ? new Date(release.published_at).toLocaleDateString(undefined,
        { day: "numeric", month: "short", year: "numeric" })
    : "";
  const dated = published ? ` (${published})` : "";

  if (compareVersions(latest, installed) > 0) {
    link.classList.add("footer__tool--update");
    link.href = release.html_url || `https://github.com/${GH_REPO}/releases/tag/v${latest}`;
    label(`${base}: update available v${latest}${dated}`);
    if (mayAct) offerUpdate(latest);
    return;
  }

  let ahead = 0;
  try {
    const compared = await ghJson(`${GH_API}/compare/v${latest}...${branch}`);
    if (typeof compared.ahead_by === "number") ahead = compared.ahead_by;
  } catch {
  }
  const trail = ahead ? ` · ${branch} +${ahead} commit${ahead === 1 ? "" : "s"} since v${latest}` : "";

  link.classList.remove("footer__tool--update");
  label(channel === "release"
    ? `${base}: up to date${trail}`
    : `${base}: latest release v${latest}${dated}${trail}`);
}

function offerUpdate(latest) {
  const button = el("update-now");
  if (!button) return;
  button.hidden = false;
  button.title = `Update to v${latest}`;
  button.setAttribute("aria-label", `Update TunICA to v${latest}`);
  button.addEventListener("click", () => runUpdate(latest), { once: true });
}

async function runUpdate(latest) {
  const button = el("update-now");
  if (term.running) {
    term.set("open");
    return;
  }
  button.disabled = true;
  term.set("open");
  term.title(`Updating to v${latest}`);
  term.write("starting…");

  try {
    const response = await fetch("api/update", { method: "POST" });
    if (!response.ok) {
      const body = await response.json().catch(() => ({}));
      term.title(body.error || `update refused (${response.status})`, true);
      button.disabled = false;
      return;
    }
  } catch (failure) {
    term.title(`could not reach the server: ${failure.message}`, true);
    button.disabled = false;
    return;
  }

  term.busy(true);
  const poll = window.setInterval(async () => {
    let state;
    try {
      state = await (await fetch("api/update")).json();
    } catch (ignored) {
      return;
    }
    if (state.lines && state.lines.length) term.write(state.lines.join("\n"));
    if (state.running) return;

    window.clearInterval(poll);
    term.busy(false);
    term.done();
    if (state.ok === false) {
      term.title("update failed", true);
      button.disabled = false;
      return;
    }
    term.title(underService
      ? `updated to v${latest}. Run: systemctl --user restart tunica.service`
      : `updated to v${latest}. Restart tunica view to run it`);
    button.hidden = true;
  }, 2000);
}

checkForUpdate();

initTheme();
initSurface();
initZen();
initTerminal();
render();
