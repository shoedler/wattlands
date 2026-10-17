# Wattlands: concept phase

Wattlands is a multiplayer fitness party game for the Wahoo KICKR CORE smart trainer. It will be built in Godot 4.7 by a single autonomous ultracode run.

This repo holds the planning material and has no game code yet. We are in the concept phase: make and review concept art, cut the concept list with Simon, and finalize the build brief.

Simon works on Windows in the Claude desktop app. That matches the brief's Windows-first target.

## What Simon asked for

- A KICKR CORE game built in Godot, using ERG mode wherever it makes the game better.
- Pedaling comes first. An Xbox controller or light keyboard use is optional, and every mode must be playable with no input at all.
- Multiplayer from the start: a host shares a short code, friends type it in, and there are no accounts.
- Rides upload to Strava.
- Concepts are judged on fun and on endurance and training effect.

## Files

- `docs/BRIEF.md` is the build prompt for the ultracode run and starts with the word ultracode.
  - Section 3.6 picks the modes; the other sections say "each P0 mode".
  - Edit this file, never a copy of it.
- `docs/research.md` is a 17 Oct 2026 snapshot of the planning doc. It covers:
  - trainer facts and existing products,
  - the four concepts with fun and training pros and cons,
  - decisions, the "Before you paste" setup checklist, open questions and sources.
- `docs/concept/` holds the concept art. `manifest.json` records each image's prompt, model and cost, and `index.html` is the contact sheet.
- `tools/concept_art/wattlands_concept_art.py` generates the art on fal.ai.
- `.claude/settings.json` sets Opus 5.5, xhigh effort and the large workflow size guideline for every session in this repo.
- `.gitattributes` keeps LF line endings, so bash scripts keep working in Git Bash.

## Where things stand (17 Oct 2026)

- Shortlist: Generator Siege, Tank Crew and Big Game Fishing. Kart Rush stays in the brief as P2 notes.
- Dropped ideas. Don't revive any of them without asking:
  - Boss Raid, because WATTGAMES already does interval boss fights.
  - Ramp Tower and Tug-of-War, because they're too thin.
  - Paceline TTT, because Zwift covers it.
  - Pedal Survivors, Track Night and Stealth Heist.
- Art direction: a spread of four styles (low-poly diorama, cel-shaded cartoon, painterly storybook, 16-bit pixel art). Each is drawn by both Nano Banana 2 and FLUX 3.
- fal budget: about $5 in total. Round 1 is estimated at $1.68, and `manifest.json` keeps the running total.

## Next steps

1. Run round 1:
   - Run `python tools/concept_art/wattlands_concept_art.py --dry-run` (or `py` instead of `python`), then run it again without the flag.
   - It needs `FAL_KEY` in the environment, which Simon sets in the desktop app's Local environment settings. Never print, log or commit the key.
2. Review round 1:
   - Look at every image yourself.
   - Note what works and what doesn't in `docs/concept/NOTES.md`: readability at a glance, how the riders read, and which style suits procedural low-poly Godot.
   - Then have Simon open `docs/concept/index.html`.
3. Cut with Simon to the final concepts and one style, then spend the rest of the budget (about $3.30) on round 2:
   - Round 2 can be Nano Banana Pro versions of the favourites (`--models nbpro --tag v2`), a gameplay mock-up per chosen mode, or a sheet for a rider, the tank or the boat.
   - Add new prompts to the script rather than making one-off calls, so every image can be reproduced.
4. Decide the packaging with Simon. There are two options:
   - one brief that builds every chosen mode, which is today's `docs/BRIEF.md`;
   - a platform brief plus one add-on brief per mode.
5. Settle the open questions in `docs/research.md`.
6. Update `docs/BRIEF.md`:
   - Make the changes: the 3.6 selection, the chosen style in 3.12 Presentation, and any spec changes.
   - Then have a fresh subagent review it for consistency: section references, governor limits against each mode's effort plan, the section 7 gates and the section 8 agent list.
7. Build, with Simon starting it in a fresh session:
   - Follow "Before you paste" in `docs/research.md`. The desktop app covers its CLI steps this way:
     - `.claude/settings.json` already sets the workflow size, and `/effort ultracode` replaces the `--effort` flag.
     - The Background tasks pane replaces `/workflows`.
   - Paste `docs/BRIEF.md`.
   - W0 of that run replaces this file, `README.md` and `.gitignore`. It keeps `.gitattributes`, `.claude/settings.json`, `docs/research.md`, `docs/concept/` and `tools/concept_art/`.

## Rules for this phase

- Don't turn on ultracode in this phase; it turns every task into a workflow. It's for the build session only.
- Art prompts describe original designs only. No brand names or logos (no Wahoo, Zwift or Strava), and no existing characters or game franchises.
- Commit images as JPEG, the script's default, to keep the repo small. `docs/concept/` is reference material for the build, not shipped content.
- Section 4.6 of the brief (the safety governor) outranks gameplay. Change a design to fit it, never the other way round.
