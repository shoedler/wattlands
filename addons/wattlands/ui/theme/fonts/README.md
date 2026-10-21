# Theme fonts

`WlTheme` uses Atkinson Hyperlegible (SIL Open Font License 1.1) when these two files exist here:

- `AtkinsonHyperlegible-Regular.ttf`
- `AtkinsonHyperlegible-Bold.ttf`

Without them it uses Godot's default font. The files were not downloaded in the W1 build (see `docs/decisions/ui-hud.md`). To add them, take both files and `OFL.txt` from the Google Fonts repository (`ofl/atkinsonhyperlegible/`) or the Braille Institute release, put them here, record the source, version and SHA-256 sums in `docs/deps.d/atkinson-hyperlegible.md` and the credit in `docs/credits.d/ui-hud.md`, then run `tools/godot.sh --headless --path . --import`. No code changes are needed.
