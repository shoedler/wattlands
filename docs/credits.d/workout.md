# Credits: Workout

- All of Workout's audio is synthesized from the recipes in `assets/workout/audio/audio.json`, rendered by `tools/audio`: no samples, no downloads, no generated-media service, no third-party material. Nothing to attribute.
# Credits: workout

Art, audio and fonts the Workout game ships, with their sources.

- Art: no generated or downloaded art (no fal calls). Everything in `assets/workout/` is drawn by our own zero-dependency Node code: `src/games/workout/art/bake.mjs` (riders, world planes, the time-of-day table, props, picker card) and `src/games/workout/art/hud_bake.mjs` (the HUD's type and crank icon). PNG encoding uses the repo's `tools/art/lib/png.mjs`.
- Fonts: `wo_text_5x7`, `wo_tall_5x9` and `wo_digits_14x24` in `assets/workout/hud/` are drawn by `src/games/workout/art/hud_font.mjs`.
- Platform fonts and UI kit (help, pause and results screens): the platform's, credited in the platform's credits.
