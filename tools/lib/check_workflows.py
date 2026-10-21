"""BRIEF 7.9: every CI workflow parses as YAML and has a jobs map.

tools/run_tests' static step runs this through uv with a pinned PyYAML:
    uv run --no-project --quiet --with pyyaml==6.0.2 python -I tools/lib/check_workflows.py <files>
It prints one FAIL line per bad file and always ends with
"workflows: <n> parsed, <m> failed"; the exit code is 1 when any file failed.
"""

import sys

import yaml


def main(paths):
    bad = 0
    for p in paths:
        try:
            with open(p, encoding="utf-8") as f:
                doc = yaml.safe_load(f)
            if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
                raise ValueError("no jobs map")
        except Exception as e:  # noqa: BLE001 - every failure is reported, none is fatal here
            bad += 1
            print(f"FAIL {p}: {e}")
    print(f"workflows: {len(paths)} parsed, {bad} failed")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
