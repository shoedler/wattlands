# server/mock_strava

A mock of Strava's OAuth and upload API for tests (BRIEF 3.8, 7.5, 7.6). Zero-dependency Node on `node:http`. Never point a real client secret at it, and never point the game at the real Strava from a test.

```
node server/mock_strava/server.mjs [--port=0] [--host=127.0.0.1] [--port-file=<path>]
     [--client=<id>:<secret>]... [--processing-polls=<n>] [--now=<unix s>] [--parent-pid=<pid>] [--quiet]
```

- Once listening it prints `MOCK_STRAVA_PORT <port>` (then a human-readable line) and writes the port to `--port-file` (via a temp file and a rename, so a reader never sees a partial file).
- One base URL serves both halves: OAuth under `/oauth/*`, the API under `/api/v3/*`. Start the game with `--strava-base=http://127.0.0.1:<port>` (WlRides maps it to `<base>/api/v3` and `<base>/oauth`).
- Default client: id `12345`, secret `mock-client-secret` (`--client` replaces it; repeat for more).
- `--now` freezes the clock at a Unix time (default: real time); `/admin/clock` moves it.
- `--parent-pid` exits when that process is gone (GUT runs and harnesses pass their own pid).
- It never logs tokens, codes or secrets (with `--quiet` it logs nothing but the start lines).

## Endpoints

| Route | Behaviour |
| --- | --- |
| `GET /oauth/authorize` | Checks `client_id`, `response_type=code`, a loopback `redirect_uri` and `scope` containing `activity:write`, then redirects (302) straight to `redirect_uri?state=...&code=...&scope=read,<scopes>` |
| `POST /oauth/token` | Form or JSON. `grant_type=authorization_code` (single-use code, client secret checked) or `refresh_token`. Returns `{token_type, access_token, refresh_token, expires_at, expires_in}` (plus `athlete` for a code). Access tokens last 6 h on the mock's clock; each refresh rotates the refresh token and the old one stops working. Bad code or refresh token: 400; bad client: 401 |
| `POST /oauth/revoke` | HTTP Basic `client_id:client_secret`, form `token=<refresh or access token>`; revokes the whole grant. 200 (also for unknown tokens, RFC 7009); 401 without valid client auth |
| `POST /oauth/deauthorize` | Strava's older revoke: Bearer access token in the Authorization header; revokes the grant. 200, or 401 without a valid token |
| `POST /api/v3/uploads` | Bearer token in the Authorization header only (a token in the query or body gets 401). Multipart `file`, `data_type` (`fit`, `fit.gz`, `tcx`, ...), `trainer`, `name`, `description`, `external_id`. 201 `{id, id_str, external_id, error: null, status: "Your activity is still being processed.", activity_id: null}` |
| `GET /api/v3/uploads/:id` | Processing for `processing_polls` polls (default 1), then ready with an `activity_id`; a FIT that fails the header/CRC check ends with `error: "Improperly formatted data."`; an `external_id` that already has an activity ends with `error: "<file> duplicate of activity <id>"` |
| `GET /api/v3/athlete` | The athlete; `ftp` and `weight` only with the `profile:read_all` scope |

## Admin API (tests only)

| Route | Body | Effect |
| --- | --- | --- |
| `GET /admin/state` | | `{now, uploads, grants, active_grants, faults, processing_polls}` |
| `POST /admin/clock` | `{now?, advance_s?}` | Set or move the clock |
| `POST /admin/fault` | `{route, status, count?, retry_after?, location?, tamper_state?, scope?}` | The next `count` (default 1) requests to `route` (`authorize`, `token`, `revoke`, `deauthorize`, `upload`, `upload_status`, `athlete`, `*`) get `status`: 401 (auth error), 429 (rate limit, with `X-RateLimit-*` and optional `Retry-After`), 5xx. With `location`, a redirect there instead. An `authorize` fault with 403 redirects with `error=access_denied`; one with `tamper_state: true` redirects with a changed `state`; one with `scope: "<scopes>"` grants only those scopes (a rider who unticked a permission) |
| `POST /admin/config` | `{processing_polls?, athlete?}` | Processing length; athlete fields |
| `GET /admin/uploads` | | Every upload: `external_id`, `filename`, `data_type`, `trainer`, `name`, `description`, `bytes`, `sha256`, `fit_valid`, `fit_error`, `status`, `error`, `activity_id`, ... |
| `GET /admin/requests` | | Every non-admin request: `{t, method, path, route, auth ("bearer", "basic" or null), token_in_query, status}` (never a token) |
| `POST /admin/reset` | | Forget codes, grants, tokens, uploads, faults and the request log |

## Tests

`node --test` in `server/mock_strava` (no npm install). The Godot tests in `tests/rides/` start this server with `OS.create_process("node", [...])` and kill it when they finish.
