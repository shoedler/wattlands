# ws 8.22.0 (relay WebSocket layer)

- Upstream: https://github.com/websockets/ws (npm package `ws`).
- Version: 8.22.0, published to npm on 2026-09-26. Its `gitHead` is `297202cdae9b0590629821373b3b679c407f3431`.
- Tarball: https://registry.npmjs.org/ws/-/ws-8.22.0.tgz, 35,094 bytes, fetched 2026-10-21 with `npm pack ws@8.22.0`.
  - SHA-256: `ca9b3798b2e11ce8fac6713f50ef0501aa12b09b330623c1dc409dff94e7abc8`
  - npm integrity (pinned in `server/relay/package-lock.json`): `sha512-Ydggc987+RO0AnWtZ/7Wq9FtNvcrL1b/RO0ud9mWjUPgDrsAAwQSF51sm2hm1XofbU/4jkpGEsLFsZZxU+1DOg==`
- License: MIT. The copyright holders are Einar Otto Stangvik (2011), Arnout Kazemier and contributors (2013), and Luigi Pinca and contributors (2016). The license is shipped in the package as `LICENSE`, with SHA-256 `2b29dcfe0d6471f7e8c92c5fb38c9f93edee10330937055440192f1832b1ecef`.
- Dependencies: none. Its optional peer dependencies `bufferutil` and `utf-8-validate` are not installed.
- Where: `server/relay/package.json` (exact version) and `package-lock.json`. The package is installed by `npm ci` into `server/relay/node_modules/` (gitignored) and isn't vendored. The Docker image runs `npm ci --omit=dev`.
- Used for: the relay's preferred WebSocket layer (BRIEF 5.3). It is optional at runtime: when `import('ws')` fails, the relay uses its own RFC 6455 server (`server/relay/src/ws_builtin.ts`). `RELAY_WS_IMPL=builtin` forces that server. The relay suites run against both layers and skip the `ws` half when it isn't installed (`RELAY_REQUIRE_WS=1` turns that skip into a failure, as in CI).
- Configuration: `noServer`, `maxPayload` 16384, `perMessageDeflate` off, UTF-8 validation on, no subprotocol selected.
