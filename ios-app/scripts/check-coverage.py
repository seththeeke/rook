#!/usr/bin/env python3
"""Enforce per-module line-coverage minimums for RookKit (spec §8.2).

Usage: check-coverage.py <llvm-cov export JSON from `swift test --show-codecov-path`>
"""
import collections
import json
import sys

# Minimum line coverage (%) per RookKit module. The session engine (and, from Phase 4, the
# Live Activity state builder) carry the pivotal workout feature, so they get the strictest bar.
THRESHOLDS = {
    "RookSession": 90.0,
    "RookLiveActivityKit": 90.0,
}
DEFAULT_THRESHOLD = 80.0


def main(path: str) -> int:
    with open(path) as handle:
        data = json.load(handle)

    totals = collections.defaultdict(lambda: [0, 0])
    for entry in data["data"][0]["files"]:
        name = entry["filename"]
        if "/Sources/" not in name:
            continue
        module = name.split("/Sources/", 1)[1].split("/", 1)[0]
        lines = entry["summary"]["lines"]
        totals[module][0] += lines["covered"]
        totals[module][1] += lines["count"]

    failed = False
    for module, (covered, count) in sorted(totals.items()):
        percent = 100.0 * covered / count if count else 100.0
        minimum = THRESHOLDS.get(module, DEFAULT_THRESHOLD)
        ok = percent >= minimum
        failed |= not ok
        print(f"{'ok ' if ok else 'LOW'} {module:22} {percent:5.1f}%  (min {minimum:.0f}%, {covered}/{count} lines)")

    if failed:
        print("error: RookKit coverage below the required minimum.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
