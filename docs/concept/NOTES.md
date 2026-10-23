# Concept art notes: round 2

18 Oct 2026 · reviewed by Claude, for Simon and for the build

Round 2 follows Simon's new direction after round 1, which has since been removed from the repo:
- **Generator Siege:** a low-poly miniature of an alternate-history Roman fort that runs on spinning power.
- **Tank Crew:** 2D pixel art of brutalist super-heavy tanks in an alternate 1940s, with no people.
- **Big Game Fishing:** 2D pixel art in a split screen with one lane per player.

The seven round-2 images (four remain after the tank images were removed) come from OpenAI's GPT Image 2.5 Sunburst on fal, at 1536 × 864 and high quality. The estimated cost is $0.49, based on fal's historical average of $0.07 an image; this key can't read actual usage. With round 1's $1.68, about $2.17 of the $5 budget is spent. `manifest.json` records each image's full request, so any image can be regenerated.

## Generator Siege

| Image | What works | What doesn't |
| --- | --- | --- |
| [siege_roman_treadwheel](siege_roman_treadwheel.jpg): one giant treadwheel | It reads as a tabletop miniature, with tilt-shift, faceted hills, rocks and cypress trees, and tiny people. One huge wooden wheel dominates the fort. Two chain shafts run from sprockets near its rim to the hub of a bronze flywheel, and a plaque above reads "1250 W". Chains run along the walls to the ballista on the left corner tower and through the bolt thrower's tower, and a separate chain crosses the courtyard to the onager. Enemies climb three roads: barbarian war bands with round shields, a ram under a roof and a siege tower. | The workers stand on slats all round the wheel, top included, like figures on shelves, instead of walking at the bottom as in a real treadwheel. There's only one ballista, though the prompt asked for two. The fort walls have stone blocks and crenellations, which is more detail than simple primitives. The readout is a plaque above the generator, not part of the spinning drum. Red banners carry a gold laurel emblem, though the prompt allowed no text but the readout. The horned helmets are a fantasy cliché. |
| [siege_roman_four_wheels](siege_roman_four_wheels.jpg): four treadwheels, one per player | Four smaller treadwheels with red, blue, yellow and green pennants ring a central bronze drum generator. Each one drives it through its own shaft and gears, and one to three workers walk at the bottom of each, as in a real treadwheel. A rolling-drum counter on top reads "1250W", so you can see each player's power join one machine. The enemy types and the three roads repeat the other image. Here the siege tower is on the right road, the helmets have no horns, and most towers have tiled roofs. | The wheels are small, so the workers inside are tiny, though their white tunics still read. The counter has no space before the W. The red Roman banners repeat the gold laurel emblem, and three black enemy banners carry a white horned bull skull. |

**Pick:** the four-wheel layout. It maps one wheel to each player, and its workers walk inside the wheels the way the rider pedals. A player's wheel can spin faster as their watts rise, and the pennant color identifies the player from 3 m. The single-wheel image has the clearer view of the hill and the roads.

**Readout:** GPT Image 2.5 drew a legible readout both times: "1250 W" on a flat plaque and "1250W" on the drum counter. In round 1, Nano Banana 2 painted words such as "SCRAP ROCKET" despite the no-text rule, while FLUX 3 drew no legible text.

## Tank Crew (now Diesel Domestiques)

The three pixel-art tank images were removed on 23 Oct 2026: the game's look changed to a dark, desaturated 2.5D diorama with depth of field and glowing lights. `docs/games/tank.md` section 3 holds the new direction; there are no reference images for it.

## Big Game Fishing

