#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - compile one component response into <component-id>.md."""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from palette import NEUTRAL_NAME, classdefs, tone_names

TONES = tone_names()

INIT = ("---\n"
        "config:\n"
        "  layout: elk\n"
        "  theme: base\n"
        "  flowchart:\n"
        "    curve: linear\n"
        "    nodeSpacing: 50\n"
        "    rankSpacing: 50\n"
        "---")

san = lambda s: re.sub(r"[^a-z0-9_]", "_", str(s).strip().lower()) or "x"
esc = lambda s: re.sub(r"\s+", " ", re.sub(r"[^\w ,.:/&+'-]", " ", "" if s is None else str(s))).strip() or "unnamed"


def main():
    raw_path, out_dir, cid = sys.argv[1], sys.argv[2], sys.argv[3]
    raw = open(raw_path, encoding="utf-8", errors="replace").read()
    start, end = raw.find("{"), raw.rfind("}")
    try:
        g = json.loads(raw[start:end + 1]) if start >= 0 else {}
    except json.JSONDecodeError:
        g = {}
    nodes = g.get("nodes") or []
    ids = set()
    for n in nodes:
        n["id"] = san(n.get("id", ""))
        while n["id"] in ids:
            n["id"] += "_"
        ids.add(n["id"])
    edges = [e for e in (g.get("edges") or [])
             if san(e.get("from", "")) in ids and san(e.get("to", "")) in ids]

    kinds = []
    for n in nodes:
        k = esc(n.get("kind", "")).lower()
        if k not in kinds:
            kinds.append(k)
    tone_of = lambda k: TONES[kinds.index(k) % len(TONES)] if k in kinds else NEUTRAL_NAME

    mm = [INIT, "flowchart TD", ""]
    tone_members = {}
    for n in nodes:
        mm.append(f'    {n["id"]}["{esc(n.get("label"))}<br/><i>{esc(n.get("kind", ""))}</i>"]')
        tone_members.setdefault(tone_of(esc(n.get("kind", "")).lower()), []).append(n["id"])
    if edges:
        mm.append("")
        for e in edges:
            a, b, lbl = san(e["from"]), san(e["to"]), esc(e.get("label", ""))
            mm.append(f'    {a} -->|"{lbl}"| {b}' if e.get("label") else f"    {a} --> {b}")
    mm.append("")
    mm += classdefs()
    for tone, members in tone_members.items():
        mm.append(f'    class {",".join(members)} {tone}')

    lines = [f"# {cid}", "", "[< back to overview](overview.md)", "",
             "```mermaid", *mm, "```", ""]
    cell = lambda s: str(s).strip().replace("|", "/").replace("\n", " ")
    lines += ["| Element | Kind | File | Description |", "| :-- | :-- | :-- | :-- |"]
    lines += [f"| {esc(n.get('label'))} | {esc(n.get('kind', ''))} | `{cell(n.get('file', ''))}` "
              f"| {cell(n.get('description', ''))} |" for n in nodes]
    lines.append("")
    open(f"{out_dir}/{cid}.md", "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"[INFO] component map compiled: {cid} -> {len(nodes)} nodes, {len(edges)} edges")


main()
