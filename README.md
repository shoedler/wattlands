# Wattlands

Wattlands is a multiplayer fitness party game for the Wahoo KICKR CORE smart trainer, planned for Godot 4.7. The repo is in its concept phase, so there's no game code yet.

- `docs/BRIEF.md` is the platform brief, the prompt for the first ultracode run. It builds the app, the trainer stack, multiplayer, rides and Strava, the Game SDK, the art pipeline and a reference game, Workout.
- `docs/games/` holds one brief per game (`siege.md`, `tank.md`, `fishing.md`). Each is pasted into its own session after the platform run, and adds that game to the same app.
- `docs/research.md` holds the research, concepts and decisions behind the brief. It also has the "Before you paste" setup checklist.
- `docs/concept/` holds the concept art. Open `index.html` there to compare the images side by side, and read `NOTES.md` for the review. `manifest.json` records every fal request, so each image can be regenerated with `FAL_KEY`.
- `.claude/settings.json` sets Opus 5.5, xhigh effort and the large workflow size for every session in this repo.

## Start on Windows with the Claude desktop app

1. Install the tools:
   - Git for Windows. Claude Code uses its Git Bash as the shell.
   - Python 3.12 or newer, for calling fal when making concept art.
   - For the build later: Node.js 22.12 or newer and Godot 4.7.2 (the standard build; a .NET build also runs the tests, but exports need standard export templates).
2. Unzip the repo to a folder outside OneDrive, such as `C:\dev\wattlands`. In that folder, run `git init`, `git add -A` and `git commit -m "Planning material"`.
3. Optionally, add these lines to `%USERPROFILE%\.claude\settings.json`. They apply to every project:
   - `"autoContinueAtUsageLimit": true` lets long runs wait out a usage limit.
   - `"permissions": {"defaultMode": "auto"}` makes Auto the default permission mode. Auto only takes effect from this user file, not from the repo's settings.
4. In the desktop app, open the Code tab. In the prompt box, open the environment dropdown, hover over **Local** and click the gear icon. Add `FAL_KEY` there.
5. Start a session: choose **Local**, pick this folder, choose Opus 5.5 and set the permission mode to Auto. Then send the kickoff message from the chat.
6. For the platform build, start a new session, run `/effort ultracode` and paste all of `docs/BRIEF.md`. Keep the PC awake until it finishes, then review the result and push it yourself.
7. Then build each game in its own new session the same way, pasting `docs/games/<id>.md`. For Tank Crew and Fishing, first add `WATTLANDS_ALLOW_ART=1` next to `FAL_KEY` in the Local environment, so the art pipeline can generate their sprites on fal; their briefs cap the spend.

`CLAUDE.md` lists the next steps for Claude Code. The original planning doc is on claude.ai: https://claude.ai/code/artifact/a5728927-63f6-4faf-be1f-d007622f96a5
