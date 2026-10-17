# Concept art

These images were generated on fal.ai. Round 2 uses OpenAI's GPT Image 2.5 Sunburst; round 1 has been removed.

- File names follow `<concept>_<subject>.jpg`.
- `manifest.json` records each image's endpoint, full input (prompt, size, quality, format), request id and estimated cost. To regenerate an image, POST its `input` to `https://queue.fal.run/<endpoint>` with `Authorization: Key $FAL_KEY`, then poll the returned `status_url` and fetch `response_url`.
- `index.html` shows all the images side by side.
- `NOTES.md` reviews the current round: what works, what doesn't, and what it means for the brief.

The images are reference for the build: palette, shapes and mood. They are not shipped assets.
