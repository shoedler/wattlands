# Decisions: cleanup c5

## 2026-10-31: WlRecord and IntentRateLimiter replace the games' copies

- **Decision:** `WlRecord` (`addons/wattlands/sdk/wl_record.gd`) takes the bodies of `TankRecord`, `SiegeRecord` and `FishingRecord`, which stay as empty subclasses so no state type or caller changes. `IntentRateLimiter` (`addons/wattlands/sdk/intent_rate_limiter.gd`) takes `allow` and `_truthy` from Tank and Siege, which keep `filter` and `MAX_PER_S`. `load_dict` now returns `WlRecord`, so `TankState.load_dict` changes its annotation.
- **Alternatives:** delete the three game base classes and have 28 state types extend `WlRecord` directly; leave the copies.
- **Reason:** the three record bodies differed only in Siege's Vector3 arm and in Tank's `_load_array`. `WlRecord` has both: Siege's superset for the types, Tank's helper for the array loop, whose behaviour is the same as the inline form. Keeping the game names keeps the doc comments and `for r: TankRecord in records`-style typing as they are. No Tank or Fishing record declares a Vector3 (re-grepped on v4), so what they save is unchanged, and `behaviour_hash` matches the baseline on all ten scenarios.

## 2026-10-31: Fishing keeps its own rate limit

- **Decision:** `FishingGame._admit` is not moved to `IntentRateLimiter`.
- **Alternatives:** have it call `allow`.
- **Reason:** it counts in a tumbling one-second window per slot, not a sliding one, and it applies the summary intent in the same loop, so a swap would change which intents a burst keeps, and with them the rules' input. It is a candidate only if Fishing's behaviour is allowed to change, for example in a Fishing version bump.
