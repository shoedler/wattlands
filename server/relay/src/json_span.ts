// Locates the raw text of one top-level member of a JSON object, so the relay forwards a
// message's "d" byte for byte without re-encoding it (it never looks inside "d", and large
// integers or number spellings like 1.0 survive unchanged).

/**
 * For `text`, a JSON object that JSON.parse already accepted, return the [start, end)
 * span of the value of the last top-level member named `key` (JSON.parse also keeps the
 * last duplicate), or null when there is none.
 */
export function memberSpan(text: string, key: string): [number, number] | null {
  let i = skipWs(text, 0);
  if (text[i] !== '{') return null;
  i = skipWs(text, i + 1);
  if (text[i] === '}') return null;
  let found: [number, number] | null = null;
  while (i < text.length) {
    if (text[i] !== '"') return null;
    const keyEnd = skipString(text, i);
    const name = JSON.parse(text.slice(i, keyEnd)) as string;
    i = skipWs(text, keyEnd);
    if (text[i] !== ':') return null;
    i = skipWs(text, i + 1);
    const start = i;
    const end = skipValue(text, i);
    if (name === key) found = [start, end];
    i = skipWs(text, end);
    if (text[i] === ',') {
      i = skipWs(text, i + 1);
      continue;
    }
    return text[i] === '}' ? found : null;
  }
  return null;
}

function skipWs(text: string, i: number): number {
  while (i < text.length) {
    const c = text.charCodeAt(i);
    if (c !== 0x20 && c !== 0x09 && c !== 0x0a && c !== 0x0d) break;
    i++;
  }
  return i;
}

/** `text[i]` is an opening quote; returns the index after the closing quote. */
function skipString(text: string, i: number): number {
  let j = i + 1;
  while (j < text.length) {
    const c = text.charCodeAt(j);
    if (c === 0x5c) j += 2;
    else if (c === 0x22) return j + 1;
    else j++;
  }
  return j;
}

function skipValue(text: string, i: number): number {
  const c = text[i];
  if (c === '"') return skipString(text, i);
  if (c === '{' || c === '[') {
    let depth = 0;
    let j = i;
    while (j < text.length) {
      const ch = text[j];
      if (ch === '"') {
        j = skipString(text, j);
        continue;
      }
      if (ch === '{' || ch === '[') depth++;
      else if (ch === '}' || ch === ']') depth--;
      j++;
      if (depth === 0) return j;
    }
    return j;
  }
  let j = i;
  while (j < text.length) {
    const ch = text[j];
    if (ch === ',' || ch === '}' || ch === ']' || ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r') break;
    j++;
  }
  return j;
}
