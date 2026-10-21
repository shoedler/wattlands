# Decisions: ui-hud (input router, PedalScanList, HUD kit, theme, Sfx)

Short ADRs for `addons/wattlands/ui/`, `addons/wattlands/audio/`, `tests/ui/` and `tests/audio/` (BRIEF 3.5, 3.9, 4.6.3, 4.6.5, 4.6.8).

## 2026-10-21: Godot's default font; Atkinson Hyperlegible is a drop-in

- Decision: the W1 build ships no font file. `WlTheme` uses Atkinson Hyperlegible when `addons/wattlands/ui/theme/fonts/AtkinsonHyperlegible-Regular.ttf` and `-Bold.ttf` exist, otherwise `ThemeDB.fallback_font`. Dropping both files in (plus `OFL.txt`, a `docs/deps.d/atkinson-hyperlegible.md` entry with source, version and SHA-256, and a credit) switches the Theme and every kit widget over with no code change.
- Alternatives: download the font from Google Fonts or the Braille Institute release during the build.
- Reason: this unattended W1 session can't get Simon's explicit go-ahead for a file download, and BRIEF 3.9 names Godot's default font as the fallback. The readability rules (sizes, outlines, contrast) don't depend on the font.

## 2026-10-21: Synthesized sound only; no CC0 pack

- Decision: every built-in effect (`ui_move` ... `click`) is synthesized at first use by `SfxSynth` (16-bit mono PCM `AudioStreamWAV`, 22 050 Hz, linear envelopes, a fixed-seed xorshift for noise). Games register their own clips; `synth(..., loop = true)` gives looping clips whose pitch a game may change live.
- Alternatives: a CC0 pack (Kenney and similar).
- Reason: same download rule as the font; BRIEF 3.9 makes synthesis the fallback. Synthesis is deterministic, tiny and silent-safe headless.

## 2026-10-21: Input router: edge-detected actions, panic hold and chord

- Decision: device actions fire once per press, edge-detected per key, button or stick direction (key repeats ignored), into `take_actions()`, the `action` signal, `EventBus.action_pressed` and `menu_input(action, "action")`. A keyboard binding of `panic` (Backspace) fires after 1.0 s held, timed by `tick(dt)` from `_process`. A controller binding of `panic` (View) never fires alone: it fires at once together with a controller binding of `pause` (Menu), and Menu pressed while View is held gives panic instead of pause. Panic emits `EventBus.panic_requested` at once and queues `&"panic"`. If `pause` has no controller binding, a controller `panic` binding falls back to the 1 s hold.
- Alternatives: View alone held 1 s also panics; polling `Input.is_action_pressed`.
- Reason: BRIEF 3.5 names View plus Menu together; a lone View press mid-ride must not drop the trainer to safe mode. Edge detection keeps stick motion from flooding the queue.

## 2026-10-21: Gestures never become actions; menus get a mapped `menu_input`

- Decision: gestures from the attached `LocalRider.gesture_detected` go to `take_gestures()`, the `gesture` signal and `EventBus.gesture` only. Menus listen to the added `menu_input(action, via)` signal, which carries device actions and the pedal-UI mapping: `surge` -> confirm, `coast` -> back (never while the attached rider is in ERG), `stop_5s` -> pause (only when `solo` and not in ERG). `pause` and `panic` stay in `take_actions()`; the GameHost filters `WlInputRouter.PLATFORM_ACTIONS` before `local_intents`.
- Alternatives: inject `confirm` into the action queue on a surge.
- Reason: docs/OWNERSHIP.md GM8 and F2.5: a surge must never also arrive as `confirm` in sessions.

## 2026-10-21: Bindings are plain data in a versioned input.cfg

