class_name FishingRecord
extends WlRecord
## Base of Fishing's plain-data state types (G0 contract; a Vector2 holds [x, z]). Fixtures and
## debugging use it; the 10 Hz snapshot is FishingSnapshot's compact integer form
## (src/games/fishing/net/), not this.
