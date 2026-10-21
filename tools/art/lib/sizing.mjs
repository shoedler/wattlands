// Request sizing (BRIEF 3.10): one request per sprite at the endpoint's nearest valid size with the
// sprite's aspect. Valid means both sides multiples of `multiple`, at least `min_pixels`, at most
// `max_pixels`, `max_edge` per side and `max_aspect` (long side / short side). A sprite whose aspect
// lies beyond `max_aspect` is requested at the nearest allowed aspect and flagged `outside_limits`.

/** Aspect errors this close (relative) count as equally good; the size nearest target_pixels wins. */
export const ASPECT_TIE = 0.0005;

function candidates(limits, aspect, maxPixels) {
  const m = limits.multiple;
  const out = [];
  for (let h = m; h <= limits.max_edge; h += m) {
    const ideal = h * aspect;
    const lo = Math.max(m, Math.floor(ideal / m) * m);
    for (const w of new Set([lo, lo + m])) {
      if (w > limits.max_edge) continue;
      const px = w * h;
      if (px < limits.min_pixels || px > maxPixels) continue;
      if (Math.max(w / h, h / w) > limits.max_aspect + 1e-12) continue;
      out.push({ w, h, px });
    }
  }
  return out;
}

/**
 * Plans the request size for a sprite of `size` [w, h] (art pixels).
 * Returns {width, height, pixels, sprite_aspect, request_aspect, target_aspect,
 * aspect_error_pct, outside_limits}. aspect_error_pct compares the request with the sprite:
 * (request aspect / sprite aspect - 1) * 100.
 */
export function planRequestSize(size, limits) {
  const [sw, sh] = size;
  if (!(sw > 0 && sh > 0)) throw new Error(`sprite size must be positive, got ${JSON.stringify(size)}`);
  const spriteAspect = sw / sh;
  const target = Math.min(Math.max(spriteAspect, 1 / limits.max_aspect), limits.max_aspect);
  const outside = Math.abs(target / spriteAspect - 1) > 1e-9;
  let list = candidates(limits, target, Math.min(limits.max_request_pixels, limits.max_pixels));
  if (list.length === 0) list = candidates(limits, target, limits.max_pixels);
  if (list.length === 0) throw new Error(`no valid request size for aspect ${target.toFixed(4)} within the endpoint limits`);
  const err = (c) => Math.abs(Math.log(c.w / c.h / target));
  const minErr = Math.min(...list.map(err));
  const near = list.filter((c) => err(c) <= minErr + ASPECT_TIE);
  near.sort((a, b) => {
    const da = Math.abs(Math.log(a.px / limits.target_pixels));
    const db = Math.abs(Math.log(b.px / limits.target_pixels));
    if (da !== db) return da - db;
    return b.w - a.w || b.h - a.h;
  });
  const best = near[0];
  const requestAspect = best.w / best.h;
  return {
    width: best.w,
    height: best.h,
    pixels: best.px,
    sprite_aspect: spriteAspect,
    target_aspect: target,
    request_aspect: requestAspect,
    aspect_error_pct: (requestAspect / spriteAspect - 1) * 100,
    outside_limits: outside,
  };
}

/** True when [w, h] satisfies every limit (used by tests and the mock's own check). */
export function isValidRequestSize(w, h, limits) {
  const m = limits.multiple;
  return (
    Number.isInteger(w) &&
    Number.isInteger(h) &&
    w % m === 0 &&
    h % m === 0 &&
    w > 0 &&
    h > 0 &&
    w <= limits.max_edge &&
    h <= limits.max_edge &&
    w * h >= limits.min_pixels &&
    w * h <= limits.max_pixels &&
    Math.max(w / h, h / w) <= limits.max_aspect + 1e-12
  );
}
