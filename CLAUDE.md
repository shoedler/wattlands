# Wattlands: concept phase

Wattlands is a multiplayer fitness party game for the Wahoo KICKR CORE smart trainer. It will be built in Godot 4.7 by a single autonomous ultracode run.

This repo holds the planning material and has no game code yet. The concept phase is wrapping up: concept art round 2 is done, and the build briefs (one platform brief, three game briefs) are written and reviewed.

Simon works on Windows in the Claude desktop app. That matches the brief's Windows-first target.

## What Simon asked for

- A KICKR CORE game built in Godot, using ERG mode wherever it makes the game better.
- Pedaling comes first. An Xbox controller or light keyboard use is optional, and every mode must be playable with no input at all.
- Multiplayer from the start: a host shares a short code, friends type it in, and there are no accounts.
- Rides upload to Strava.
- Concepts are judged on fun and on endurance and training effect.

## Files

- `docs/BRIEF.md` is the platform brief, the prompt for the first ultracode run. It starts with the word ultracode.
  - That run builds the app shell, the trainer stack and safety governor (4.6), multiplayer, rides/FIT/Strava, the Game SDK (3.6), the 2D and 3D presentation kits (3.9), the fal art pipeline (3.10) and a reference game, Workout (3.7).
  - Edit this file, never a copy of it.
- `docs/games/siege.md`, `docs/games/tank.md` and `docs/games/fishing.md` are the game briefs. Each also starts with ultracode and is pasted into its own session after the platform run. That session adds one game under `src/games/<id>/` in this repo, on branch `game/<id>`.
  - They cite platform sections as "BRIEF x.y" and use the SDK's exact names, so change the platform brief and the game briefs together.
- `docs/research.md` is a 17 Oct 2026 snapshot of the planning doc. It covers:
  - trainer facts and existing products,
  - the four concepts with fun and training pros and cons,
  - decisions, the "Before you paste" setup checklist, open questions and sources.
- `docs/concept/` holds the concept art and `NOTES.md`, the review of it. `manifest.json` records each image's full fal request (endpoint, prompt, size, quality), request id and estimated cost, so any image can be regenerated. `index.html` is the contact sheet.
  - There's no generator script in the repo any more; Simon had it removed after round 1. New images come from direct calls to fal, and every request goes into `manifest.json`.
- `.claude/settings.json` sets Opus 5.5, xhigh effort and the large workflow size guideline for every session in this repo.
- `.gitattributes` keeps LF line endings, so bash scripts keep working in Git Bash.

## Where things stand (18 Oct 2026)

- Shortlist: Generator Siege, Tank Crew and Big Game Fishing. Kart Rush stays in the platform brief's backlog (3.12) as P2 notes.
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
- fal budget for concept art: about $5. Round 1 cost $1.68 and round 2 an estimated $0.49 (this key can't read actual usage), so about $2.83 is left. Simon can add fal credits for the games' art.
- Decisions from 18 Oct 2026:
  - Packaging: one platform brief, then one session per game. Everything lives in this repo as one app with a game picker.
  - 2D pixel art (Tank Crew, Fishing): whatever is fastest and looks good. The platform's `tools/art` generates sprites on fal with GPT Image 2.5, then pixelates them to a fixed palette and animates them by parts.
  - Generator Siege uses the four-treadwheel layout, one wheel per player.

## Next steps

1. Go over the briefs with Simon and flag the judgment calls the game briefs made:
   - In Tank Crew, the multi-crew diesel rides ERG 90% at gun lines ("Dig in").
   - In Fishing, marlin jumps stop at 104% FTP, because BRIEF 4.6.1 caps phases longer than 300 s (an open-ended phase counts at its `max_s`) at 105%. A lost fish is replaced by one of the same species, so a snapped line never costs the planned interval.
   - Every brief has new names for content (forts, tanks, missions, currencies).
2. Build the platform, with Simon starting it in a fresh session:
   - Follow "Before you paste" in `docs/research.md`. The desktop app covers its CLI steps this way:
     - `.claude/settings.json` already sets the workflow size, and `/effort ultracode` replaces the `--effort` flag.
     - The Background tasks pane replaces `/workflows`.
   - Godot: Simon's install is the .NET build. Point `GODOT` at its `_console.exe` (fine for running and testing GDScript), or install the standard 4.7.2 build for exports.
   - Paste `docs/BRIEF.md`.
   - W0 of that run replaces this file, `README.md` and `.gitignore`. It keeps `.gitattributes`, `.claude/settings.json`, `docs/research.md`, `docs/games/` and `docs/concept/`. The run commits locally and never pushes; Simon reviews and pushes.
3. Build each game in its own fresh session after the platform run, in any order:
   - For Tank Crew and Fishing, first add `FAL_KEY` and `WATTLANDS_ALLOW_ART=1` to the desktop app's Local environment, so the art pipeline can call fal. Their briefs cap the art spend; Siege needs no fal art.
   - Run `/effort ultracode` and paste `docs/games/<id>.md`.

For more concept art in the meantime, call fal directly and add every request to `docs/concept/manifest.json` (endpoint, full input, request id, estimated cost):
- `FAL_KEY` is in Simon's Windows user environment, not in this app's session environment. Read it from there for the one process that needs it. Never print, log or commit it.
- On Windows, Python can't verify fal's image CDN with the system store alone. Load Git for Windows' CA bundle (`C:\Program Files\Git\usr\ssl\certs\ca-bundle.crt`) into the SSL context.
- fal bills on completion even when the download fails. A lost result can be found again with `GET https://api.fal.ai/v1/models/requests/by-endpoint?expand=payloads`.

## Rules for this phase

- Don't turn on ultracode in this phase; it turns every task into a workflow. It's for the build session only.
- Art prompts describe original designs only. No brand names or logos (no Wahoo, Zwift or Strava), and no existing characters or game franchises. The 1940s tank art carries no flags, insignia or national markings.
- Commit images as JPEG to keep the repo small. `docs/concept/` is reference material for the build, not shipped content.
- Section 4.6 of the platform brief (the safety governor) outranks gameplay in every brief. Change a design to fit it, never the other way round.
