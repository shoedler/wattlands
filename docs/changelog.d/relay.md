# Changelog: relay

- **The relay caps what one address, and the whole relay, can hold.** 500 sockets (64 per address), 200 rooms (8 per address), 10 room creates a minute per address, and 10 seconds for a new socket to say hello. Each has a flag and an environment variable, and 0 turns it off. A socket over a cap is refused before the handshake; a create over a room cap gets `rate_limited`. Eight riders behind one router, a host that drops and takes its room back, and the end-to-end run are nowhere near them.
- **WebSocket ping and pong frames no longer keep a socket alive.** Only a message to the relay does, and the app sends one every 15 seconds.
- **Behind a proxy the relay reads the right address.** `RELAY_TRUST_PROXY=1` takes the last `X-Forwarded-For` entry, a larger number takes that many from the right, and `fly` takes `Fly-Client-IP`. The old setting took the first entry, which a client could write itself. A typo in the setting is now an error at start.
- **`server/relay/README.md` covers running it for friends and in public,** with the limits, the proxy settings for Fly and Render, and why `wss://` matters.
