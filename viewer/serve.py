#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA viewer server."""
import json
import os
import re
import shutil
import subprocess
import sys
import threading
import time
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

VIEWER_DIR = Path(__file__).resolve().parent
ROOT = VIEWER_DIR.parent
OUT_ROOT = Path(os.environ.get("TUNICA_OUT_ROOT") or (ROOT / "out"))
ALLOW_GENERATE = (os.environ.get("TUNICA_VIEW_ALLOW_GENERATE") or "").strip().lower() == "true"
UNDER_SERVICE = bool(os.environ.get("INVOCATION_ID"))
MAX_BODY = 4096

running = threading.Lock()
running_repo = {"name": None}

updating = {"on": False, "ok": None}
UPDATE_LOG = ROOT / ".update.log"

TARGET = re.compile(r"^[A-Za-z0-9._:/@~+-]{1,400}$")
NAME = re.compile(r"^[A-Za-z0-9._-]{1,120}$")

COVER_SUFFIXES = (".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif")


def version() -> str:
    try:
        for line in (ROOT / "tunica.sh").read_text().splitlines():
            if line.startswith("CODE_VERSION="):
                return line.split('"')[1]
    except OSError:
        pass
    return ""


def stored_maps() -> list:
    entries = []
    if not OUT_ROOT.is_dir():
        return entries
    for path in sorted(OUT_ROOT.iterdir(), key=lambda item: item.name.lower()):
        overview = path / "overview.md"
        if not overview.is_file():
            continue
        components = [f for f in path.glob("*.md") if f.name != "overview.md"]
        cover = next((c.name for c in sorted(path.glob("cover.*"))
                      if c.suffix.lower() in COVER_SUFFIXES), None)
        source = source_of(path)
        entries.append({
            "name": path.name,
            "components": len(components),
            "updated": int(overview.stat().st_mtime),
            "cover": cover,
            "source": source.get("target", ""),
            "depth": source.get("depth", ""),
        })
    return entries


def source_of(path: Path) -> dict:
    found = {}
    record = path / ".work" / "source.txt"
    if not record.is_file():
        return found
    try:
        for line in record.read_text(errors="replace").splitlines():
            key, _, value = line.partition("=")
            if key.strip():
                found[key.strip()] = value.strip()
    except OSError:
        pass
    return found


