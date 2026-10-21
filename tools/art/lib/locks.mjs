// The art lock (BRIEF 1, 3.10): real fal calls need both FAL_KEY and WATTLANDS_ALLOW_ART=1.
// This module never reads any other lock variable; the network lock governs the app's Strava
// client, not this tool.

export const EXIT_LOCKED = 4;

/**
 * Checks the art lock in `env` (a plain object). Never returns or prints the key itself.
 * Returns {ok, message}.
 */
export function checkArtLock(env) {
  const hasKey = typeof env.FAL_KEY === 'string' && env.FAL_KEY.trim() !== '';
  const allowed = env.WATTLANDS_ALLOW_ART === '1';
  if (hasKey && allowed) return { ok: true, message: '' };
  const missing = [];
  if (!hasKey) missing.push('FAL_KEY is not set');
  if (!allowed) missing.push('WATTLANDS_ALLOW_ART is not 1');
  return {
    ok: false,
    message:
      `generate.mjs: refusing to call fal: ${missing.join(' and ')}.\n` +
      'Real generation needs both FAL_KEY and WATTLANDS_ALLOW_ART=1 in the environment (set by a human, see docs/ART_PIPELINE.md).\n' +
      'Plan without calling anything: --dry-run. Tests: --mock=<url of tools/art/mock_fal>.\n',
  };
}

/**
 * Returns a function that replaces the key, and each ":"-separated part of it that is 4 or more
 * characters long, with "[redacted]". The key is also known without surrounding whitespace (fetch
 * trims header values, so a server echoes the trimmed key; W3 ART-W3-2). With no key it returns
 * text unchanged.
 */
export function makeRedactor(key) {
  if (typeof key !== 'string' || key.trim() === '') return (text) => String(text);
  const variants = new Set([key, key.trim()]);
  const parts = [];
  for (const v of variants) {
    parts.push(v, ...v.split(':').filter((p) => p.length >= 4), ...v.split(':').map((p) => p.trim()).filter((p) => p.length >= 4));
  }
  parts.sort((a, b) => b.length - a.length);
  return (text) => {
    let s = String(text);
    for (const p of parts) s = s.split(p).join('[redacted]');
    return s;
  };
}
