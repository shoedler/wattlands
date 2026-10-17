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
- `docs/concept/` holds the concept art and `NOTES.md`, the review of it. `manifest.json` records each image's full fal request (endpoint, prompt, size, quality), request id and estimated cost, so any image can be regenerated. `index.html` is the contact sheet.
  - There's no generator script in the repo any more; Simon had it removed after round 1. New images come from direct calls to fal, and every request goes into `manifest.json`.
- `.claude/settings.json` sets Opus 5.5, xhigh effort and the large workflow size guideline for every session in this repo.
- `.gitattributes` keeps LF line endings, so bash scripts keep working in Git Bash.

## Where things stand (18 Oct 2026)

- Shortlist: Generator Siege, Tank Crew and Big Game Fishing. Kart Rush stays in the brief as P2 notes.
- Dropped ideas. Don't revive any of them without asking:
  - Boss Raid, because WATTGAMES already does interval boss fights.
  - Ramp Tower and Tug-of-War, because they're too thin.
  - Paceline TTT, because Zwift covers it.
  - Pedal Survivors, Track Night and Stealth Heist.
- Art direction, from Simon after round 1 (round 1 has been removed from the repo):
  - Generator Siege: a low-poly 3D miniature with simple primitives and tilt-shift. It's set in an alternate-history Roman fort powered by spinning machines (treadwheels driving a bronze flywheel generator with a watt readout). Enemies are realistic but not detailed. People are tiny, with no close-up riders.
  - Tank Crew: 2D pixel art in a dark, oily alternate 1940s. Brutalist super-heavy tanks are shown with an x-ray cutaway of moving machinery. Each task has its own crude engine (diesel, electric, steam), there's one tank layout each for 1, 2 and 3 players, the enemies are tanks, and no people are drawn.
  - Big Game Fishing: 2D pixel art in a split screen, with one horizontal lane per player.
- Round 2 is 7 images from GPT Image 2.5 Sunburst on fal (`openai/gpt-image-2.5/sunburst/text-to-image`, 1536 × 864, high quality), reviewed in `docs/concept/NOTES.md`.
- fal budget: about $5 in total. Round 1 cost $1.68 and round 2 an estimated $0.49 (this key can't read actual usage), so about $2.83 is left.

## Next steps

1. Review round 2 with Simon: `docs/concept/NOTES.md` and `docs/concept/index.html`.
2. If Simon wants a round 3, spend part of the remaining budget (about $2.83) on it. NOTES.md lists prompt fixes. Call fal directly and add every request to `manifest.json`, with its endpoint, full input, request id and estimated cost.
   - `FAL_KEY` is in Simon's Windows user environment, not in this app's session environment. Read it from there for the one process that needs it. Never print, log or commit it.
   - On Windows, Python can't verify fal's image CDN with the system store alone. Load Git for Windows' CA bundle (`C:\Program Files\Git\usr\ssl\certs\ca-bundle.crt`) into the SSL context. fal bills on completion even when the download fails; a lost result can be found again with `GET https://api.fal.ai/v1/models/requests/by-endpoint?expand=payloads`.
3. Decide the packaging with Simon. There are two options:
   - one brief that builds every chosen mode, which is today's `docs/BRIEF.md`;
   - a platform brief plus one add-on brief per mode.
4. Settle the open questions in `docs/research.md`, plus a new one: how an autonomous agent should make 2D pixel art for Tank Crew and Fishing without licensing risk.
5. Update `docs/BRIEF.md`. The "What changes in the brief" section of NOTES.md lists the changes:
   - 3.6 selection;
   - 3.12 Presentation: Siege in low-poly 3D, Tank and Fishing in 2D pixel art;
   - the Siege reskin in 3.7;
   - engine rooms and tank enemies in 3.8;
   - fishing lanes in 3.9;
   - the section 1 file list, because `tools/concept_art/` is gone.

   Then have a fresh subagent review it for consistency: section references, governor limits against each mode's effort plan, the section 7 gates and the section 8 agent list.
6. Build, with Simon starting it in a fresh session:
   - Follow "Before you paste" in `docs/research.md`. The desktop app covers its CLI steps this way:
     - `.claude/settings.json` already sets the workflow size, and `/effort ultracode` replaces the `--effort` flag.
     - The Background tasks pane replaces `/workflows`.
   - Paste `docs/BRIEF.md`.
   - W0 of that run replaces this file, `README.md` and `.gitignore`. It keeps `.gitattributes`, `.claude/settings.json`, `docs/research.md` and `docs/concept/`.

## Rules for this phase

- Don't turn on ultracode in this phase; it turns every task into a workflow. It's for the build session only.
- Art prompts describe original designs only. No brand names or logos (no Wahoo, Zwift or Strava), and no existing characters or game franchises. The 1940s tank art carries no flags, insignia or national markings.
- Commit images as JPEG to keep the repo small. `docs/concept/` is reference material for the build, not shipped content.
- Section 4.6 of the brief (the safety governor) outranks gameplay. Change a design to fit it, never the other way round.
