#!/usr/bin/env python3
# Copyright (c) 2026 Arelius-D | AGPL-3.0-only
"""TunICA - extract a claude CLI JSON envelope and keep a running token tally.

  usage.py record <envelope.json> <response-out> <tally.json> <label>
  usage.py total  <tally.json>
"""
import json
import sys


def load(path, default):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError):
        return default


FIELDS = ("input_tokens", "output_tokens", "cache_read_input_tokens", "cache_creation_input_tokens")


def record(envelope_path, response_path, tally_path, label):
    env = load(envelope_path, None)
    if env is None:
        sys.exit(f"[ERROR] unreadable claude envelope: {envelope_path}")
    if env.get("is_error"):
        sys.exit(f"[ERROR] claude reported an error ({label}): {str(env.get('result'))[:300]}")
    text = env.get("result") or ""
    if not text.strip():
        sys.exit(f"[ERROR] claude returned no content ({label})")
    with open(response_path, "w", encoding="utf-8") as f:
        f.write(text)

    u = env.get("usage") or {}
    call = {k: int(u.get(k) or 0) for k in FIELDS}
    call["cost_usd"] = float(env.get("total_cost_usd") or 0.0)
    call["label"] = label

    tally = load(tally_path, {"calls": []})
    tally["calls"].append(call)
    with open(tally_path, "w", encoding="utf-8") as f:
        json.dump(tally, f, indent=2)

    billed = call["input_tokens"] + call["output_tokens"] + call["cache_creation_input_tokens"]
    print(f"[INFO]   tokens: in {call['input_tokens']:,} + out {call['output_tokens']:,} "
          f"+ cache write {call['cache_creation_input_tokens']:,} "
          f"(cache read {call['cache_read_input_tokens']:,}, free) = {billed:,}")


def total(tally_path):
    tally = load(tally_path, {"calls": []})
    calls = tally.get("calls") or []
    if not calls:
        return
    s = {k: sum(c.get(k, 0) for c in calls) for k in FIELDS}
    cost = sum(c.get("cost_usd", 0.0) for c in calls)
    billed = s["input_tokens"] + s["output_tokens"] + s["cache_creation_input_tokens"]
    print(f"[INFO] usage: {len(calls)} claude call(s)")
    print(f"[INFO]   input          {s['input_tokens']:,}")
    print(f"[INFO]   output         {s['output_tokens']:,}")
    print(f"[INFO]   cache write    {s['cache_creation_input_tokens']:,}")
    print(f"[INFO]   cache read     {s['cache_read_input_tokens']:,}  (not billed)")
    print(f"[INFO]   billed total   {billed:,} tokens")
    print(f"[INFO]   list price     ${cost:.4f}  (CLI estimate; drawn from your plan, not invoiced)")


mode = sys.argv[1] if len(sys.argv) > 1 else ""
if mode == "record" and len(sys.argv) == 6:
    record(*sys.argv[2:6])
elif mode == "total" and len(sys.argv) == 3:
    total(sys.argv[2])
else:
    sys.exit("usage: usage.py record <envelope> <response> <tally> <label> | total <tally>")