| Image | What works | What doesn't |
| --- | --- | --- |
| [fishing_split_2p](fishing_split_2p.jpg): 2 lanes | Two stacked lanes with red and blue borders. Each is a side-view slice: a boat on the left, the sea surface, then a deep cross-section with reef and light rays. Top lane: a tuna pulls deep, down by the reef, while gulls work a bait ball over a big school of bait fish. Bottom lane: a marlin leaps in a burst of spray above a few scattered billfish. The line from rod to fish shows the fight instantly. | The anglers sit at a big reel on a stand, holding the rod. No bicycle is visible, though the prompt asked for one. |
| [fishing_split_4p](fishing_split_4p.jpg): 4 lanes | Four lanes in red, blue, yellow and green, with boats, canopies, pennants and shirts to match. Three anglers wear caps in their lane color and the yellow-lane angler a tan sun hat. The lanes show a mackerel at the surface, a mahi-mahi on a run, a tuna deep down and a marlin leaping. It's still readable with four players at 1536 × 864. | No bike again. The model drew uneven lanes, from about 180 px (red) to about 260 px (yellow); the game would use equal lanes (216 px each at this size, 270 px at 1080p). Reef or cliffs fill the right edge of every lane, leaving only a strip of open water between the fish and the rocks. The boats are identical apart from color, which is good for fairness but leaves no room for cosmetics yet. |

**What the set suggests for the game:**
- **Each lane can show the fight state through position.** The fish's depth and its distance from the boat can track the fight: it sounds deep on a run and comes in toward the boat as it tires. The landing sprint starts when it reaches the boat.
- **Keep the right side of each lane clear for the HUD:** the tension band, the strain and slack meters, and the watt and cadence numbers. The model filled that area with rocks, so the prompt and the game layout should reserve it.

## What changes in the brief

These changes went into the briefs on 18 Oct 2026: `docs/BRIEF.md` is now the platform brief, and each game has its own brief in `docs/games/`. The notes below are kept as the reasoning behind them.

- **3.12 Presentation** assumes procedural low-poly 3D for every mode. Siege stays 3D. Tank Crew and Fishing are now 2D pixel art, so the brief needs a pixel-art approach that an autonomous agent can build without licensing risk. Options include:
  - sprites drawn in code;
  - simple 3D or 2D shapes rendered at low resolution with nearest-neighbor filtering;
  - generated sprite sheets.

  This is an open question.
- **3.7 Generator Siege** needs a reskin:
  - Dynamo → a Roman flywheel generator;
  - pedal huts → treadwheels, one per player;
  - Arc Coil, Spoke Ballista and Headwind Fan → for example ballista, bolt thrower and onager;
  - scrap enemies → war bands, rams and siege towers.

  The brief's slowing fan tower needs a Roman equivalent, and so does the flying Spoke Wasp.
- **3.8 Tank Crew** draws no riders: seats become engine rooms, and the enemies become tanks. A solo rider gets a one-engine tank rather than AI crew in empty seats. The shared `src/combat` scrap-machine enemies no longer fit both Siege and Tank Crew. The combat code can still be shared, but the content differs.
- **3.9 Big Game Fishing** gets a lane per player instead of one shared boat. The shared catch board and the Double Hookup bonus still work across lanes.
- **Section 1** lists `tools/concept_art/`, which no longer exists.

## Prompt fixes for next time

- **Siege:** "no banners, flags with symbols or emblems", "the readout is part of the generator's spinning drum", and "plain block walls without masonry detail".
- **Fishing:** "the angler sits on a stationary bicycle and pedals; the bicycle's chain visibly turns the reel".
- **Tank:**
  - "Chunky pixel art with large pixels and fewer colors, suitable for sprite animation", if we want something closer to what the game could ship.
  - "Each engine connects to its job with a visible shaft or chain: diesel to the tracks, dynamo to the turret ring, steam engine to a shell hoist that lifts shells to the breech."
  - State the size steps: "the 2-crew tank is longer than the 1-crew tank; the 3-crew tank is longer still, with secondary turrets", and "a wall between engine rooms".
- **Siege (single wheel):** "workers walk at the bottom inside the wheel", and name the tower count.
- **Fishing layout:** "four equal lanes; keep the right third of each lane open water".

About $2.83 is left.

## How these notes were checked

Claude looked at every image. Then three independent reviewers, one per concept, tried to refute the notes against the images and the manifest. They checked 103 claims and found 19 to fix, mostly overstatements, and all are corrected here.
