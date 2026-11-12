- Contributors: `tools/gate fast` uses more of your machine, runs only the GUT tests a game-only change can reach, and `tools/gate wait` follows a gate you started in the background. `tools/gate fmt` takes seconds.

- For contributors: `tools/gate fast` now runs the Node suites, the simulations and the static checks side by side, and runs only the Node suites your change can reach. `node tools/e2e/faults.mjs --jobs=6` plays the multiplayer fault scenarios six at a time.
