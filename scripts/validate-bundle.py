#!/usr/bin/env python3
"""Validate one or more LSML bundles against spec/schema.json.

Bundles are JSON documents (RFC 8259). Any of these extensions are
accepted — the bytes are identical, only the brand differs (LSML §18.1):

    - .lsml          (preferred)
    - .lsml.json     (alternative)
    - .json          (legacy)

Usage:
    python scripts/validate-bundle.py <bundle.lsml> [<bundle2.lsml> ...]
    python scripts/validate-bundle.py spec/examples/*.lsml

Exits 0 if every bundle validates, 1 otherwise. Prints a per-file
summary with error details on failure.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    import jsonschema
    from referencing import Registry, Resource
    from referencing.jsonschema import DRAFT202012
except ImportError:
    sys.stderr.write(
        "error: jsonschema/referencing not installed. "
        "Install with: pip install 'jsonschema>=4.18' referencing\n"
    )
    sys.exit(2)

ROOT = Path(__file__).resolve().parent.parent
SCHEMA_PATH = ROOT / "spec" / "schema.json"
ADAPTERS_DIR = ROOT / "spec" / "adapters"


def _build_registry() -> Registry:
    """Pre-load every spec/adapters/*.json under its `$id` so AdapterDecl
    `$ref` resolution succeeds offline (LSML §9.1 enforcement)."""
    registry: Registry = Registry()
    for adapter_file in sorted(ADAPTERS_DIR.glob("*.json")):
        schema = json.loads(adapter_file.read_text(encoding="utf-8"))
        ref_id = schema.get("$id")
        if not ref_id:
            sys.stderr.write(
                f"warning: {adapter_file} has no $id, skipping\n"
            )
            continue
        resource = Resource.from_contents(schema, default_specification=DRAFT202012)
        registry = registry.with_resource(uri=ref_id, resource=resource)
    return registry


def main(args: list[str]) -> int:
    if not args:
        sys.stderr.write(f"usage: {sys.argv[0]} <bundle.lsml> [...]\n")
        return 2

    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    registry = _build_registry()
    validator = jsonschema.Draft202012Validator(schema, registry=registry)

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
