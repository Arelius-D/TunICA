#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - drop the paths a repository has said are not part of it.

Paths arrive on stdin, one per line, and the ones that survive go back out.
"""
import fnmatch
import os
import sys

REPO = os.environ.get("TUNICA_REPO", "")


def rules() -> list:
    """Every pattern .gitignore states, without the ones that re-include."""
    try:
        with open(os.path.join(REPO, ".gitignore"), encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return []
    return [line.strip().rstrip("/").lstrip("/") for line in lines
            if line.strip() and not line.strip().startswith(("#", "!"))]


def ignored(path: str, patterns: list) -> bool:
    """True when any pattern covers the path, a directory above it, or a name in it."""
    parts = path.split("/")
    prefixes = ["/".join(parts[:i + 1]) for i in range(len(parts))]
    return any(fnmatch.fnmatch(candidate, pattern)
               for pattern in patterns
               for candidate in prefixes + parts)


def main() -> None:
    patterns = rules()
    for line in sys.stdin:
        path = line.rstrip("\n")
        if path and not ignored(path, patterns):
            print(path)


main()
