#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - the image a repository already publishes for itself."""
import re
import shutil
import sys
from pathlib import Path

MARKDOWN_IMAGE = re.compile(r"!\[[^\]]*\]\(\s*<?([^)\s>]+)")
HTML_IMAGE = re.compile(r"<img[^>]+src\s*=\s*[\"']([^\"']+)", re.I)
READMES = ("README.md", "README", "readme.md", "Readme.md")
SUFFIXES = {".png", ".jpg", ".jpeg", ".webp", ".svg", ".gif"}
MAX_BYTES = 2 * 1024 * 1024
NOT_IDENTITY = re.compile(r"badge|shield|visitor|coverage|build|ci[-_.]", re.I)


def candidates(readme: str):
    """Every image the README shows, in the order a reader meets them."""
    found = list(MARKDOWN_IMAGE.finditer(readme)) + list(HTML_IMAGE.finditer(readme))
    for match in sorted(found, key=lambda item: item.start()):
        yield match.group(1).strip()


def find_cover(repo: Path) -> Path | None:
    for name in READMES:
        readme = repo / name
        if not readme.is_file():
            continue
        text = readme.read_text(encoding="utf-8", errors="replace")
        for reference in candidates(text):
            if reference.startswith(("http://", "https://", "//", "data:")):
                continue
            if NOT_IDENTITY.search(reference):
                continue
            path = (repo / reference.split("#")[0].split("?")[0]).resolve()
            if repo.resolve() not in path.parents:
                continue
            if path.is_file() and path.suffix.lower() in SUFFIXES and path.stat().st_size <= MAX_BYTES:
                return path
        return None
    return None


def main():
    repo, out_dir = Path(sys.argv[1]), Path(sys.argv[2])
    cover = find_cover(repo)
    if not cover:
        return
    target = out_dir / f"cover{cover.suffix.lower()}"
    for stale in out_dir.glob("cover.*"):
        stale.unlink()
    shutil.copy2(cover, target)
    print(f"[INFO] cover: {cover.relative_to(repo)}")


main()
