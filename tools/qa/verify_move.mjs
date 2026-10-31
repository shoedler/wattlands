#!/usr/bin/env node
// tools/qa/verify_move.mjs: proves a split of a GDScript file moved code without changing it.
//
//   node tools/qa/verify_move.mjs --base=<rev> --from=<old path> --to=<path,path,...> [--allow=<name,...>]
//
// Run it from the repo root, after gdformat. It parses `git show <base>:<from>` and the --to files (work tree) into
// top-level blocks: func and static func (signature through last body line, trailing blanks cut), and const, var,
// static var, enum, signal and class blocks, each with its annotations and the comment lines directly above it.
// Every old block must occur byte-identical exactly once across the targets. An --allow name may differ (it prints a
// one-line diff count) but must still exist. `# --- x ---` headers and class_name and extends lines are not blocks.
// Extra new blocks and any other dropped comment line are printed and do not fail. Exit 0 or 1; 2 on bad flags.
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const DECL = /^(?:(?:@\w+(?:\([^)]*\))?\s+)*)(static\s+func|func|static\s+var|var|const|enum|signal|class)\b\s*(\w*)/;
const NOT_BLOCK = /^(?:class_name|extends)\b/;
const HEADER = /^#\s*-{3,}/;
const CLOSER = /^[)\]}]/;

export const normalise = (text) => text.replace(/\r\n?/g, '\n');

const isComment = (line) => line.startsWith('#');
const isAnnotationLine = (line) => /^@\w+(?:\(.*\))?\s*$/.test(line);
const isIndented = (line) => /^[ \t]/.test(line);
const isBlank = (line) => line.trim() === '';

/** Whether a triple-quoted string is still open after `line`, given whether one was open before it. */
function triple(open, line) {
  const n = line.split('"""').length - 1;
  return n % 2 === 1 ? !open : open;
}

/**
 * Splits GDScript into `{ blocks: [{ name, kind, text }], loose: [comment lines] }`. Text has LF line ends.
 * A col-0 comment run followed by an indented line stays in the body it interrupts; a run directly above a
 * declaration or annotation belongs to that block; anything else is loose.
 */
export function parseBlocks(source) {
  const lines = normalise(source).split('\n');
  const blocks = [];
  const loose = [];
  let pending = [];
  const flushPending = () => {
    for (const l of pending) if (isComment(l) && !HEADER.test(l)) loose.push(l);
    pending = [];
  };
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    if (isBlank(line)) {
      flushPending();
      i += 1;
      continue;
    }
    if (isComment(line) || isAnnotationLine(line)) {
      if (HEADER.test(line)) flushPending();
      else pending.push(line);
      i += 1;
      continue;
    }
    if (NOT_BLOCK.test(line)) {
      flushPending();
      i += 1;
      continue;
    }
    const m = line.match(DECL);
    if (!m) {
      flushPending();
      i += 1;
      continue;
    }
    const kind = m[1].replace(/\s+/, ' ');
    let name = m[2];
    let end = i;
    let open = triple(false, line);
    let j = i + 1;
    while (j < lines.length) {
      const l = lines[j];
      if (open) {
        open = triple(open, l);
        end = j;
        j += 1;
        continue;
      }
      if (isIndented(l) && !isBlank(l)) {
        open = triple(open, l);
        end = j;
        j += 1;
        continue;
      }
      if (CLOSER.test(l)) {
        end = j;
        j += 1;
        continue;
      }
      if (isBlank(l)) {
        j += 1;
        continue;
      }
      if (isComment(l)) {
        // A col-0 comment run inside a body: the next code line decides.
        let k = j;
        while (k < lines.length && (isComment(lines[k]) || isBlank(lines[k]))) k += 1;
        if (k < lines.length && isIndented(lines[k])) {
          end = k - 1;
          j = k;
          continue;
        }
      }
      break;
    }
    if (name === '') name = `${kind}@${line.trim()}`;
    const text = [...pending, ...lines.slice(i, end + 1)].join('\n');
    blocks.push({ name, kind, text });
    pending = [];
    i = end + 1;
  }
  flushPending();
  return { blocks, loose };
}

/** A one-line diff count: lines only in `a`, lines only in `b`. */
export function diffCount(a, b) {
  const count = new Map();
  for (const l of a.split('\n')) count.set(l, (count.get(l) || 0) + 1);
  let removed = 0;
  let added = 0;
  for (const l of b.split('\n')) {
    const n = count.get(l) || 0;
    if (n > 0) count.set(l, n - 1);
    else added += 1;
  }
  for (const n of count.values()) removed += n;
  return { removed, added };
}

