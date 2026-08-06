#!/usr/bin/env python3
"""Merge deterministic Python and JavaScript discovery facts."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable


def unique_sorted(items: Iterable[Any], keys: tuple[str, ...] | None = None) -> list[Any]:
    unique: dict[str, Any] = {}
    for item in items:
        identity = json.dumps(item, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        unique[identity] = item
    if keys is None:
        return sorted(unique.values())
    return sorted(unique.values(), key=lambda item: tuple(str(item.get(key, "")) for key in keys))


def load(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--python", required=True, type=Path)
    parser.add_argument("--javascript", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    python_facts = load(args.python)
    javascript_facts = load(args.javascript)
    digest_text = "\n".join(
        (python_facts["snapshot"]["source_digest"], javascript_facts["snapshot"]["source_digest"])
    )
    merged = {
        "schema_version": "1.0.0",
        "snapshot": {
            "git_commit": python_facts["snapshot"].get("git_commit"),
            "dirty": python_facts["snapshot"].get("dirty", False),
            "source_digest": hashlib.sha256(digest_text.encode()).hexdigest(),
        },
        "tools": unique_sorted(
            (*python_facts.get("tools", []), *javascript_facts.get("tools", [])), ("name", "version")
        ),
        "capabilities": unique_sorted(
            (*python_facts.get("capabilities", []), *javascript_facts.get("capabilities", []))
        ),
        "entrypoints": unique_sorted(
            (*python_facts.get("entrypoints", []), *javascript_facts.get("entrypoints", [])),
            ("path", "symbol", "kind", "evidence"),
        ),
        "modules": unique_sorted(
            (*python_facts.get("modules", []), *javascript_facts.get("modules", [])), ("path",)
        ),
        "symbols": unique_sorted(
            (*python_facts.get("symbols", []), *javascript_facts.get("symbols", [])),
            ("path", "start_line", "name"),
        ),
        "edges": unique_sorted(
            (*python_facts.get("edges", []), *javascript_facts.get("edges", [])),
            ("from", "type", "to", "line"),
        ),
        "read_set": [],
        "diagnostics": unique_sorted(
            (*python_facts.get("diagnostics", []), *javascript_facts.get("diagnostics", [])),
            ("level", "code", "message"),
        ),
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(merged, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "mixed discover: "
        f"entrypoints={len(merged['entrypoints'])} modules={len(merged['modules'])} "
        f"symbols={len(merged['symbols'])} edges={len(merged['edges'])}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
