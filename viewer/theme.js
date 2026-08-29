// TunICA viewer, theme bootstrap.
// Copyright (c) 2026 Arelius-D | AGPL-3.0-only
// Loaded synchronously in the head, ahead of the stylesheet: a deferred module
// paints the system theme first, then flips to the stored one.
(function () {
  try {
    var stored = localStorage.getItem("tunica-theme");
    if (stored === "paper" || stored === "deep-field") {
      document.documentElement.setAttribute("data-theme", stored);
    }
  } catch (ignored) {
  }
})();
