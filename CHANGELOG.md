# TunICA Change Log

All notable changes to TunICA are documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

---

## [Unreleased]

### Added

### Fixed

- A fresh install skipped its onboarding questions. The installer decided whether
  to ask by looking for settings in `tunica.env`, but the file it was reading had
  just been copied from the shipped template, which has them. It now asks when the
  installation is new and stays quiet when it is not, so the line about keeping
  existing settings is only printed when there are existing settings to keep.
- Re-running the installer over an installation overwrote `tunica.env` with the
  template, discarding every setting, and then reported that it had kept them.
  `copy_payload` no longer replaces a config that is already there.
- The shipped `tunica.env` carried a live viewer port and a public URL from the
  machine it was written on, so every installation started out configured as
  someone else's instance. Both lines are commented out again: the port falls
  back to the documented default and the URL is unset until you set it.
- Onboarding never asked which port the viewer should use, so an installation
  always came up on the built-in default and a second instance on the same
  machine collided with the first. It is now one of the questions asked at
  install time.

---

## [1.0.1] - 2026-08-29
### Changed

- The logo is redrawn, and the README now shows it with the wordmark rather than
  the bare mark. The heading beside it drops the name it repeats.
- Every icon is regenerated from the new artwork: `icon-16`, `icon-32`,
  `icon-180`, `icon-512`, `favicon.ico`, and the viewer's own copies.

### Fixed

- `favicon.ico` carried a single 16x16 image. It now holds 16, 32, 48, 64, 128
  and 256, so a browser tab, a bookmark bar and a pinned shortcut each get a
  size drawn for them rather than one upscaled from the smallest.

---

## [1.0.0] - 2026-08-29
First public release. What TunICA is and what it does is described in the README; there is
no earlier version for this file to describe a change from. Every release after this one
records what was added, changed or fixed since the last.

---
