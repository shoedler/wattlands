#!/usr/bin/env node
// tools/art/generate.mjs: generates a game's sprites on fal (BRIEF 3.10). Zero dependencies.
//
//   node tools/art/generate.mjs --game=<id> [--only=<ids>] [--dry-run] [--budget=<usd>]
//        [--reroll=<ids>] [--select=<sprite id>:<request id>] [--mock=<url>] [--root=<dir>]
//
// Real calls need both FAL_KEY and WATTLANDS_ALLOW_ART=1 (the art lock, BRIEF 1); without them it
// refuses unless --mock is given. It contacts only fal's hosts (or the mock) and never prints the key.
// See docs/ART_PIPELINE.md and `--help`.
import { main } from './lib/generate.mjs';

process.exitCode = await main(process.argv.slice(2), process.env);
