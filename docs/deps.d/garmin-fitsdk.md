# @garmin/fitsdk 21.218.0 (tools/fit_check only)

- What: Garmin's FIT JavaScript SDK, used by `tools/fit_check/check.mjs` to decode and check every FIT file the tests and simulations write (BRIEF 3.8, 7.5): `Decoder.isFIT`, `checkIntegrity`, `read`, and the enum names in `Profile.types`. The tests in `tools/fit_check/test/` also use its `Encoder` to build fixtures.
- Upstream: https://github.com/garmin/fit-javascript-sdk (npm package `@garmin/fitsdk`).
- Version: `21.218.0`, pinned exactly in `tools/fit_check/package.json` and `tools/fit_check/package-lock.json` (profile version 21.218).
- Tarball: `https://registry.npmjs.org/@garmin/fitsdk/-/fitsdk-21.218.0.tgz`, 166,996 bytes, downloaded 2026-10-21.
  - SHA-256: `779833051c4040741fffe1da7f7fe4c266b255b06a618121c7643064b60be7c1`
  - npm integrity (in the lockfile): `sha512-Jbhedp3AJ/xJBSuiPBlPpwH5QISXd+GYtfnAUZ3u68hUqkzHiRWUhla8xj4tW/05w6gKsErEt+7GQCFap+a2kQ==`
- Dependencies: none (the lockfile holds this one package).
- License: "SEE LICENSE IN LICENSE.txt", Garmin's Flexible and Interoperable Data Transfer (FIT) Protocol License Agreement (`node_modules/@garmin/fitsdk/LICENSE.txt`, SHA-256 `6cc7ff94b5afc8c3a2b14aeb3e90da97a9fb6c8d40644304da94df5cf56428cf`). It is not an open-source license: a non-exclusive, royalty-free licence to use the SDK internally and the FIT protocol in our software, with no redistribution of the SDK itself and a requirement to follow the FIT protocol.
- How it's used: installed with `npm ci --prefix tools/fit_check` into `tools/fit_check/node_modules/`, which is gitignored (and `tools/fit_check/` has a `.gdignore`). It is never vendored, committed, shipped with the game or loaded by Godot. The game's own FIT encoder (`addons/wattlands/rides/fit_encoder.gd`) is written from the FIT protocol and shares no code with the SDK.
- Fallback: if npm is blocked, `check.mjs` runs the GDScript decoder (`tools/fit_decode/decode.gd`, qa) through `tools/godot.sh` (contract in `tools/fit_check/README.md`).
- Updating: change the version in `package.json`, run `npm install --save-exact --prefix tools/fit_check`, commit both files, re-run `node --test` in `tools/fit_check` and the rides GUT tests, and update this file (hashes from `npm pack @garmin/fitsdk@<version>`).
