# gate

- Added a machine-wide cap file for the Godot lock: `node tools/lib/godot_lock.mjs set-cap <n>` (`0` deletes it, and the default stays as it was with no file). `WATTLANDS_GODOT_LOCK_CAP` still wins.
- Added `WATTLANDS_USERDATA_DIR` to `tools/godot.sh` and `tools/godot.ps1`, for concurrent runs in one checkout.
- `tools/screenshot` now opens at most 4 windows at once on a machine; further runs wait for a free one.
