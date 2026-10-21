# GUT (Godot Unit Test) 9.7.1

- Upstream: https://github.com/bitwes/Gut
- Version: 9.7.1 (`addons/gut/plugin.cfg` says `version="9.7.1"`), the release for Godot 4.7.x (release branch `godot_4_7`, published 2026-07-10).
- Tag: `v9.7.1` (lightweight tag) -> commit `aeb5d4f3f7f0a6c9b5e178876d6c99b791fda605`.
- Archive: https://github.com/bitwes/Gut/archive/refs/tags/v9.7.1.zip, downloaded 2026-10-21, 1,118,303 bytes.
  - SHA-256: `14969aa46adc84aa08cdd21b9f6d1a64addd92ae60b36f02d0521ed305aa4086`
  - GitHub generates source archives on demand, so this hash may differ on a later download. The git tree hash below is the stable check.
- Git tree of `addons/gut` at the tag commit: `5d6893836af4917ee62b1a395125a7530b1f239d`. The vendored folder hashes to the same tree (259 files, all mode 100644), so it is byte-identical to upstream. Check after a commit with `git rev-parse HEAD:addons/gut`.
- License: MIT, Copyright (c) 2018 Tom "Butch" Wesley. Kept at `addons/gut/LICENSE.md` (SHA-256 `872fea6e72319f72e4ec0aa10bd7ec535ed3124bf2718bd8e0140e9adafef917`).
  - Bundled fonts (Anonymous Pro, Courier Prime, Lobster Two, used only by GUT's own GUI) are under the SIL Open Font License 1.1, kept at `addons/gut/fonts/OFL.txt` (SHA-256 `7284515a7e666096d0ba18e3273acc893723d258fbacc029da2a520da37facb4`).
- Vendored into: `addons/gut/`. Date: 2026-10-21.

## Kept and removed

- Kept: all of `addons/gut/` from the tag, unchanged: 259 files, including the upstream `*.uid` (87) and `*.import` (26) files.
- Removed: nothing. Upstream marks its tests, examples and docs `export-ignore`, so the tag's source archive holds only `addons/gut/`.
- Local modifications: none. Godot's imports leave the folder untouched (see the check below).

## Import and run check (2026-10-21)

Godot 4.7.2 .NET build (`4.7.2.stable.mono.official.ed1daf0bf`), run through `tools/godot.sh` on Windows 11 (Git Bash). Logs are in `build/vendor/` (gitignored scratch).

- Imports of the main checkout: a first headless import on a fresh `.godot` cache, an incremental one, and a second one on a fresh cache all exit 0 (about 4 s each) with no error or warning lines. GUT's 22 fonts and images and `source_code_pro.fnt` import cleanly, and its 87 `.uid` and 26 `.import` files are kept byte for byte: no file under `addons/gut/` is added or changed. Its tree, computed from the working copy after the imports and the runs below, is still `5d6893836af4917ee62b1a395125a7530b1f239d`.
- `-gdir=res://tests -ginclude_subdirs -gexit` against a `tests/` tree that holds only `.gitkeep` files:
  - prints `[GUT ERROR]:  Nothing was run.` and `On the one hand nothing failed, on the other hand nothing did anything.`, and no `Run Summary`;
  - exits **0**;
  - with `-gjunit_xml_file`, writes `<testsuites name="GutTests" failures="0" tests="0" >` with no suites, and prints `Results saved to <file>`.
  So the exit code alone cannot catch an empty run; `tools/run_tests` must keep the "Nothing was run", "Run Summary" and JUnit count checks (BRIEF 7). The real logs pass through `tools/lib/gut_gate.mjs`: the empty run fails on all three, a passing run passes, a failing run fails.
- A throwaway passing test (2 tests) exits 0 and prints `= Run Summary`, a Totals block (`Scripts 1`, `Tests 2`, `Passing Tests 2`, `Asserts 2`) and `---- All tests passed! ----`. JUnit: `<testsuites name="GutTests" failures="0" tests="2" >`, one `<testsuite>` per script with `tests`, `failures` and `skipped`, and one `<testcase ... status="pass">` per test.
- A throwaway failing test exits **1** and prints the failure twice (in the run and in the summary), `Failing Tests 1` and `---- 1 failing tests ----`. JUnit: `failures="1"` and a `<failure message="failed">` element with a CDATA body.
- GUT colours its console output with ANSI escapes even when stdout is a file or pipe (for example `ESC[31m[GUT ERROR]: ESC[0mNothing was run.`). Strip `ESC[...m` before matching whole lines, or pass `-gdisable_colors`. Substring checks for the five forbidden strings and "Run Summary" work either way.
- GUT's temporary output goes to `<checkout>/.userdata/Godot/app_userdata/Wattlands`, so the wrappers' per-checkout user dir applies to GUT runs.

## Binary files (SHA-256)

| File | SHA-256 |
| --- | --- |
| `fonts/AnonymousPro-Bold.ttf` | `886c150f2aa1d4b1cc23bce0b77d68ed36d5a42e0ff3f0e97748edd7623087c2` |
| `fonts/AnonymousPro-BoldItalic.ttf` | `a421794367245363a89fd2804a19969212ebd6a9cef076bb825accb39a27e121` |
| `fonts/AnonymousPro-Italic.ttf` | `c09b3b506b231b4e1a3b3b22e24420dbce85b7bebc74dc0f350caeb48f8b035e` |
| `fonts/AnonymousPro-Regular.ttf` | `4d5d383c044681a4d6552c3672c5b0c907eabc6ab0175565e0c81dac24fd7e26` |
| `fonts/CourierPrime-Bold.ttf` | `ff84d6ef4951db182c99c6b8a76c0bae0245c192994a032132b59f5c04392967` |
| `fonts/CourierPrime-BoldItalic.ttf` | `32cbf2f3729bd78a84008878aeac9abdf85f3f84dd196d012879abdcda5bffcd` |
| `fonts/CourierPrime-Italic.ttf` | `2f4cc8daf20a7127e2b2a314fbb20279021208b9abb8c38e54fc9b19caac6783` |
| `fonts/CourierPrime-Regular.ttf` | `16c3b24e173a21f23bdab9d50b5a49dc138e2b80789e010c7f29272b23e0634b` |
| `fonts/LobsterTwo-Bold.ttf` | `cfe79870da707a188578dea1816f452420916281530817dc47ceda096e4cefba` |
| `fonts/LobsterTwo-BoldItalic.ttf` | `97a658cde6909be3ed54c11fb337e10ed72201579d3b94ecff2ff9477b5a1605` |
| `fonts/LobsterTwo-Italic.ttf` | `5b4894780212918aaba1936a57f255c08da026c3bcc15d6343141030a29a2dc5` |
| `fonts/LobsterTwo-Regular.ttf` | `66ae53dcaad43a7de57cd3a1aa3fbc4e1b51623a317be9dc1f7e603118a301cb` |
| `gui/arrow.png` | `7f5a2f25d0cc68b8281bda24cdcd1d816e718d11fa0d050ede6cbad9033d17ed` |
| `gui/play.png` | `d4280462a7940ebaf184e2b92bd01a69cf09ae1c97b175ac92e1410d16ecf278` |
| `icon.png` | `17186e5c117662f093554ade93529a8f2927750362004e133acf3ded0afba45d` |
| `images/GutIconV2_base.png` | `4e9f0e37fb7cc5854622c7dacb7e801e05bf19aca76fdfff8c6b36a4a4ea320a` |
| `images/GutIconV2_no_shine.png` | `5c18b5fec79f125206545b71441d58b2e66f1f4c9d9b54535f3fcc47eff8b381` |
| `images/eyey.png` | `a129c7c3aa05794538b85a8ae12bee0c49513ebb31b8a8f3c17e5a2888b95da4` |
| `images/green.png` | `9137132eda912531252c215d698a604c401f2e59f8b29005117d72fef625ed75` |
| `images/red.png` | `e85d15987192029471051afc3b5de797629b95a5e02024fc5d14d81fdaf599bd` |
| `images/yellow.png` | `d3e42a49cde1baf9dd2647d62ca58399efeb94c2eec39b2b62450021532c08c3` |
| `source_code_pro.fnt` | `404094d0aae3de496a64fca1795bed8bd60c2411a3d992551f9e8f00789b71fe` |

## Use

Command-line runner only (BRIEF 7): `tools/godot.sh --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gjunit_xml_file=build/junit.xml`. The command-line runner does not need GUT's editor plugin, so `project.godot` does not enable it (it had no `[editor_plugins]` entry on 2026-10-21). Nothing in the shipped game loads GUT; the lead decides whether exports exclude `addons/gut/`.

## Updating

Download the new tag's archive, replace `addons/gut/` as a whole, compare `git rev-parse HEAD:addons/gut` with upstream's tree for `addons/gut` at the tag (`gh api "repos/bitwes/Gut/contents/addons?ref=<commit>"`), and update this file. Run a headless import on a fresh `.godot` cache and check that `addons/gut/` is unchanged. If a Godot import rewrites any vendored `*.import` or `*.uid` file, record it here as a local modification.
