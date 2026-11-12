# tools/audio

The sound pipeline's tools: `generate.mjs` renders a bank's wavs, `scorecard.mjs` scores a bank, `preview.mjs` renders its preview, and `live_report.mjs` reads a recorded session. How a game's sound is made and proved is in `docs/AUDIO_PIPELINE.md`.

## Tests

`node --test` in this folder runs every test. `test/scorecard_banks.test.mjs` scores every bank on disk that has a preview block, each in its own worker thread, and prints one line per bank: `scored`, or `cached verdict, inputs unchanged`.

### The verdict cache

`tools/gate fast` runs the node suites with `WATTLANDS_TEST_CACHE_DIR` set to `build/test_cache`. With it set, a bank that passed is not scored again while nothing its scoring read has changed: every file it read (the bank JSON, its wavs, the real-wave reports it names, the shared bank), every folder it listed, every path it checked, every `.mjs` under `lib/` and the Node version. A change to any of them scores the bank again. A failing card is never kept, and a run that reads files in a way the cache can't follow keeps nothing. `lib/verdict_cache.mjs` has the details.

To score every bank afresh:

- delete `build/test_cache`, or
- run `tools/gate fast --games=all`, which runs the node suites without the cache, or
- run `node --test` here yourself: without `WATTLANDS_TEST_CACHE_DIR` nothing is cached.

Each run with the cache deletes the entries that no longer belong to a bank on disk or to the current scoring code.