def repo_name(target: str) -> str:
    if not re.match(r"^(https?://|git@|ssh://)", target):
        try:
            here = Path(target)
            if here.is_dir():
                return here.resolve().name
        except OSError:
            pass
    name = target.rstrip("/").split("/")[-1]
    return name[:-4] if name.endswith(".git") else name


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def end_headers(self):
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def _json(self, status, payload):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.startswith("/api/config"):
            return self._json(200, {
                "generate": ALLOW_GENERATE,
                "version": version(),
                "service": UNDER_SERVICE,
            })
        if self.path.startswith("/api/maps"):
            return self._json(200, {"maps": stored_maps()})
        if self.path.startswith("/api/update"):
            lines = []
            try:
                lines = UPDATE_LOG.read_text(errors="replace").splitlines()[-200:]
            except OSError:
                pass
            return self._json(200, {
                "running": updating["on"],
                "ok": updating["ok"],
                "lines": lines,
            })
        if self.path.startswith("/api/status"):
            name = unquote(self.path.partition("repo=")[2].split("&")[0])
            if not NAME.match(name):
                return self._json(400, {"error": "not a map name"})
            ready = (OUT_ROOT / name / "overview.md").is_file()
            log = OUT_ROOT / name / ".work" / "run.log"
            lines = []
            if log.is_file():
                try:
                    lines = log.read_text(errors="replace").splitlines()[-200:]
                except OSError:
                    lines = []
            return self._json(200, {
                "ready": ready,
                "running": running_repo["name"] == name,
                "lines": lines,
            })
        return super().do_GET()

    def do_POST(self):
        if self.path.startswith("/api/update"):
            return self._update()
        if self.path.startswith("/api/delete"):
            return self._delete()
        if not self.path.startswith("/api/map"):
            return self._json(404, {"error": "no such endpoint"})
        if not ALLOW_GENERATE:
            return self._json(403, {"error": "Mapping from the browser is off. Set TUNICA_VIEW_ALLOW_GENERATE=true in tunica.env to turn it on."})

        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            return self._json(413, {"error": "request too large"})
        try:
            payload = json.loads(self.rfile.read(length) or b"{}")
        except json.JSONDecodeError:
            return self._json(400, {"error": "malformed request"})

        target = str(payload.get("target") or "").strip()
        depth = "2" if str(payload.get("depth")) == "2" else "1"
        if not TARGET.match(target) or ".." in target:
            return self._json(400, {"error": "That does not look like a path, a git URL, or owner/repo."})

        if not running.acquire(blocking=False):
            return self._json(409, {"error": f"already mapping {running_repo['name']}"})

        name = repo_name(target)
        running_repo["name"] = name
        try:
            work = OUT_ROOT / name / ".work"
            work.mkdir(parents=True, exist_ok=True)
            run_log = open(work / "run.log", "w", buffering=1)
            started = time.time()
            process = subprocess.Popen(
                [str(ROOT / "tunica.sh"), target, "-d", depth],
                cwd=str(ROOT), stdout=run_log, stderr=subprocess.STDOUT, start_new_session=True,
            )
            run_log.close()
        except OSError as failure:
            running_repo["name"] = None
            running.release()
            return self._json(500, {"error": f"could not start the run: {failure}"})

        sweep = name if payload.get("replace") else None
        threading.Thread(target=self._await, args=(process, sweep, started), daemon=True).start()
        return self._json(202, {"repo": name})

    def _update(self):
        if not ALLOW_GENERATE:
            return self._json(403, {"error": "This viewer is read only. Set TUNICA_VIEW_ALLOW_GENERATE=true in tunica.env to update from the page."})

        installer = ROOT / "install.sh"

        if not running.acquire(blocking=False):
            return self._json(409, {"error": f"already mapping {running_repo['name']}"})

        updating["on"] = True
        updating["ok"] = None
        try:
            log = open(UPDATE_LOG, "w", buffering=1)
            process = subprocess.Popen(
                [str(installer), "--update", "-y", "--path", str(ROOT)],
                cwd=str(ROOT), stdout=log, stderr=subprocess.STDOUT, start_new_session=True,
            )
            log.close()
        except OSError as failure:
            updating["on"] = False
            running.release()
            return self._json(500, {"error": f"could not start the update: {failure}"})

        threading.Thread(target=self._await_update, args=(process,), daemon=True).start()
        return self._json(202, {"started": True})

    def _await_update(self, process):
        try:
            process.wait()
            updating["ok"] = process.returncode == 0
        finally:
            updating["on"] = False
            running.release()

    def _delete(self):
        if not ALLOW_GENERATE:
            return self._json(403, {"error": "This viewer is read only. Set TUNICA_VIEW_ALLOW_GENERATE=true in tunica.env to manage maps from the page."})

        length = int(self.headers.get("Content-Length") or 0)
        if length > MAX_BODY:
            return self._json(413, {"error": "request too large"})
        try:
            name = str(json.loads(self.rfile.read(length) or b"{}").get("repo") or "")
        except json.JSONDecodeError:
            return self._json(400, {"error": "malformed request"})

        if not NAME.match(name):
            return self._json(400, {"error": "not a map name"})
        target = (OUT_ROOT / name).resolve()
        if target.parent != OUT_ROOT.resolve() or not (target / "overview.md").is_file():
            return self._json(404, {"error": f"no map called {name}"})
        if running_repo["name"] == name:
            return self._json(409, {"error": f"{name} is being mapped right now"})

        shutil.rmtree(target)
        return self._json(200, {"removed": name})

    def _await(self, process, sweep=None, started=0.0):
        try:
            process.wait()
            if sweep and process.returncode == 0:
                self._sweep_stale(sweep, started)
        finally:
            running_repo["name"] = None
            running.release()

    def _sweep_stale(self, name, started):
        if not NAME.match(name):
            return
        folder = (OUT_ROOT / name).resolve()
        if folder.parent != OUT_ROOT.resolve() or not (folder / "overview.md").is_file():
            return
        for stale in folder.glob("*.md"):
            try:
                if stale.stat().st_mtime < started:
                    stale.unlink()
            except OSError:
                pass


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8864
    bind = sys.argv[2] if len(sys.argv) > 2 else "127.0.0.1"
    ThreadingHTTPServer((bind, port), partial(Handler, directory=str(VIEWER_DIR))).serve_forever()


if __name__ == "__main__":
    main()
