#!/usr/bin/env python3
"""Generate Wattlands concept art on fal.ai with your own FAL_KEY.

Default run (round 1): 3 concepts x 4 styles x 2 models = 24 images, about $1.70.

    python3 tools/concept_art/wattlands_concept_art.py --dry-run   # plan and cost only
    python3 tools/concept_art/wattlands_concept_art.py             # generate

Examples for later rounds:

    # Nano Banana Pro versions of two favourites, as a second variant
    python3 tools/concept_art/wattlands_concept_art.py --models nbpro --concepts tank,siege --styles cel --tag v2

Images (JPEG by default), manifest.json and an index.html contact sheet go to
docs/concept/ in this repo (change with --out). Existing files are skipped, so
a re-run only pays for what is missing; --tag makes new variants instead.
manifest.json keeps every image's prompt, model, request id and estimated cost.

Needs Python 3.8+ and nothing else. FAL_KEY is read from the environment and is
never printed or written anywhere.
"""

import argparse
import base64
import html
import json
import os
import sys
import threading
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

QUEUE_BASE = os.environ.get("FAL_QUEUE_BASE", "https://queue.fal.run")

# Estimated USD per image (fal.ai/pricing, 17 Oct 2026). FLUX 3 bills per
# megapixel ($0.048/MP); a 16:9 "1k" image is about 1 MP, so $0.06 is a safe estimate.
MODELS = {
    "nb2": {
        "id": "fal-ai/nano-banana-2",
        "label": "Nano Banana 2",
        "usd": 0.08,
        "args": {"aspect_ratio": "16:9", "resolution": "1K", "num_images": 1},
    },
    "flux3": {
        "id": "blackforestlabs/flux-3/text-to-image",
        "label": "FLUX 3",
        "usd": 0.06,
        "args": {"aspect_ratio": "16:9", "resolution": "1k"},
    },
    "nbpro": {
        "id": "fal-ai/nano-banana-pro",
        "label": "Nano Banana Pro",
        "usd": 0.15,
        "args": {"aspect_ratio": "16:9", "resolution": "1K", "num_images": 1},
    },
}

STYLES = {
    "lowpoly": (
        "Low-poly diorama",
        "Stylized low-poly 3D game concept art: a toy-like diorama seen from a high three-quarter "
        "angle with a gentle tilt-shift look, chunky simple shapes with flat-shaded facets, bright "
        "saturated colors, soft global illumination and clean readable silhouettes.",
    ),
    "cel": (
        "Cel-shaded cartoon",
        "Bold cel-shaded 3D cartoon game concept art: thick dark ink outlines, flat colors with crisp "
        "two-tone shadows, a punchy comic-book palette, a dynamic low camera angle, energetic and funny.",
    ),
    "painterly": (
        "Painterly storybook",
        "Painterly storybook illustration for a cozy indie game: gouache and watercolor textures, "
        "visible brush strokes, warm golden light, soft edges, whimsical and richly detailed.",
    ),
    "pixel": (
        "16-bit pixel art",
        "Detailed 16-bit pixel art like a retro console game screenshot: crisp square pixels, a "
        "limited vibrant palette, a three-quarter top-down view, small expressive characters and "
        "playful arcade charm.",
    ),
}

CONCEPTS = {
    "siege": (
        "Generator Siege",
        "A co-op tower-defense battle powered by pedaling. On a grassy hilltop stands the Dynamo, a "
        "giant glowing generator with spinning copper coils, at the heart of the base. Around it, "
        "small open-sided pedal huts each hold a cyclist pedaling hard on a stationary bike, and thick "
        "glowing power cables run from each hut to a defense tower: a crackling tesla-coil tower, a "
        "crossbow ballista built from bicycle wheels and spokes, and a giant fan tower blowing a "
        "visible gust of wind. Swarms of rusty scrap-metal beetles and slimy grease slugs crawl up "
        "three winding dirt paths toward the base, led by a hulking robot made of junk. Sparks, "
        "lightning arcs and flying bolts in late-afternoon light.",
    ),
    "tank": (
        "Tank Crew",
        "A whimsical pedal-powered tank crewed by three cyclists rumbles through a scrapyard. The "
        "driver pedals a bike bolted inside the open hull, with bicycle chains driving the big "
        "treads; the gunner pedals a hydraulic pump with brass pistons and pressure gauges that "
        "swings the turret; the loader runs inside a big hamster wheel that winds a giant clockwork "
        "spring, with a huge wind-up key on the side of the cannon. The cannon fires a glowing shell "
        "at a flock of rusty scrap drones, while a towering walking robot built from junk looms in "
        "the hazy background. Dust, puffs of steam and flying sparks.",
    ),
    "fishing": (
        "Big Game Fishing",
        "Big-game fishing from a sport-fishing boat on a turquoise ocean near a coral reef at "
        "sunrise. A cyclist on a stationary bike sits in the boat's fighting chair, and the bike's "
        "crank drives a huge fishing reel; the rod bends hard as a blue marlin leaps out of the water "
        "in a burst of spray. A second rider on another bike-powered reel fights a tuna on the other "
        "side of the deck. Seagulls circle over a bait ball, calm swell, warm morning light.",
    ),
}

