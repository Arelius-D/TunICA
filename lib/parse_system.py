#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - parse and validate the system-map response into graph.json."""
import json
import re
import sys

san = lambda s: re.sub(r"[^a-z0-9_]", "_", str(s).strip().lower()) or "x"


def main():
    raw_path, graph_path, tree_path = sys.argv[1], sys.argv[2], sys.argv[3]
    raw = open(raw_path, encoding="utf-8", errors="replace").read()
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end <= start:
        sys.exit(f"[ERROR] no JSON object in model output. Inspect {raw_path}")
    try:
        g = json.loads(raw[start:end + 1])
    except json.JSONDecodeError as e:
        sys.exit(f"[ERROR] invalid JSON from model ({e}). Inspect {raw_path}")
    comps = g.get("components") or []
    if not comps:
        sys.exit("[ERROR] model returned no components")

    tree = set(open(tree_path, encoding="utf-8").read().splitlines())
    ids, dropped = set(), []
    for c in comps:
        c["id"] = san(c.get("id", ""))
        while c["id"] in ids:
            c["id"] += "_"
        ids.add(c["id"])
        kept = [f for f in (c.get("files") or []) if f in tree]
        dropped += [f for f in (c.get("files") or []) if f not in tree]
        c["files"] = kept
    for c in comps:
        raw_edges = c.get("calls") or c.get("uses") or []
        c["uses"] = [san(u) for u in raw_edges if san(u) in ids and san(u) != c["id"]]
        c.pop("calls", None)

    groups = g.get("groups") or []
    gids, merged = set(), []
    for grp in groups:
        grp["id"] = san(grp.get("id", ""))
        if grp["id"] in gids:
            merged.append(grp.get("label") or grp["id"])
            while grp["id"] in gids:
                grp["id"] += "_"
        gids.add(grp["id"])
    for c in comps:
        grp = san(c.get("group") or "")
        c["group"] = grp if grp in gids else None

    if merged:
        print(f"[WARN] group id collision, renamed: {', '.join(merged)}")
    if dropped:
        print(f"[WARN] dropped {len(dropped)} hallucinated path(s): {', '.join(dropped[:5])}")
    open(graph_path, "w", encoding="utf-8").write(json.dumps(g, indent=2))
    print(f"[INFO] system map: {len(comps)} components, {len(groups)} groups")


main()
