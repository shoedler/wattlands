// multipart/form-data parser for the mock Strava server. Zero dependencies.

/** The boundary parameter of a multipart Content-Type header, or null. */
export function boundaryOf(contentType) {
  if (!contentType || !/^multipart\/form-data/i.test(contentType)) return null;
  const m = /boundary=(?:"([^"]+)"|([^;\s]+))/i.exec(contentType);
  return m ? (m[1] ?? m[2]) : null;
}

/**
 * Parses a multipart body.
 * @param {Buffer} body
 * @param {string} boundary
 * @returns {{fields: Record<string,string>, files: Record<string,{filename: string,
 *   contentType: string|null, data: Buffer}>}}
 * @throws {Error} on a malformed body
 */
export function parseMultipart(body, boundary) {
  const delim = Buffer.from(`--${boundary}`);
  const fields = {};
  const files = {};
  let pos = body.indexOf(delim);
  if (pos < 0) throw new Error('no opening boundary');
  for (;;) {
    pos += delim.length;
    // "--" after a boundary ends the body.
    if (body[pos] === 0x2d && body[pos + 1] === 0x2d) break;
    if (body[pos] !== 0x0d || body[pos + 1] !== 0x0a) throw new Error('boundary not followed by CRLF');
    pos += 2;
    const headerEnd = body.indexOf('\r\n\r\n', pos);
    if (headerEnd < 0) throw new Error('part without a header end');
    const headers = {};
    for (const line of body.subarray(pos, headerEnd).toString('utf8').split('\r\n')) {
      const colon = line.indexOf(':');
      if (colon > 0) headers[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim();
    }
    const dataStart = headerEnd + 4;
    const next = body.indexOf(Buffer.concat([Buffer.from('\r\n'), delim]), dataStart);
    if (next < 0) throw new Error('part without a closing boundary');
    const data = body.subarray(dataStart, next);
    const disp = headers['content-disposition'] ?? '';
    const name = /\bname="([^"]*)"/i.exec(disp)?.[1];
    const filename = /\bfilename="([^"]*)"/i.exec(disp)?.[1];
    if (name === undefined) throw new Error('part without a name');
    if (filename !== undefined) {
      files[name] = { filename, contentType: headers['content-type'] ?? null, data: Buffer.from(data) };
    } else {
      fields[name] = data.toString('utf8');
    }
    pos = next + 2;
  }
  return { fields, files };
}
