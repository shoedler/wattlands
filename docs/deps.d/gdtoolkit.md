# gdtoolkit (gdlint, gdformat)

- What: GDScript linter and formatter, used by the lint part of `tools/run_tests`'s static step, which fails on any finding when gdtoolkit is available.
- Source: https://github.com/Scony/godot-gdscript-toolkit (PyPI `gdtoolkit`).
- Version: 4.5.0, pinned in `tools/lib/run_tests.mjs` (`GDTOOLKIT_VERSION`; `gdlint`/`gdformat` on PATH count only at that version, else `uvx --from gdtoolkit==4.5.0`).
- License: MIT.
- Not vendored and never shipped: `uvx` fetches it into uv's cache on first use. When Python or uv is missing, the step prints "gdtoolkit unavailable, skipped".
- Project settings: `gdlintrc` at the repo root (see docs/decisions/lead.md).