- Decision: `input.cfg` (ConfigFile at `Paths.input_cfg_path()`) holds `[input] version = 1` and `[bindings] <action> = [{"type": "key", "physical_keycode": ...}, ...]`. `rebind()` replaces the action's bindings of the same family (keyboard or controller) and removes that input from every other action; `add_binding()` adds a second one. A missing file, a wrong version or an unknown action falls back to the project.godot defaults with a `push_warning`.
- Alternatives: store `InputEvent` objects in the ConfigFile.
- Reason: plain data is readable, stable across Godot versions and safe to load.

## 2026-10-21: PedalScanList timing

- Decision: scanning steps every `scan_interval_s` (default from the profile, 1.6 s) over enabled items. Up, down, left and right move focus and pause scanning for 10 s. ERG auto-confirm picks the highlighted item `2 x enabled items x scan_interval_s` after the last input or pick, whether scanning is on or not, so with scanning on it lands on the item highlighted when the count began (put the recommended item first), and repeats two cycles later if the list stays open. `coast` never backs out in ERG. A hint line shows how to pick and the auto-pick countdown.
- Alternatives: count cycles of the highlight itself; stop after one auto-pick.
- Reason: BRIEF 3.5 and docs/OWNERSHIP.md PSL2: picks during ERG must happen without input; Siege expects its recommendation on top.

## 2026-10-21: HUD layout rules

- Decision: `HudLayer` is CanvasLayer 10 with one stack per anchor, 32 px from the edges; top anchors stack downward, bottom anchors upward (the first entry nearest the edge); kit widgets first, then game Controls, the banner area and the toast area. A Rect2i is mapped through `PixelViewport.art_rect_to_screen()` into a fixed holder of exactly that rect, re-laid out on the PixelViewport's `resized` and the window's `size_changed`. Kit widgets shrink to fit (`fit_to`, never above 1.0) from a documented `base_size()`; key numbers (own W, rpm, big readouts) never drop below 48 px, so a rect below a widget's documented `min_rect()` overflows rather than shrinking them. The gear indicator is not a key number (48 px at full size, shrinks), so Fishing's 639 x 252 px zone fits timeline, gauge, cadence, W' and gear with W and rpm at 48 px (tested).
- Alternatives: scale whole stacks by one factor; Godot anchors with grow directions.
- Reason: deterministic, testable layout; BRIEF 3.9's 48 px rule; docs/OWNERSHIP.md HUD2.

## 2026-10-21: Raw W and %FTP always on screen; W/kg only by opt-in

- Decision: if a spec has no power gauge (and not both a `power_w` and an `ftp_pct` readout), `HudLayer` adds a gauge at bottom_left (`ensure_power_visible`). W/kg shows when the profile opts in: `RiderProfile.show_wkg` if that field exists, else `share_weight`; `HudLayer.wkg_weight_kg` overrides.
- Alternatives: trust each game's spec.
- Reason: BRIEF 3.3 and pillar 2. The profile has no W/kg display flag yet (requested from platform).

## 2026-10-21: Safety banners

- Decision: the banner area shows the most urgent of paused, rescue and warm-up (paused > rescue > warm-up), each with its own text and color (grey, orange, purple; never color alone), warm-up smaller. Sources are OR-ed: `set_safety_state()`, `update()`'s telemetry (`rescue`, `paused`) and the bus (`rescue_changed` and `governor_status` for the local peer, `paused_changed`). `HudSpec.show_safety_banners = false` hides them.
- Reason: BRIEF 4.6.3, 4.6.8; the GameHost can feed whichever it has.

## 2026-10-21: Shared Theme as a hand-written .tres plus WlTheme constants

- Decision: `res://addons/wattlands/ui/theme/wattlands_theme.tres` (dark panels, 32 px body, 40 px buttons, 48 px line edits, sky-blue focus) and `WlTheme` (sizes, Okabe-Ito based colors, `label_settings()`, `panel_style()`). Kit widgets use LabelSettings with a dark outline so text reads over any game art.
- Reason: games match the kit by setting the same Theme and using the same constants (HUD11).
