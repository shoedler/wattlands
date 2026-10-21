# Decisions

Short ADRs (date, decision, alternatives, reason). Agents and game sessions write fragments in `docs/decisions/<agent or game id>.md`; the lead merges platform fragments here. Game sessions keep theirs in `docs/decisions/<id>.md` only.

## From the concept phase (17-18 Oct 2026, moved here from the planning CLAUDE.md and README)

- Shortlist: Generator Siege, Tank Crew and Big Game Fishing. Kart Rush stays in the backlog (BRIEF 3.12) as P2 notes.
- Dropped ideas, not to be revived without asking Simon: Boss Raid (WATTGAMES already does interval boss fights), Ramp Tower and Tug-of-War (too thin), Paceline TTT (Zwift covers it), Pedal Survivors, Track Night and Stealth Heist.
- Packaging: one platform brief, then one session per game. Everything lives in this repo as one app with a game picker.
- Art direction (after concept round 1):
  - Generator Siege: a low-poly 3D miniature with simple primitives, in an alternate-history Roman fort powered by treadwheels driving a bronze flywheel generator with a watt readout. Enemies are realistic but not detailed; people are tiny, with no close-up riders. Four treadwheels, one per player.
  - Tank Crew: 2D pixel art in a dark, oily alternate 1940s, brutalist super-heavy tanks in x-ray cutaway with one crude engine per task (diesel, electric, steam), one tank layout each for 1, 2 and 3 players, enemy tanks only, no people.
  - Big Game Fishing: 2D pixel art in a split screen, one horizontal lane per player.
- 2D pixel art (Tank Crew, Fishing): whatever is fastest and looks good. The platform's `tools/art` generates sprites on fal with GPT Image 2.5, then pixelates them to a fixed palette and animates them by parts.
- Concept art: round 2 is 7 images from GPT Image 2.5 Sunburst on fal (1536 x 864, high quality), reviewed in `docs/concept/NOTES.md`; every request is in `docs/concept/manifest.json`. About $2.83 of the $5 concept-art budget is left; Simon adds fal credits for the games' art.
- Art prompts describe original designs only: no brand names or logos (no Wahoo, Zwift or Strava), no existing characters or franchises, and no flags, insignia or national markings on the 1940s tank art.
- `docs/concept/` is reference material for the build, not shipped content; images are committed as JPEG.
- Toolchain choices baked into the brief (see `docs/research.md`, "Decisions baked into the prompt"): Godot 4.7.2 with GDScript and the Compatibility renderer; GDBLE for Bluetooth with a Python bridge as fallback; host-authoritative multiplayer through a small Node relay with room codes; % of FTP fairness by default; FIT export and optional upload to each rider's own Strava API app; GUT 9.7.1 with strict pass rules; procedural or pipeline-generated art, an OFL font and CC0 or synthesized audio.

## Platform build (W0-W4, from 21 Oct 2026)

Merged from `docs/decisions/*.md` platform fragments. See `docs/decisions/lead.md` for the lead's decisions; the module fragments follow as they are merged.
