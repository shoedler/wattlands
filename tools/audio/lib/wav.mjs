// RIFF PCM16 read and write. Nothing else: no float, no 8-bit, no extra chunks on write, so a
// rendered file is a pure function of its samples.

const HEADER_BYTES = 44;

/** Interleaved Int16Array -> a canonical 44-byte-header WAV. */
export function encodeWav(samples, { rate, ch }) {
  const dataBytes = samples.length * 2;
  const b = Buffer.alloc(HEADER_BYTES + dataBytes);
  b.write('RIFF', 0, 'ascii');
  b.writeUInt32LE(36 + dataBytes, 4);
  b.write('WAVE', 8, 'ascii');
  b.write('fmt ', 12, 'ascii');
  b.writeUInt32LE(16, 16);
  b.writeUInt16LE(1, 20);
  b.writeUInt16LE(ch, 22);
  b.writeUInt32LE(rate, 24);
  b.writeUInt32LE(rate * ch * 2, 28);
  b.writeUInt16LE(ch * 2, 32);
  b.writeUInt16LE(16, 34);
  b.write('data', 36, 'ascii');
  b.writeUInt32LE(dataBytes, 40);
  for (let i = 0; i < samples.length; i++) b.writeInt16LE(samples[i], HEADER_BYTES + i * 2);
  return b;
}

/** A WAV buffer -> {rate, ch, frames, samples (interleaved Int16Array)}. Throws on anything but PCM16. */
export function decodeWav(buf) {
  if (buf.length < 12 || buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') {
    throw new Error('not a RIFF/WAVE file');
  }
  let at = 12;
  let fmt = null;
  while (at + 8 <= buf.length) {
    const id = buf.toString('ascii', at, at + 4);
    const size = buf.readUInt32LE(at + 4);
    const body = at + 8;
    if (id === 'fmt ') {
      fmt = { tag: buf.readUInt16LE(body), ch: buf.readUInt16LE(body + 2), rate: buf.readUInt32LE(body + 4), bits: buf.readUInt16LE(body + 14) };
    } else if (id === 'data') {
      if (!fmt) throw new Error('data chunk before fmt chunk');
      if (fmt.tag !== 1 || fmt.bits !== 16) throw new Error(`only PCM16 is supported (tag ${fmt.tag}, ${fmt.bits} bits)`);
      const count = Math.floor(Math.min(size, buf.length - body) / 2);
      const samples = new Int16Array(count);
      for (let i = 0; i < count; i++) samples[i] = buf.readInt16LE(body + i * 2);
      return { rate: fmt.rate, ch: fmt.ch, frames: Math.floor(count / fmt.ch), samples };
    }
    at = body + size + (size & 1);
  }
  throw new Error('no data chunk');
}

/** Interleaved Int16Array -> one Float64Array per channel, in [-1, 1). */
export function deinterleave(samples, ch) {
  const frames = Math.floor(samples.length / ch);
  const out = [];
  for (let c = 0; c < ch; c++) {
    const x = new Float64Array(frames);
    for (let i = 0; i < frames; i++) x[i] = samples[i * ch + c] / 32768;
    out.push(x);
  }
  return out;
}