COMMON = (
    "The riders are everyday cyclists in plain jerseys and helmets. Wide 16:9 game concept art "
    "without any user interface. No text, letters, numbers, logos, brand names or watermarks."
)

print_lock = threading.Lock()


def log(message):
    with print_lock:
        print(message, flush=True)


class FatalError(Exception):
    """Stops the whole run (bad key, no credits)."""


def default_out_dir():
    repo = Path(__file__).resolve().parents[2]
    if (repo / "docs").is_dir():
        return repo / "docs" / "concept"
    return Path.home() / "Pictures" / "wattlands-concept-art"


def http_json(method, url, key, body=None, timeout=60):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", "Key " + key)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", "replace")[:400]
        if error.code in (401, 403):
            raise FatalError("fal rejected the request (HTTP %d). Check FAL_KEY. %s" % (error.code, detail))
        if error.code == 402 or "balance" in detail.lower() or "credit" in detail.lower():
            raise FatalError("fal says the account is out of credits (HTTP %d). %s" % (error.code, detail))
        raise RuntimeError("HTTP %d from %s: %s" % (error.code, url.split("?")[0], detail))


def download(url, path):
    if url.startswith("data:"):
        path.write_bytes(base64.b64decode(url.split(",", 1)[1]))
        return
    with urllib.request.urlopen(url, timeout=120) as response:
        path.write_bytes(response.read())


