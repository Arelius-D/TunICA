#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - which components are documentation rather than architecture."""
import re

DOC_FILE = re.compile(
    r"(^|/)(README|LICENSE|LICENCE|CHANGELOG|CONTRIBUTING|FUNDING|SECURITY|CODE_OF_CONDUCT)[^/]*$"
    r"|(^|/)\.github/",
    re.I,
)


def is_doc_only(component):
    """True when every file of the component is documentation or repository metadata."""
    files = component.get("files") or []
    return bool(files) and all(DOC_FILE.search(f) for f in files)
