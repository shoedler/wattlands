## What changed and why

<!-- Link the issue if there is one. -->

## How you tested it

- [ ] `tools/gate check --contributor`
- [ ] `tools/gate fast --contributor`, or these narrower tests:
- [ ] `tools/gate matrix --game=<id>` if a game with `tests/games/<id>/sim/run_sims.sh` changed

**Not tested:** <!-- A real trainer, a real relay, how it sounds or looks on a real screen, anything else. Saying so is fine. -->

## Safety

- [ ] This doesn't touch the trainer stack, or if it does, I've said how a rider's load could change.
- [ ] No limit, test or assertion was lowered, skipped or removed to get to green.

## AI

- [ ] An AI agent helped with this, and I've read the diff and seen the test results myself. <!-- Delete this if none did. -->
