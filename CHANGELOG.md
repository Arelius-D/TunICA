# TunICA Change Log

All notable changes to TunICA are documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

---

## [1.2.0] - 2026-09-03

### Added

- The install asks whether to keep the viewer running as a systemd --user
  service, the last question of onboarding. It answers no by default, and a
  scripted install with `-y` never installs one, so nothing appears in
  `~/.config/systemd/user/` unless you say yes. Until now the service existed
  only as `tunica service install`, which nothing mentioned while installing, so
  a finished install left you with a viewer that was not running and a proxy in
  front of it answering 502.

### Changed

### Fixed

- `tunica view` refused to start while the out root held no maps, which is every
  fresh installation. Nothing could be served until the first repository was
  mapped, and a service installed before that would have failed and retried
  every five seconds. It now starts and serves the index, which lists maps as
  they appear. Asking for a map by name that does not exist is still an error.

---

## [1.1.2] - 2026-09-03

### Added

### Changed

### Fixed

- The installer kept its log at `$HOME/.tunica-install.log`, outside the
  installation, and left it there when the installation was removed, which is
  why uninstalling ended by asking whether to delete a stray file. The log was
  named at the top of the script, before the target directory is known, and for
  a fresh install the target does not exist until the first question is
  answered. Lines are now held until the target is known and then written to
  `install.log` inside it, so an installation owns its own log, an update and a
  check append to it, and an uninstall takes it away with everything else. A run
  that ends before a target exists, a failed dependency check, writes nothing at
  all: those lines were printed to the terminal. `TUNICA_INSTALL_LOG` still puts
  the log wherever you say.

---

## [1.1.1] - 2026-09-03

### Added

### Changed

### Fixed

- `--update`, `--uninstall` and `--check` looked at `$HOME/TunICA` no matter
  which copy of the installer was run, so every installation that answered the
  install prompt with a different location was unreachable by its own installer:
  running `/home/you/Apps/TunICA/install.sh --update` reported nothing installed
  at `/home/you/TunICA` and stopped. An installer that sits in an installation,
  next to the `tunica.sh` and `lib` it copied there, now takes that installation
  as its target unless `--path` or `TUNICA_INSTALL_DIR` says otherwise. A source
  tree is told apart by the `README.md` an installation never receives, whether
  it arrived by `git clone` or as an extracted tarball, so `--update` run inside
  one cannot overwrite it with `main`. The piped one-liner sits in no directory
  at all and still offers `$HOME/TunICA`.

---

## [1.1.0] - 2026-09-03

### Added

- Onboarding asks how you will reach the viewer, and writes the answer, so a
  fresh installation is reachable without opening a file afterwards. From this
  machine only, from other machines on your network, or through a reverse proxy;
  the third also asks the public address the proxy serves it at. The answer is
  stored as `TUNICA_VIEW_BIND`, and the address as `TUNICA_VIEW_URL`, which is
  the link `tunica view` prints and not what the server listens on. A question
  with no useful default now offers `[Enter = skip]` rather than an empty one.
  Until now the install asked for a port and left the bind address at `auto`,
  which is loopback unless the shell starting the viewer is an SSH session, and
  is loopback under a systemd service whatever the shell was. A proxy on the same
  host then reached a port bound to loopback, answered 502, and nothing in the
  installation had said which setting decides that.

### Changed

### Fixed

---

## [1.0.6] - 2026-09-03

### Added

### Changed

### Fixed

- The install location prompt asks for "another path under `$HOME`" and then
  rejected one. Answering `Apps/TunICA` was refused as being outside `$HOME`,
  because the answer was only accepted when it already began with the full
  `/home/you/`, and the prompt looped on the same question with no way to say
  what it wanted. A relative answer is now taken as relative to `$HOME`, which is
  what the question asks for, and `--path` reads a path the same way. Both
  resolve `~`, `.` and `..` before deciding, so a path that climbs out of your
  home directory is still refused rather than accepted on the strength of its
  first few characters.
- `--path $HOME` was accepted as an install location, which made
  `install.sh --uninstall` a command that deletes your home directory. The
  installer now takes a directory under `$HOME`, never `$HOME` itself.

---

## [1.0.5] - 2026-09-03

### Added

### Changed

### Fixed

- Prompts now mark their default in the usual way, as `[Y/n]` and `[y/N]`.

---

## [1.0.4] - 2026-09-03

### Added

### Changed

### Fixed

- The one-line installer could not install anything. It downloads TunICA when it
  is run outside a checkout, and the line announcing the download was captured as
  part of the path it returned, so the fetched tree was never found: every run of
  the command in the README ended in `could not resolve a TunICA source tree`. A
  failed download reported that same generic message instead of its own, and the
  temporary tree was left behind in `/tmp`.

---

## [1.0.3] - 2026-09-03

### Added

### Changed

### Fixed

- Every installer prompt showed its default in brackets without saying what the
  brackets meant, so the first thing a new install asks for looked like a
  question with no obvious answer. Each one now reads `[Enter = <default>]`, and
  the install location and onboarding are introduced by a line saying so.
- The dependency report listed every tool it found. It now says one line when
  everything is present and speaks up only about what is missing.
- A missing Claude CLI was a warning, so the installer asked where to install and
  what model to use before finishing an installation that could not map anything.
  It is a required dependency: the run stops before the first question and
  nothing is written.
- The install location prompt asked for a path. It now asks whether to use the
  default, and takes a different path under `$HOME` if you type one instead.

---

## [1.0.2] - 2026-09-03

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
- The viewer's default port is 8866. It was 8864, which is also the port the
  bundled server fell back to when started directly, so the two had to be kept
  in step by hand.

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
