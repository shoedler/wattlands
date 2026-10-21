# Dependencies

Every third-party dependency, merged from `docs/deps.d/` (one file per dependency, with source, version, license and SHA-256 sums). Third-party code is vendored from GitHub releases or pinned commits, never from the in-editor Asset Store (BRIEF 1).

| Dependency | Version | License | Where | Used for | Record |
| --- | --- | --- | --- | --- | --- |
| Godot Engine | 4.7.2 stable (.NET build used for running and testing; standard build for exports) | MIT | Installed separately | Engine | `docs/decisions/lead.md` |
| GUT (Godot Unit Test) | 9.7.1 (`aeb5d4f`) | MIT | `addons/gut/` | Unit tests only | `docs/deps.d/gut.md` |
| GDBLE | v0.6.0 (tag commit `ecae959`) | MIT | `addons/gdble/` (Windows and Linux x86_64 libraries) | Bluetooth LE GDExtension on btleplug | `docs/deps.d/gdble.md` |
| Node.js | 22.12 or newer on PATH (26.12 here) | MIT | Installed separately | Relay, mock servers, art pipeline, e2e harness, tool wrappers | — |

Optional tools: Python 3.12+ with uv (the trainer bridge and gdtoolkit linting), Docker (the relay image).
