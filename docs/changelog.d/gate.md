- Contributors: `tools/gate fast` uses more of your machine, runs only the GUT tests a game-only change can reach, and `tools/gate wait` follows a gate you started in the background. `tools/gate fmt` takes seconds.

- For contributors: `tools/gate fast` now runs the Node suites, the simulations and the static checks side by side, and runs only the Node suites your change can reach. `node tools/e2e/faults.mjs --jobs=6` plays the multiplayer fault scenarios six at a time.

- For contributors: `tools/gate wait --for=fast` reports only the verdict of the gate you started, for the tree you have now, and exits 4 with the reason when there is none. `check` stops one game's code from naming another game's files, classes or text keys. The gates size themselves to smaller machines, and the built-in relay fault scenarios no longer trip over each other when run side by side.