def run_job(job, key, out_dir, image_format):
    model = MODELS[job["model"]]
    body = dict(model["args"])
    body["output_format"] = image_format
    body["prompt"] = job["prompt"]
    submitted = http_json("POST", "%s/%s" % (QUEUE_BASE, model["id"]), key, body)
    status_url = submitted.get("status_url")
    response_url = submitted.get("response_url")
    if not status_url or not response_url:
        raise RuntimeError("unexpected submit response: %s" % json.dumps(submitted)[:300])
    deadline = time.time() + 420
    while True:
        status = http_json("GET", status_url, key).get("status")
        if status == "COMPLETED":
            break
        if status not in ("IN_QUEUE", "IN_PROGRESS"):
            raise RuntimeError("request ended with status %r" % status)
        if time.time() > deadline:
            raise RuntimeError("timed out after 7 minutes")
        time.sleep(2)
    result = http_json("GET", response_url, key)
    images = result.get("images") or []
    if not images or not images[0].get("url"):
        raise RuntimeError("no image in the result: %s" % json.dumps(result)[:300])
    download(images[0]["url"], out_dir / job["file"])
    job["request_id"] = submitted.get("request_id")
    job["width"] = images[0].get("width")
    job["height"] = images[0].get("height")
    job["created"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    return job


def write_contact_sheet(out_dir, records):
    sections = []
    for concept_key, (concept_title, _) in CONCEPTS.items():
        cells = sorted(
            (r for r in records if r.get("concept") == concept_key and (out_dir / r["file"]).exists()),
            key=lambda r: (list(STYLES).index(r["style"]) if r.get("style") in STYLES else 99, r["file"]),
        )
        if not cells:
            continue
        figures = "".join(
            '<figure><a href="%s"><img src="%s" alt="%s" loading="lazy"></a>'
            "<figcaption>%s · %s%s</figcaption></figure>"
            % (
                html.escape(r["file"]),
                html.escape(r["file"]),
                html.escape("%s, %s, %s" % (concept_title, r.get("style_label", ""), r.get("model_label", ""))),
                html.escape(r.get("style_label", "")),
                html.escape(r.get("model_label", "")),
                html.escape(" · " + r["tag"]) if r.get("tag") else "",
            )
            for r in cells
        )
        sections.append("<h2>%s</h2><div class='grid'>%s</div>" % (html.escape(concept_title), figures))
    page = (
        "<!doctype html><meta charset='utf-8'><title>Wattlands concept art</title>"
        "<style>body{font:15px system-ui,sans-serif;margin:24px;background:#111;color:#eee}"
        ".grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(420px,1fr));gap:16px}"
        "figure{margin:0}img{width:100%;border-radius:8px;display:block}"
        "figcaption{margin-top:6px;color:#bbb}h2{margin:32px 0 12px}</style>"
        "<h1>Wattlands concept art</h1>" + "".join(sections)
    )
    (out_dir / "index.html").write_text(page, encoding="utf-8")


def main():
    parser = argparse.ArgumentParser(description="Generate Wattlands concept art on fal.ai.")
    parser.add_argument("--out", default=str(default_out_dir()))
    parser.add_argument("--models", default="nb2,flux3", help="comma list from: " + ",".join(MODELS))
    parser.add_argument("--concepts", default=",".join(CONCEPTS), help="comma list from: " + ",".join(CONCEPTS))
    parser.add_argument("--styles", default=",".join(STYLES), help="comma list from: " + ",".join(STYLES))
    parser.add_argument("--tag", default="", help="suffix for new variants, e.g. v2 (files never overwrite)")
    parser.add_argument("--format", default="jpeg", choices=["jpeg", "png"])
    parser.add_argument("--budget", type=float, default=2.50, help="stop before this run's estimated spend passes this (USD)")
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    out_dir = Path(args.out).expanduser()
    picks = {
        "models": [m.strip() for m in args.models.split(",") if m.strip()],
        "concepts": [c.strip() for c in args.concepts.split(",") if c.strip()],
        "styles": [s.strip() for s in args.styles.split(",") if s.strip()],
    }
    for kind, table in (("models", MODELS), ("concepts", CONCEPTS), ("styles", STYLES)):
        unknown = [x for x in picks[kind] if x not in table]
        if unknown:
            sys.exit("Unknown %s: %s (choose from %s)" % (kind, ", ".join(unknown), ", ".join(table)))
    tag = "".join(ch for ch in args.tag if ch.isalnum() or ch in "-_")
    extension = "jpg" if args.format == "jpeg" else "png"

    jobs = []
    for model_key in picks["models"]:  # every concept and style for the first model, then the next
        for concept_key in picks["concepts"]:
            for style_key in picks["styles"]:
                stem = "%s_%s_%s" % (concept_key, style_key, model_key) + ("_" + tag if tag else "")
                jobs.append({
                    "concept": concept_key,
                    "style": style_key,
                    "style_label": STYLES[style_key][0],
                    "model": model_key,
                    "model_label": MODELS[model_key]["label"],
                    "model_id": MODELS[model_key]["id"],
                    "tag": tag,
                    "est_usd": MODELS[model_key]["usd"],
                    "file": "%s.%s" % (stem, extension),
                    "prompt": " ".join([STYLES[style_key][1], CONCEPTS[concept_key][1], COMMON]),
                })

    manifest_path = out_dir / "manifest.json"
    previous = {}
    if manifest_path.exists():
        try:
            previous = {r["file"]: r for r in json.loads(manifest_path.read_text(encoding="utf-8")).get("images", [])}
        except (ValueError, KeyError):
            previous = {}

    todo, skipped, planned_usd = [], [], 0.0
    for job in jobs:
        if (out_dir / job["file"]).exists():
            skipped.append(job)
        elif planned_usd + job["est_usd"] <= args.budget + 1e-9:
            todo.append(job)
            planned_usd += job["est_usd"]
    over_budget = len(jobs) - len(skipped) - len(todo)

    print("Output folder: %s" % out_dir)
    print("Planned: %d new images, about $%.2f (budget $%.2f); %d already there; %d left out by the budget."
          % (len(todo), planned_usd, args.budget, len(skipped), over_budget))
    if args.dry_run:
        for job in todo:
            print("  %-40s %-16s $%.2f" % (job["file"], job["model_label"], job["est_usd"]))
        return
    if not todo:
        return

    key = os.environ.get("FAL_KEY", "").strip()
    if not key:
        sys.exit("FAL_KEY is not set in this shell. Export it and try again.")
    out_dir.mkdir(parents=True, exist_ok=True)

    records = dict(previous)
    done, failed, fatal, spent = [], [], [], 0.0
    stop = threading.Event()

    def save_manifest():
        kept = [r for f, r in sorted(records.items()) if (out_dir / f).exists()]
        total = sum(float(r.get("est_usd", 0)) for r in kept)
        manifest_path.write_text(
            json.dumps({"est_total_usd": round(total, 2), "images": kept, "failed_last_run": failed}, indent=2),
            encoding="utf-8",
        )
        return total

    def worker(job):
        if stop.is_set():
            return None
        started = time.time()
        try:
            run_job(job, key, out_dir, args.format)
            return ("ok", job, time.time() - started)
        except FatalError as error:
            stop.set()
            return ("fatal", job, str(error))
        except Exception as error:  # keep going with the other images
            return ("error", job, str(error))

    with ThreadPoolExecutor(max_workers=max(1, args.workers)) as pool:
        for index, outcome in enumerate(pool.map(worker, todo), start=1):
            if outcome is None:
                continue
            kind, job, info = outcome
            if kind == "ok":
                records[job["file"]] = job
                done.append(job)
                spent += job["est_usd"]
                log("[%d/%d] %s (%s) done in %.0f s, about $%.2f so far"
                    % (index, len(todo), job["file"], job["model_label"], info, spent))
            else:
                failed.append({"file": job["file"], "error": info})
                if kind == "fatal":
                    fatal.append(info)
                log("[%d/%d] %s FAILED: %s" % (index, len(todo), job["file"], info))
            save_manifest()

    total = save_manifest()
    write_contact_sheet(out_dir, list(records.values()))
    print()
    print("Finished: %d new images, %d failed, about $%.2f spent this run, about $%.2f for all images in the folder."
          % (len(done), len(failed), spent, total))
    print("Contact sheet: %s" % (out_dir / "index.html"))
    if fatal:
        print("Stopped early: %s" % fatal[0])
        sys.exit(1)


if __name__ == "__main__":
    main()
