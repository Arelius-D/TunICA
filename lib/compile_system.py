#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - compile graph.json into overview.md."""
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

from doc_files import is_doc_only

def node_line(c, indent):
    return f'{indent}{c["id"]}["{esc(c.get("label"))}<br/><i>{esc(c.get("kind", ""))}</i>"]'


def main():
    graph_path, out_dir, depth = sys.argv[1], sys.argv[2], sys.argv[3]
    g = json.load(open(graph_path, encoding="utf-8"))
    comps = g.get("components") or []
    if not comps:
        sys.exit("[ERROR] graph.json has no components")
    groups = [grp for grp in (g.get("groups") or []) if grp.get("id")]
    order = {grp["id"]: i for i, grp in enumerate(groups)}
    tone_of = lambda gid: TONES[order[gid] % len(TONES)] if gid in order else NEUTRAL_NAME

    drawn = [c for c in comps if not is_doc_only(c)]
    drawn_ids = {c["id"] for c in drawn}
    mm = [INIT, "flowchart TD"]
    assigned, tone_members = set(), {}
    for grp in groups:
        members = [c for c in drawn if c.get("group") == grp["id"]]
        if not members:
            continue
        mm += ["", f'    subgraph grp_{grp["id"]}["{esc(grp.get("label"))}"]']
        for c in members:
            mm.append(node_line(c, "      "))
            assigned.add(c["id"])
            tone_members.setdefault(tone_of(grp["id"]), []).append(c["id"])
        mm.append("    end")
    ungrouped = [c for c in drawn if c["id"] not in assigned]
    if ungrouped:
        mm.append("")
        for c in ungrouped:
            mm.append(node_line(c, "    "))
            tone_members.setdefault(NEUTRAL_NAME, []).append(c["id"])

    edges = [(c["id"], u) for c in drawn for u in (c.get("uses") or []) if u in drawn_ids]
    if edges:
        mm.append("")
        mm += [f"    {a} --> {b}" for a, b in edges]

    if depth == "2":
        clickable = [c for c in drawn if c.get("files")]
        if clickable:
            mm.append("")
            mm += [f'    click {c["id"]} "{c["id"]}.md"' for c in clickable]

    mm.append("")
    mm += classdefs()
    for tone, members in tone_members.items():
        mm.append(f'    class {",".join(members)} {tone}')

    meta = os.environ.get("TUNICA_META", "")
    lines = [f"# {esc(g.get('title', 'Repository map'))}", ""]
    if meta:
        lines += [f"> {meta}", ""]
    lines += [str(g.get("description", "")).strip(), "", "```mermaid", *mm, "```", ""]
    cell = lambda s: str(s).strip().replace("|", "/").replace("\n", " ")
    lines += ["## Components", "", "| Component | Kind | Files | Description |", "| :-- | :-- | :-- | :-- |"]
    for c in comps:
        label = esc(c.get("label"))
        name = f"[{label}]({c['id']}.md)" if depth == "2" and (c.get("files") or []) else label
        files = ", ".join(f"`{cell(f)}`" for f in c.get("files") or [])
        lines.append(f"| {name} | {esc(c.get('kind', ''))} | {files} | {cell(c.get('description', ''))} |")
    lines.append("")
    open(os.path.join(out_dir, "overview.md"), "w", encoding="utf-8").write("\n".join(lines) + "\n")
    print(f"[INFO] system map compiled: {len(comps)} components, {len(groups)} groups -> {out_dir}/overview.md")


main()