/**
 * Compares one old source to its targets (`[{ path, text }]`). Returns `{ ok, errors, allowed, extra, droppedComments }`.
 */
export function verify(oldText, targets, allow = []) {
  const old = parseBlocks(oldText);
  const parsed = targets.map((t) => ({ path: t.path, ...parseBlocks(t.text) }));
  const byText = new Map();
  const byName = new Map();
  for (const t of parsed) {
    for (const b of t.blocks) {
      if (!byText.has(b.text)) byText.set(b.text, []);
      byText.get(b.text).push(t.path);
      if (!byName.has(b.name)) byName.set(b.name, []);
      byName.get(b.name).push({ path: t.path, text: b.text });
    }
  }
  const errors = [];
  const allowed = [];
  const allowSet = new Set(allow);
  const oldTexts = new Set(old.blocks.map((b) => b.text));
  const oldNames = new Set(old.blocks.map((b) => b.name));
  for (const b of old.blocks) {
    const hits = byText.get(b.text) || [];
    if (hits.length === 1) continue;
    const named = byName.get(b.name) || [];
    if (hits.length > 1) {
      errors.push(`${b.kind} ${b.name}: occurs ${hits.length} times (${hits.join(', ')})`);
    } else if (named.length === 0) {
      errors.push(`${b.kind} ${b.name}: dropped`);
    } else if (allowSet.has(b.name) && named.length === 1) {
      const d = diffCount(b.text, named[0].text);
      allowed.push(`${b.kind} ${b.name}: allowed, -${d.removed} +${d.added} lines in ${named[0].path}`);
    } else {
      const d = diffCount(b.text, named[0].text);
      errors.push(`${b.kind} ${b.name}: changed, -${d.removed} +${d.added} lines in ${named[0].path}`);
    }
  }
  const extra = [];
  for (const t of parsed) {
    for (const b of t.blocks) {
      if (!oldTexts.has(b.text) && !oldNames.has(b.name)) extra.push(`${b.kind} ${b.name} in ${t.path}`);
    }
  }
  const newLines = new Set(targets.flatMap((t) => normalise(t.text).split('\n')));
  const droppedComments = old.loose.filter((l) => !newLines.has(l));
  return { ok: errors.length === 0, errors, allowed, extra, droppedComments };
}

function parseArgs(argv) {
  const o = {};
  for (const a of argv) {
    const m = a.match(/^--(base|from|to|allow)=(.*)$/);
    if (!m) throw new Error(`unknown flag ${a}`);
    o[m[1]] = m[2];
  }
  if (!o.base || !o.from || !o.to) throw new Error('--base, --from and --to are required');
  return o;
}

function main(argv) {
  let o;
  try {
    o = parseArgs(argv);
  } catch (e) {
    process.stderr.write(`verify_move: ${e.message}\n`);
    return 2;
  }
  const from = o.from.replaceAll('\\', '/');
  const shown = spawnSync('git', ['show', `${o.base}:${from}`], { encoding: 'utf8', maxBuffer: 1 << 28 });
  if (shown.status !== 0) {
    process.stderr.write(`verify_move: git show ${o.base}:${from} failed: ${shown.stderr}\n`);
    return 2;
  }
  const targets = [];
  for (const p of o.to.split(',').filter(Boolean)) {
    try {
      targets.push({ path: p, text: fs.readFileSync(path.resolve(p), 'utf8') });
    } catch (e) {
      process.stderr.write(`verify_move: cannot read ${p}: ${e.message}\n`);
      return 2;
    }
  }
  const r = verify(shown.stdout, targets, (o.allow || '').split(',').filter(Boolean));
  for (const l of r.allowed) process.stdout.write(`${l}\n`);
  for (const l of r.extra) process.stdout.write(`new block: ${l}\n`);
  for (const l of r.droppedComments) process.stdout.write(`dropped comment: ${l}\n`);
  for (const l of r.errors) process.stdout.write(`FAIL ${l}\n`);
  process.stdout.write(`verify_move: ${r.ok ? 'ok' : `${r.errors.length} problem(s)`}\n`);
  return r.ok ? 0 : 1;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main(process.argv.slice(2)));
}
