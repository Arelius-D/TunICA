# TunICA Change Log

All notable changes to TunICA are documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

---

## [Unreleased]

### Added

### Changed

### Fixed

---

## [1.4.0] - 2026-09-03

### Added

- Onboarding asks whether the viewer page may map a repository and delete a map,
  and writes `TUNICA_VIEW_ALLOW_GENERATE`. The page's controls do nothing while
  that is false, which is what a fresh install had, and nothing said so.
- Onboarding asks per setting rather than per install, so it covers every setting
  that decides whether an installation works: model, out root, port, bind
  address and public URL, page controls, and the service. A question whose
  setting `tunica.env` already answers is not asked again, an update asks the
  ones added since you installed, and the service question is skipped when a unit
  is already there. `-y` and a run with no terminal ask nothing and write
  nothing, as before.

### Changed

### Fixed

---

## [1.3.0] - 2026-09-03

### Added

- Saying yes to the service also offers to keep it running after you log out. A
  `systemd --user` service stops with your login session unless lingering is on,
  so the service offered at install time died with the terminal that asked for
  it. On a yes it runs `sudo loginctl enable-linger <you>` and reports the
  result. The command is printed before it runs, never runs without a yes at a
  terminal, and a no leaves it for you to run. `tunica service install` asks the
  same question.

### Changed

### Fixed

---

## [1.2.1] - 2026-09-03

### Added

### Changed

- Uninstalling names the directory it removed and nothing else.

### Fixed

---

## [1.2.0] - 2026-09-03

### Added

- Onboarding asks whether to keep the viewer running as a `systemd --user`
  service, and installs one on a yes. It defaults to no, and `-y` never installs
  one. The service existed before only as a command nothing mentioned during an
  install.

### Changed

### Fixed

- `tunica view` refused to start while the out root held no maps, which is every
  fresh installation. It serves the index, which lists maps as they appear.
  Naming a map that does not exist is still an error.

---

## [1.1.2] - 2026-09-03

### Added

### Changed

### Fixed

- The installer log was written to `$HOME/.tunica-install.log`, outside the
  installation, and outlived it, so uninstalling ended by asking whether to
  delete it. The path was fixed at the top of the script, before the target is
  known. Lines are held until it is known, then written to `install.log` inside
  the installation. A run that ends before a target exists writes nothing.
  `TUNICA_INSTALL_LOG` still overrides the location.

---

## [1.1.1] - 2026-09-03

### Added

### Changed

### Fixed

- `--update`, `--uninstall` and `--check` looked at `$HOME/TunICA` whichever
  copy of the installer was run, so an installation put anywhere else could not
  be updated, checked or removed by its own installer. An installer sitting
  beside the `tunica.sh` and `lib` it copied takes that directory as its target,
  unless `--path` or `TUNICA_INSTALL_DIR` says otherwise. A source tree is told
  apart by its `README.md`, which is not part of the payload, so an update run
  inside a checkout or an extracted tarball cannot overwrite it with `main`. The
  piped one-liner still offers `$HOME/TunICA`.

---

## [1.1.0] - 2026-09-03

### Added

- Onboarding asks how you will reach the viewer and writes `TUNICA_VIEW_BIND`
  from the answer: this machine, the network, or a reverse proxy. The proxy
  answer also asks for the public address and stores it as `TUNICA_VIEW_URL`,
  which is the link `tunica view` prints, not what the server binds. The bind
  address was left at `auto`, which is loopback unless the viewer is started
  from an SSH session, and loopback under a service either way.
- A question with no useful default shows `[Enter = skip]`.

### Changed

### Fixed

---

## [1.0.6] - 2026-09-03

### Added

### Changed

### Fixed

- The install location prompt asks for a path under `$HOME` and then rejected
  one: `Apps/TunICA` was refused as outside it, because only an answer that
  already began with the full home path was accepted. A relative answer is read
  as relative to `$HOME`, and `--path` reads a path the same way. Both expand
  `~` and resolve `.` and `..` first, so a path that climbs out of your home
  directory is still refused.
- `--path $HOME` was accepted as an install location, which made
  `install.sh --uninstall` a command that deletes your home directory. The
  target must be a directory under `$HOME`.

---

## [1.0.5] - 2026-09-03

### Added

### Changed

### Fixed

- Prompts mark their default as `[Y/n]` and `[y/N]`.

---

## [1.0.4] - 2026-09-03

### Added

### Changed

### Fixed

- The one-line installer could not install anything. It downloads TunICA when
  run outside a checkout, and the line announcing the download was captured as
  part of the path it returned, so the fetched tree was never found and every
  run ended in `could not resolve a TunICA source tree`. A failed download
  reported that same message instead of its own, and left the temporary tree in
  `/tmp`.

---

## [1.0.3] - 2026-09-03

### Added

### Changed

### Fixed

- Every prompt showed its default in brackets without saying what the brackets
  meant. Each reads `[Enter = <default>]`, and the install location and
  onboarding are introduced by a line saying so.
- The dependency report listed every tool it found. It says one line when
  everything is present and speaks up only about what is missing.
- A missing Claude CLI was a warning, so the installer asked where to install
  and which model to use before finishing an installation that could not map
  anything. It is a required dependency: the run stops before the first
  question and nothing is written.
- The install location prompt asked for a path. It asks whether to use the
  default, and takes another path under `$HOME` if you type one.

---

## [1.0.2] - 2026-09-03

### Added

### Changed

### Fixed

- A fresh install skipped its onboarding questions. It decided whether to ask by
  looking for settings in `tunica.env`, which had just been copied from the
  shipped template that has them. It asks when the installation is new.
- Re-running the installer over an installation overwrote `tunica.env` with the
  template, discarding every setting, and reported that it had kept them.
  `copy_payload` no longer replaces a config that is already there.
- The shipped `tunica.env` carried a live viewer port and a public URL from the
  machine it was written on, so every installation started out configured as
  someone else's instance. Both are commented out.
- Onboarding never asked which port the viewer should use, so a second instance
  on the same machine collided with the first. It is one of the questions.
- The viewer's default port is 8866. It was 8864, which is also the port the
  bundled server fell back to when started directly, so the two had to be kept
  in step by hand.

---

## [1.0.1] - 2026-08-29

### Added

### Changed

- The logo is redrawn, and the README shows it with the wordmark rather than the
  bare mark. The heading beside it drops the name it repeats.
- Every icon is regenerated from the new artwork: `icon-16`, `icon-32`,
  `icon-180`, `icon-512`, `favicon.ico`, and the viewer's own copies.

### Fixed

- `favicon.ico` carried a single 16x16 image. It holds 16, 32, 48, 64, 128 and
  256, so a tab, a bookmark bar and a pinned shortcut each get a size drawn for
  them rather than one upscaled from the smallest.

---

## [1.0.0] - 2026-08-29

First public release. The README describes what TunICA is and what it does.
Every release after this one records what was added, changed or fixed since the
last.

---
