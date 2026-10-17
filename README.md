# Wattlands

Wattlands is a multiplayer fitness party game for the Wahoo KICKR CORE smart trainer, planned for Godot 4.7. The repo is in its concept phase, so there's no game code yet.

- `docs/BRIEF.md` is the build prompt for the one-shot ultracode run.
- `docs/research.md` holds the research, concepts and decisions behind the brief. It also has the "Before you paste" setup checklist.
- `docs/concept/` holds the concept art. Open `index.html` there to compare the images side by side.
- `tools/concept_art/` has the art generator, which needs `FAL_KEY`. Start with `python tools/concept_art/wattlands_concept_art.py --dry-run`, which shows the plan and cost without spending anything.
- `.claude/settings.json` sets Opus 5.5, xhigh effort and the large workflow size for every session in this repo.

## Start on Windows with the Claude desktop app

1. Install the tools:
   - Git for Windows. Claude Code uses its Git Bash as the shell.
   - Python 3.12 or newer, for the art script.
   - For the build later: Node.js 22.12 or newer and Godot 4.7.2.
2. Unzip the repo to a folder outside OneDrive, such as `C:\dev\wattlands`. In that folder, run `git init`, `git add -A` and `git commit -m "Planning material"`.
3. Optionally, add these lines to `%USERPROFILE%\.claude\settings.json`. They apply to every project:
   - `"autoContinueAtUsageLimit": true` lets long runs wait out a usage limit.
   - `"permissions": {"defaultMode": "auto"}` makes Auto the default permission mode. Auto only takes effect from this user file, not from the repo's settings.
4. In the desktop app, open the Code tab. In the prompt box, open the environment dropdown, hover over **Local** and click the gear icon. Add `FAL_KEY` there.
5. Start a session: choose **Local**, pick this folder, choose Opus 5.5 and set the permission mode to Auto. Then send the kickoff message from the chat.
6. For the build itself, start a new session, run `/effort ultracode` and paste all of `docs/BRIEF.md`. Keep the PC awake until it finishes.

`CLAUDE.md` lists the next steps for Claude Code. The original planning doc is on claude.ai: https://claude.ai/code/artifact/a5728927-63f6-4faf-be1f-d007622f96a5
