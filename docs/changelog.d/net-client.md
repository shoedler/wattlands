### Networking (net-client)

- `Protocol`: encode/decode for the relay envelope and every game message, required-field and type checks, schema-version rejection, int conversion (top-level ids, `*_id` keys at any depth, schema and `int_fields()` paths with `[]` and `{}`, peer-keyed dictionaries), exact round trips.
- `RelayTransport`: WebSocket client for the relay (hello, create/join, 15 s pings, error codes, drops with the reconnect token).
- `LoopbackTransport` and `LoopbackHub`: the relay's semantics in-process, for tests and simulations, with drop and latency fault injection.
- `WlNetSession`: host-authoritative lobby (slot looks, bots and bot FTP, ready-up with version checks, options and player options), offline SOLO lobby, routing rules, 16 KB limit, directive coalescing, telemetry intent caps, clock offset, snapshot buffer with interpolation, reconnect and rejoin, `session_in_progress`, graceful `host_left`.
- `NetRoster`: the 2 Hz roster builder; `LocalRelayServer`: the relay protocol served by Godot.
- `docs/PROTOCOL.md`: the relay protocol, every game message, int conversion, versioning, reconnect and limits.
