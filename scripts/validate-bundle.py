#!/usr/bin/env python3
"""Validate one or more LSML bundles against spec/schema.json.

Usage:
    python scripts/validate-bundle.py <bundle.json> [<bundle2.json> ...]
    python scripts/validate-bundle.py spec/examples/*.lsml.json

Exits 0 if every bundle validates, 1 otherwise. Prints a per-file
summary with error details on failure.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import jsonschema
except ImportError:
    sys.stderr.write(
        "error: jsonschema not installed. Install with: pip install jsonschema\n"
    )
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "spec" / "schema.json"


def main(args: list[str]) -> int:
    if not args:
        sys.stderr.write(f"usage: {sys.argv[0]} <bundle.json> [...]\n")
        return 2

    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    validator = jsonschema.Draft202012Validator(schema)

    failures = 0
    for arg in args:
        path = Path(arg)
        if not path.exists():
            print(f"  FAIL{path} : file not found")
            failures += 1
            continue

        try:
            bundle = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as exc:
            print(f"  FAIL{path} : invalid JSON — {exc}")
            failures += 1
            continue

        errors = sorted(validator.iter_errors(bundle), key=lambda e: e.path)
        if not errors:
            print(f"  OK   {path}")
            continue

        failures += 1
        print(f"  FAIL{path} : {len(errors)} validation error(s)")
        for err in errors:
            location = "/".join(str(p) for p in err.absolute_path) or "(root)"
            print(f"      at {location}: {err.message}")

    if failures:
        print(f"\n{failures} bundle(s) failed validation")
        return 1

    print(f"\nAll {len(args)} bundle(s) validate cleanly.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
